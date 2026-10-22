import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/id_generator.dart';
import '../../cart/data/cart_repository.dart';
import '../../cart/models/frequency.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/models/product.dart';
import '../data/order_repository.dart';
import '../models/order_summary.dart';
import '../presentation/widgets/product_thumb.dart';

sealed class OrderDetailState extends Equatable {
  const OrderDetailState();

  @override
  List<Object?> get props => [];
}

class OrderDetailLoading extends OrderDetailState {
  const OrderDetailLoading();
}

class OrderDetailLoaded extends OrderDetailState {
  const OrderDetailLoaded(
    this.order,
    this.products, {
    this.reordering = false,
    this.cancelling = false,
  });

  final OrderSummary order;

  /// A key mapped to null means the lookup failed (render "Item").
  final Map<String, Product?> products;

  /// MA-152 FR-1 — a Reorder is in flight (its button is disabled).
  final bool reordering;

  /// MA-155 FR-7 — a cancel is in flight.
  final bool cancelling;

  OrderDetailLoaded copyWith({OrderSummary? order, bool? reordering, bool? cancelling}) =>
      OrderDetailLoaded(
        order ?? this.order,
        products,
        reordering: reordering ?? this.reordering,
        cancelling: cancelling ?? this.cancelling,
      );

  @override
  List<Object?> get props => [order, products, reordering, cancelling];
}

/// `404 ORDER_NOT_FOUND` — unknown, or another user's (never leaked).
class OrderDetailNotFound extends OrderDetailState {
  const OrderDetailNotFound();
}

class OrderDetailError extends OrderDetailState {
  const OrderDetailError();
}

/// MA-152 FR-1 — what a Reorder achieved; [message] is the SnackBar copy.
class ReorderResult {
  const ReorderResult({required this.added, required this.total, required this.failedNames});

  final int added;
  final int total;

  /// Product names of the lines that failed, in order-line order.
  final List<String> failedNames;

  String get message {
    if (added == 0) return "Couldn't add items to cart. Try again.";
    if (failedNames.isEmpty) return 'Added $total item${total == 1 ? '' : 's'} to cart';
    return "Added $added of $total items to cart. Couldn't add ${failedNames.join(', ')}.";
  }

  /// Even a partial success put something in the cart.
  bool get showViewCart => added > 0;
}

/// MA-155 FR-3 — how a cancel ended; the screen maps it to its SnackBar.
enum CancelOutcome { cancelled, cutoffPassed, notCancellable, failed }

/// MA-146 FR-2 — one order from `GET /orders/{id}`, plus product details.
class OrderDetailCubit extends Cubit<OrderDetailState> {
  OrderDetailCubit({
    required OrderRepository orderRepository,
    required CatalogRepository catalogRepository,
    required CartRepository cartRepository,
    required this.orderId,
  }) : _orders = orderRepository,
       _catalog = catalogRepository,
       _cart = cartRepository,
       super(const OrderDetailLoading());

  final OrderRepository _orders;
  final CatalogRepository _catalog;
  final CartRepository _cart;
  final String orderId;

  /// MA-155 — true once a cancel succeeded here, so the screen can tell My
  /// Orders to reload when it closes.
  bool changed = false;

  /// Shows the skeleton; used on open and after an error.
  Future<void> load() async {
    emit(const OrderDetailLoading());
    await _fetch(keepContentOnError: false);
  }

  /// Pull-to-refresh: keeps the current content until the result arrives,
  /// and keeps it if the refresh fails (like My Orders). Returns false on a
  /// failure, so the screen can say so.
  Future<bool> refresh() => _fetch(keepContentOnError: true);

