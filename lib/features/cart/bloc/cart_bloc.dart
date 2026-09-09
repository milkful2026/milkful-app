import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_client.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/models/product.dart';
import '../data/cart_repository.dart';
import '../models/cart_line_item.dart';
import 'cart_event.dart';
import 'cart_state.dart';

/// MA-123's `CartBloc`. Mirrors `ProductConfigBloc`'s shape — one bloc
/// owning a single screen's several independent async operations.
class CartBloc extends Bloc<CartEvent, CartState> {
  CartBloc({required this._cartRepository, required this._catalogRepository})
    : super(const CartState()) {
    on<CartStarted>(_onStarted);
    // `sequential`, not `restartable`: each write is a full round-trip that
    // depends on and advances `cartVersion`, and `PUT /cart` replaces the
    // whole item list. `restartable` cancels an in-flight write when the
    // next one arrives — which, keyed on event type rather than line item,
    // means editing one row would abort another row's write mid-flight and
    // run its revert/error handling on a dead `Emitter` (a silent no-op).
    // Serializing keeps every write's outcome observable.
    on<QuantityWriteRequested>(_onQuantityWriteRequested, transformer: sequential());
    on<ItemRemoveRequested>(_onItemRemoveRequested);
    on<ItemRemoveCancelled>(_onItemRemoveCancelled);
    on<ItemRemoveConfirmed>(_onItemRemoveConfirmed, transformer: sequential());
  }

  final CartRepository _cartRepository;
  final CatalogRepository _catalogRepository;

  Future<void> _onStarted(CartStarted event, Emitter<CartState> emit) async {
    emit(state.copyWith(loadStatus: CartLoadStatus.loading, clearLoadErrorMessage: true));
    try {
      final view = await _cartRepository.getCart();
      final items = await _resolveProducts(view.items);
      emit(
        state.copyWith(
          loadStatus: CartLoadStatus.loaded,
          items: items,
          cartVersion: view.cartVersion,
          quote: view.quote,
          clearQuote: view.quote == null,
        ),
      );
    } on ApiException catch (e) {
      emit(state.copyWith(loadStatus: CartLoadStatus.failed, loadErrorMessage: e.message));
    } catch (_) {
      emit(state.copyWith(loadStatus: CartLoadStatus.failed));
    }
  }

  /// MA-123 FR-2 — parallel, not sequential; a single failed lookup
  /// degrades only that row (`product: null`), not the whole screen.
  Future<List<CartLineItemView>> _resolveProducts(List<CartLineItem> lineItems) {
    return Future.wait(
      lineItems.map((li) async {
        try {
          final product = await _catalogRepository.getProduct(li.productId);
          return CartLineItemView(lineItem: li, product: product);
        } catch (_) {
          return CartLineItemView(lineItem: li, product: null);
        }
      }),
    );
  }

  /// Reuses already-resolved [Product]s by id rather than re-querying
  /// Catalog Service after every write — product data doesn't change as a
  /// side effect of a quantity edit or removal.
  List<CartLineItemView> _pairWithKnownProducts(List<CartLineItem> lineItems) {
    final knownByProductId = <String, Product?>{
      for (final view in state.items) view.lineItem.productId: view.product,
    };
    return lineItems
        .map((li) => CartLineItemView(lineItem: li, product: knownByProductId[li.productId]))
        .toList();
  }

  Future<void> _onQuantityWriteRequested(
    QuantityWriteRequested event,
    Emitter<CartState> emit,
  ) async {
    final targetExists = state.items.any((v) => v.lineItem.id == event.lineItemId);
    if (!targetExists) return;

    final originalItems = state.items;
    final optimisticItems = state.items
        .map(
          (v) => v.lineItem.id == event.lineItemId
              ? v.copyWith(lineItem: v.lineItem.copyWith(quantity: event.quantity))
              : v,
        )
        .toList();
    emit(state.copyWith(items: optimisticItems, clearWriteErrorMessage: true));

    await _writeQuantity(
      lineItemId: event.lineItemId,
      quantity: event.quantity,
      items: optimisticItems,
      revertItems: originalItems,
      revertVersion: state.cartVersion,
      emit: emit,
      retried: false,
    );
  }

