import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_client.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/models/product.dart';
import '../data/order_repository.dart';
import '../models/order_summary.dart';

sealed class OrderDetailState extends Equatable {
  const OrderDetailState();

  @override
  List<Object?> get props => [];
}

class OrderDetailLoading extends OrderDetailState {
  const OrderDetailLoading();
}

class OrderDetailLoaded extends OrderDetailState {
  const OrderDetailLoaded(this.order, this.products);

  final OrderSummary order;

  /// A key mapped to null means the lookup failed (render "Item").
  final Map<String, Product?> products;

  @override
  List<Object?> get props => [order, products];
}

/// `404 ORDER_NOT_FOUND` — unknown, or another user's (never leaked).
class OrderDetailNotFound extends OrderDetailState {
  const OrderDetailNotFound();
}

class OrderDetailError extends OrderDetailState {
  const OrderDetailError();
}

/// MA-146 FR-2 — one order from `GET /orders/{id}`, plus product details.
class OrderDetailCubit extends Cubit<OrderDetailState> {
  OrderDetailCubit({
    required OrderRepository orderRepository,
    required CatalogRepository catalogRepository,
    required this.orderId,
  }) : _orders = orderRepository,
       _catalog = catalogRepository,
       super(const OrderDetailLoading());

  final OrderRepository _orders;
  final CatalogRepository _catalog;
  final String orderId;

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
      if (!isClosed) emit(OrderDetailLoaded(order, products));
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