  Future<bool> _fetch({required bool keepContentOnError}) async {
    try {
      final order = await _orders.getById(orderId);
      final products = await resolveProducts(
        _catalog,
        order.items.map((i) => i.productId).toSet(),
      );
      if (!isClosed) {
        // A refresh mid-Reorder (or mid-cancel) keeps its flag until it ends.
        final (reordering, cancelling) = switch (state) {
          OrderDetailLoaded(:final reordering, :final cancelling) => (reordering, cancelling),
          _ => (false, false),
        };
        emit(
          OrderDetailLoaded(order, products, reordering: reordering, cancelling: cancelling),
        );
      }
      return true;
    } on ApiException catch (e) {
      final notFound = e.statusCode == 404 || e.errorCode == 'ORDER_NOT_FOUND';
      if (notFound) {
        if (!isClosed) emit(const OrderDetailNotFound());
      } else {
        _fail(keepContentOnError);
      }
      return false;
    } catch (_) {
      _fail(keepContentOnError);
      return false;
    }
  }

  /// MA-152 FR-1 — re-adds every line as a one-time cart item. Null (and
  /// no calls) unless loaded and not already reordering.
  ///
  /// Lines are added one at a time, not with `Future.wait` as the spec
  /// suggests: each Cart Service add is a DynamoDB transaction on the cart's
  /// shared META row, so concurrent adds to one cart conflict and fail.
  Future<ReorderResult?> reorder() async {
    final current = state;
    if (current is! OrderDetailLoaded || current.reordering) return null;
    emit(current.copyWith(reordering: true));
    final failed = <String>[];
    for (final line in current.order.items) {
      try {
        // No startDate/slotId: Cart Service rejects them on a ONE_TIME line.
        await _cart.addItem(
          productId: line.productId,
          quantity: line.quantity,
          frequency: Frequency.oneTime,
          idempotencyKey: newHexId(),
        );
      } catch (_) {
        failed.add(productNameFor(current.products, line.productId));
      }
    }
    final now = state;
    if (!isClosed && now is OrderDetailLoaded) emit(now.copyWith(reordering: false));
    final total = current.order.items.length;
    return ReorderResult(added: total - failed.length, total: total, failedNames: failed);
  }

  /// MA-155 FR-3 — cancels with an optional [reason]. Null (and no call)
  /// unless loaded and not already cancelling. On success the screen redraws
  /// from the returned order (no extra GET). A cut-off or not-cancellable
  /// answer reloads the order, so the Cancel action disappears.
  Future<CancelOutcome?> cancel(CancelReason? reason) async {
    final current = state;
    if (current is! OrderDetailLoaded || current.cancelling) return null;
    emit(current.copyWith(cancelling: true));
    try {
      final cancelled = await _orders.cancel(orderId, reason: reason);
      changed = true;
      final now = state;
      if (!isClosed && now is OrderDetailLoaded) {
        emit(now.copyWith(order: cancelled, cancelling: false));
      }
      return CancelOutcome.cancelled;
    } on ApiException catch (e) {
      _stopCancelling();
      switch (e.errorCode) {
        case 'CUTOFF_PASSED':
          await refresh();
          return CancelOutcome.cutoffPassed;
        case 'ORDER_NOT_CANCELLABLE':
          await refresh();
          return CancelOutcome.notCancellable;
      }
      return CancelOutcome.failed;
    } catch (_) {
      _stopCancelling();
      return CancelOutcome.failed;
    }
  }

  void _stopCancelling() {
    final now = state;
    if (!isClosed && now is OrderDetailLoaded) emit(now.copyWith(cancelling: false));
  }

  void _fail(bool keepContent) {
    if (isClosed || (keepContent && state is OrderDetailLoaded)) return;
    emit(const OrderDetailError());
  }
}

/// Parallel Catalog lookups; a failure maps to null, never throws.
Future<Map<String, Product?>> resolveProducts(
  CatalogRepository catalog,
  Iterable<String> ids,
) async {
  final entries = await Future.wait(
    ids.map((id) async {
      try {
        return MapEntry<String, Product?>(id, await catalog.getProduct(id));
      } catch (_) {
        return MapEntry<String, Product?>(id, null);
      }
    }),
  );
  return Map.fromEntries(entries);
}
