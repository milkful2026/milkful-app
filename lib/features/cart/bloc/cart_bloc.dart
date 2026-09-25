import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/jwt_claims.dart';
import '../../auth/data/profile_repository.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/models/product.dart';
import '../../checkout/data/checkout_repository.dart';
import '../../checkout/data/pending_checkout_store.dart';
import '../../checkout/models/checkout_failure.dart';
import '../../wallet/data/wallet_repository.dart';
import '../data/cart_repository.dart';
import '../models/cart_line_item.dart';
import '../models/cart_view.dart';
import 'cart_event.dart';
import 'cart_state.dart';

/// MA-123's `CartBloc`, extended by MA-137 into the Review Cart screen's
/// bloc: the cart plus its split pricing, the wallet balance, the saved
/// delivery address, and Confirm Order. Mirrors `ProductConfigBloc`'s
/// shape — one bloc owning a single screen's several independent async
/// operations.
class CartBloc extends Bloc<CartEvent, CartState> {
  CartBloc({
    required this._cartRepository,
    required this._catalogRepository,
    required this._walletRepository,
    required this._profileRepository,
    required this._checkoutRepository,
    required this._pendingCheckoutStore,
    required this._currentUserId,
    this._checkoutRetryDelays = _defaultRetryDelays,
  }) : super(const CartState()) {
    on<CartStarted>(_onStarted);
    on<CartRefreshRequested>(_onRefreshRequested, transformer: restartable());
    on<QuantityEditStarted>(_onQuantityEditStarted);
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
    // `droppable`: a second tap while one Confirm is running is ignored
    // outright (the button is disabled too; this is the belt to its braces).
    on<CheckoutRequested>(_onCheckoutRequested, transformer: droppable());
    on<CheckoutFeedbackConsumed>(_onFeedbackConsumed);
  }

  /// MA-137 FR-8 — automatic retries of an incomplete checkout, same key.
  static const _defaultRetryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  final CartRepository _cartRepository;
  final CatalogRepository _catalogRepository;
  final WalletRepository _walletRepository;
  final ProfileRepository _profileRepository;
  final CheckoutRepository _checkoutRepository;
  final PendingCheckoutStore _pendingCheckoutStore;
  final CurrentUserIdReader _currentUserId;
  final List<Duration> _checkoutRetryDelays;

  Future<void> _onStarted(CartStarted event, Emitter<CartState> emit) async {
    emit(state.copyWith(loadStatus: CartLoadStatus.loading, clearLoadErrorMessage: true));
    // MA-137 FR-5/FR-6 — balance and profile load alongside the cart; a
    // failure in either only hides its own row.
    await Future.wait([
      _loadCart(emit),
      _loadWallet(emit),
      _loadProfile(emit),
      _loadPendingCheckout(emit),
    ]);
  }

  Future<void> _onRefreshRequested(
    CartRefreshRequested event,
    Emitter<CartState> emit,
  ) async {
    await Future.wait([_loadCart(emit, keepContent: true), _loadWallet(emit)]);
  }

  Future<void> _loadCart(Emitter<CartState> emit, {bool keepContent = false}) async {
    try {
      final view = await _cartRepository.getCart();
      final items = await _resolveProducts(view.items);
      if (emit.isDone) return;
      emit(_withCart(state, view, items).copyWith(loadStatus: CartLoadStatus.loaded));
    } on ApiException catch (e) {
      if (emit.isDone) return;
      if (keepContent && state.loadStatus == CartLoadStatus.loaded) {
        emit(state.copyWith(writeErrorMessage: e.message));
      } else {
        emit(state.copyWith(loadStatus: CartLoadStatus.failed, loadErrorMessage: e.message));
      }
    } catch (_) {
      if (emit.isDone) return;
      if (keepContent && state.loadStatus == CartLoadStatus.loaded) {
        emit(state.copyWith(writeErrorMessage: 'Something went wrong'));
      } else {
        emit(state.copyWith(loadStatus: CartLoadStatus.failed));
      }
    }
  }

  Future<void> _loadWallet(Emitter<CartState> emit) async {
    try {
      final wallet = await _walletRepository.getWallet();
      if (emit.isDone) return;
      emit(
        state.copyWith(
          walletStatus: SideLoadStatus.loaded,
          walletBalancePaise: wallet.balancePaise,
        ),
      );
    } catch (_) {
      if (emit.isDone) return;
      emit(state.copyWith(walletStatus: SideLoadStatus.failed));
    }
  }