  /// MA-123 FR-6 — a stale `cartVersion` (409) silently refetches and
  /// re-applies the same target quantity once; any other failure reverts
  /// to the last known-good state and surfaces the backend's message.
  ///
  /// [revertItems]/[revertVersion] are always a matched pair describing one
  /// consistent cart snapshot — after a 409 refetch that pair becomes the
  /// freshly-fetched server state, not the pre-edit local snapshot, so a
  /// failed retry can't leave `items` and `cartVersion` describing
  /// different carts (which would let the next write submit a stale list
  /// under a valid `ifVersion` and silently clobber a concurrent change).
  Future<void> _writeQuantity({
    required String lineItemId,
    required int quantity,
    required List<CartLineItemView> items,
    required List<CartLineItemView> revertItems,
    required int revertVersion,
    required Emitter<CartState> emit,
    required bool retried,
  }) async {
    try {
      await _cartRepository.updateItem(
        items: items.map((v) => v.lineItem).toList(),
        ifVersion: state.cartVersion,
      );
      final fresh = await _cartRepository.getCart();
      emit(
        state.copyWith(
          items: _pairWithKnownProducts(fresh.items),
          cartVersion: fresh.cartVersion,
          quote: fresh.quote,
          clearQuote: fresh.quote == null,
        ),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 409 && !retried) {
        final fresh = await _cartRepository.getCart();
        final freshViews = _pairWithKnownProducts(fresh.items);
        final refreshedItems = freshViews
            .map(
              (v) => v.lineItem.id == lineItemId
                  ? v.copyWith(lineItem: v.lineItem.copyWith(quantity: quantity))
                  : v,
            )
            .toList();
        emit(state.copyWith(items: refreshedItems, cartVersion: fresh.cartVersion));
        await _writeQuantity(
          lineItemId: lineItemId,
          quantity: quantity,
          items: refreshedItems,
          revertItems: freshViews,
          revertVersion: fresh.cartVersion,
          emit: emit,
          retried: true,
        );
        return;
      }
      emit(
        state.copyWith(
          items: revertItems,
          cartVersion: revertVersion,
          writeErrorMessage: e.message,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          items: revertItems,
          cartVersion: revertVersion,
          writeErrorMessage: 'Something went wrong',
        ),
      );
    }
  }

  void _onItemRemoveRequested(ItemRemoveRequested event, Emitter<CartState> emit) {
    emit(state.copyWith(pendingRemovalId: event.lineItemId));
  }

  void _onItemRemoveCancelled(ItemRemoveCancelled event, Emitter<CartState> emit) {
    emit(state.copyWith(clearPendingRemovalId: true));
  }

  Future<void> _onItemRemoveConfirmed(
    ItemRemoveConfirmed event,
    Emitter<CartState> emit,
  ) async {
    final originalItems = state.items;
    final remainingItems = state.items
        .where((v) => v.lineItem.id != event.lineItemId)
        .toList();
    emit(
      state.copyWith(
        items: remainingItems,
        clearPendingRemovalId: true,
        clearWriteErrorMessage: true,
      ),
    );

    try {
      await _cartRepository.removeItem(id: event.lineItemId);
      // MA-123 FR-5 — removing the last item skips the extra GET /cart
      // round-trip; the empty state is already fully known locally.
      if (remainingItems.isEmpty) {
        emit(state.copyWith(quote: null, clearQuote: true));
        return;
      }
      final fresh = await _cartRepository.getCart();
      emit(
        state.copyWith(
          items: _pairWithKnownProducts(fresh.items),
          cartVersion: fresh.cartVersion,
          quote: fresh.quote,
          clearQuote: fresh.quote == null,
        ),
      );
    } on ApiException catch (e) {
      emit(state.copyWith(items: originalItems, writeErrorMessage: e.message));
    } catch (_) {
      emit(state.copyWith(items: originalItems, writeErrorMessage: 'Something went wrong'));
    }
  }
}