  /// MA-137 FR-6 — the saved address for the delivery card. `AuthBloc`
  /// doesn't hold the profile, so this reads it directly, as
  /// `ProductConfigBloc` does. Checkout never depends on it (FR-9).
  Future<void> _loadProfile(Emitter<CartState> emit) async {
    try {
      final profile = await _profileRepository.getMe();
      if (emit.isDone) return;
      emit(
        state.copyWith(
          addressStatus: SideLoadStatus.loaded,
          deliveryAddress: profile.defaultAddress,
          clearDeliveryAddress: profile.defaultAddress == null,
        ),
      );
    } catch (_) {
      if (emit.isDone) return;
      emit(state.copyWith(addressStatus: SideLoadStatus.failed));
    }
  }

  /// MA-137 FR-9 — the user id (token `sub`, no network) and any checkout
  /// a previous session left without a final outcome. Confirm is disabled
  /// until this has run, so it can never race a submit.
  Future<void> _loadPendingCheckout(Emitter<CartState> emit) async {
    final String? userId;
    try {
      userId = await _currentUserId();
    } catch (_) {
      return;
    }
    if (userId == null) return;
    final pending = await _pendingCheckoutStore.read(userId);
    if (emit.isDone || state.checkoutStatus == CheckoutStatus.submitting) return;
    emit(
      state.copyWith(
        userId: userId,
        pendingCheckout: pending,
        // Never reached an outcome: show the "finishing your order" banner
        // and lock the cart; the next tap resumes it.
        checkoutStatus: pending != null ? CheckoutStatus.incomplete : null,
      ),
    );
  }

  CartState _withCart(CartState base, CartView view, List<CartLineItemView> items) =>
      base.copyWith(
        items: items,
        cartVersion: view.cartVersion,
        quote: view.quote,
        clearQuote: view.quote == null,
        payNowQuote: view.payNowQuote,
        clearPayNowQuote: view.payNowQuote == null,
        perDeliveryQuote: view.perDeliveryQuote,
        clearPerDeliveryQuote: view.perDeliveryQuote == null,
      );

  /// MA-123 FR-2 — parallel, not sequential; a single failed lookup
  /// degrades only that row (`product: null`), not the whole screen.
  Future<List<CartLineItemView>> _resolveProducts(List<CartLineItem> lineItems) {
    final known = <String, Product?>{
      for (final view in state.items)
        if (view.product != null) view.lineItem.productId: view.product,
    };
    return Future.wait(
      lineItems.map((li) async {
        if (known.containsKey(li.productId)) {
          return CartLineItemView(lineItem: li, product: known[li.productId]);
        }
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

  void _onQuantityEditStarted(QuantityEditStarted event, Emitter<CartState> emit) {
    if (state.isCartLocked) return;
    emit(state.copyWith(unsentQuantityEdits: {...state.unsentQuantityEdits, event.lineItemId}));
  }

  Future<void> _onQuantityWriteRequested(
    QuantityWriteRequested event,
    Emitter<CartState> emit,
  ) async {
    final unsent = {...state.unsentQuantityEdits}..remove(event.lineItemId);
    if (unsent.length != state.unsentQuantityEdits.length) {
      emit(state.copyWith(unsentQuantityEdits: unsent));
    }
    if (state.isCartLocked) return;
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
    emit(
      state.copyWith(
        items: optimisticItems,
        clearWriteErrorMessage: true,
        writesInFlight: state.writesInFlight + 1,
      ),
    );

    try {
      await _writeQuantity(
        lineItemId: event.lineItemId,
        quantity: event.quantity,
        items: optimisticItems,
        revertItems: originalItems,
        revertVersion: state.cartVersion,
        emit: emit,
        retried: false,
      );
    } finally {
      emit(state.copyWith(writesInFlight: state.writesInFlight - 1));
    }
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
      emit(_withCart(state, fresh, _pairWithKnownProducts(fresh.items)));
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
    if (state.isCartLocked) return;
    emit(state.copyWith(pendingRemovalId: event.lineItemId));
  }

  void _onItemRemoveCancelled(ItemRemoveCancelled event, Emitter<CartState> emit) {
    emit(state.copyWith(clearPendingRemovalId: true));
  }

  Future<void> _onItemRemoveConfirmed(
    ItemRemoveConfirmed event,
    Emitter<CartState> emit,
  ) async {
    if (state.isCartLocked) {
      emit(state.copyWith(clearPendingRemovalId: true));
      return;
    }
    final originalItems = state.items;
    final remainingItems = state.items
        .where((v) => v.lineItem.id != event.lineItemId)
        .toList();
    final remainingErrors = Map<String, String>.of(state.lineErrors)..remove(event.lineItemId);
    emit(
      state.copyWith(
        items: remainingItems,
        clearPendingRemovalId: true,
        clearWriteErrorMessage: true,
        writesInFlight: state.writesInFlight + 1,
        lineErrors: remainingErrors,
      ),
    );

    try {
      await _cartRepository.removeItem(id: event.lineItemId);
      // MA-123 FR-5 — removing the last item skips the extra GET /cart
      // round-trip; the empty state is already fully known locally.
      if (remainingItems.isEmpty) {
        emit(
          state.copyWith(
            clearQuote: true,
            clearPayNowQuote: true,
            clearPerDeliveryQuote: true,
          ),
        );
        return;
      }
      final fresh = await _cartRepository.getCart();
      emit(_withCart(state, fresh, _pairWithKnownProducts(fresh.items)));
    } on ApiException catch (e) {
      emit(state.copyWith(items: originalItems, writeErrorMessage: e.message));
    } catch (_) {
      emit(state.copyWith(items: originalItems, writeErrorMessage: 'Something went wrong'));
    } finally {
      emit(state.copyWith(writesInFlight: state.writesInFlight - 1));
    }
  }

  /// MA-137 FR-7..FR-9 — one Confirm Order. The key and the body are
  /// persisted together before the first request and resent unchanged on
  /// every retry until the checkout reaches a final outcome, so the server
  /// resumes exactly what the customer confirmed (MA-136 FR-2/FR-2a) —
  /// even across an app kill or a logout. Nothing is sent unless that
  /// record is safely stored.
  Future<void> _onCheckoutRequested(
    CheckoutRequested event,
    Emitter<CartState> emit,
  ) async {
    if (!state.canConfirm) return;
    final userId = state.userId!;
    var pending = state.pendingCheckout;
    if (pending == null) {
      pending = PendingCheckout(
        key: newHexId(),
        cartVersion: state.cartVersion,
        expectedPayNowPaise: state.payNowPaise,
      );
      if (!await _pendingCheckoutStore.write(userId, pending)) {
        if (emit.isDone) return;
        emit(
          state.copyWith(
            checkoutFailure: const Unexpected('Something went wrong. Please try again.'),
          ),
        );
        return;
      }
    }
    if (emit.isDone) return;
    emit(
      state.copyWith(
        checkoutStatus: CheckoutStatus.submitting,
        pendingCheckout: pending,
        clearCheckoutFailure: true,
        lineErrors: const {},
      ),
    );

    for (var attempt = 0; ; attempt++) {
      CheckoutFailure failure;
      try {
        final result = await _checkoutRepository.checkout(
          cartVersion: pending.cartVersion,
          expectedPayNowPaise: pending.expectedPayNowPaise,
          idempotencyKey: pending.key,
        );
        await _pendingCheckoutStore.clear(userId);
        emit(
          state.copyWith(
            checkoutStatus: CheckoutStatus.idle,
            clearPendingCheckout: true,
            checkoutResult: result,
          ),
        );
        return;
      } on ApiException catch (e) {
        failure = CheckoutFailure.fromApiException(e);
      } catch (_) {
        failure = const Incomplete();
      }

      if (!failure.clearsKey) {
        if (attempt < _checkoutRetryDelays.length) {
          await Future<void>.delayed(_checkoutRetryDelays[attempt]);
          if (emit.isDone) return;
          continue;
        }
        emit(state.copyWith(checkoutStatus: CheckoutStatus.incomplete, checkoutFailure: failure));
        return;
      }

      await _pendingCheckoutStore.clear(userId);
      emit(
        state.copyWith(
          checkoutStatus: CheckoutStatus.idle,
          clearPendingCheckout: true,
          checkoutFailure: failure,
          lineErrors: failure is LineInvalid ? failure.reasonsByLineId : const {},
        ),
      );
      if (failure is CartChanged || failure is PriceChanged || failure is LineInvalid) {
        add(const CartRefreshRequested());
      }
      return;
    }
  }

  void _onFeedbackConsumed(CheckoutFeedbackConsumed event, Emitter<CartState> emit) {
    emit(state.copyWith(clearCheckoutFailure: true));
  }
}
