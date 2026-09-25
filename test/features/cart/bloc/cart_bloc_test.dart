import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/cart/bloc/cart_bloc.dart';
import 'package:milkful_app/features/cart/bloc/cart_event.dart';
import 'package:milkful_app/features/cart/bloc/cart_state.dart';
import 'package:milkful_app/features/cart/models/cart_line_item.dart';
import 'package:milkful_app/features/cart/models/cart_view.dart';
import 'package:milkful_app/features/cart/models/frequency.dart';
import 'package:milkful_app/features/cart/models/quote.dart';
import 'package:milkful_app/features/catalog/models/product.dart';
import 'package:milkful_app/features/auth/models/delivery_address.dart';
import 'package:milkful_app/features/auth/models/user_profile.dart';
import 'package:milkful_app/features/checkout/data/pending_checkout_store.dart';
import 'package:milkful_app/features/checkout/models/checkout_failure.dart';
import 'package:milkful_app/features/wallet/models/wallet_status.dart';
import 'package:milkful_app/features/wallet/models/wallet_view.dart';

import '../../../fakes/fake_cart_repository.dart';
import '../../../fakes/fake_catalog_repository.dart';
import '../../../fakes/fake_checkout_repository.dart';
import '../../../fakes/fake_pending_checkout_store.dart';
import '../../../fakes/fake_profile_repository.dart';
import '../../../fakes/fake_wallet_repository.dart';

const _cowMilk = Product(
  id: 'cow-milk',
  categoryId: 'milk',
  name: 'Cow Milk',
  description: 'Farm-fresh cow milk',
  unit: '1L Bottle',
  price: 68,
  stockState: StockState.inStock,
);

const _buffaloMilk = Product(
  id: 'buffalo-milk',
  categoryId: 'milk',
  name: 'Buffalo Milk',
  description: 'Rich buffalo milk',
  unit: '1L Bottle',
  price: 90,
  stockState: StockState.inStock,
  subscriptionEligible: true,
);

const _lineItem1 = CartLineItem(
  id: 'li-1',
  productId: 'cow-milk',
  quantity: 1,
  frequency: Frequency.oneTime,
  addedAt: '2026-08-31T10:00:00.000Z',
);

const _lineItem2 = CartLineItem(
  id: 'li-2',
  productId: 'buffalo-milk',
  quantity: 1,
  frequency: Frequency.daily,
  startDate: '2026-09-01',
  addedAt: '2026-08-31T10:00:00.000Z',
);

const _quote = Quote(
  basePrice: 158,
  taxAmount: 7.9,
  taxRate: 5,
  deliveryFee: 20,
  netPayable: 185.9,
);

void main() {
  group('CartBloc', () {
    late FakeCartRepository cartRepository;
    late FakeCatalogRepository catalogRepository;
    late FakeWalletRepository walletRepository;
    late FakeProfileRepository profileRepository;
    late FakeCheckoutRepository checkoutRepository;
    late FakePendingCheckoutStore pendingCheckoutStore;
    String? currentUserId;

    setUp(() {
      currentUserId = 'user-1';
      cartRepository = FakeCartRepository(
        getCartResult: const CartView(
          items: [_lineItem1, _lineItem2],
          cartVersion: 1,
          quote: _quote,
        ),
      );
      catalogRepository = FakeCatalogRepository(
        productsById: {'cow-milk': _cowMilk, 'buffalo-milk': _buffaloMilk},
      );
      walletRepository = FakeWalletRepository();
      profileRepository = FakeProfileRepository();
      checkoutRepository = FakeCheckoutRepository();
      pendingCheckoutStore = FakePendingCheckoutStore();
    });

    CartBloc build() => CartBloc(
      cartRepository: cartRepository,
      catalogRepository: catalogRepository,
      walletRepository: walletRepository,
      profileRepository: profileRepository,
      checkoutRepository: checkoutRepository,
      pendingCheckoutStore: pendingCheckoutStore,
      currentUserId: () async => currentUserId,
      checkoutRetryDelays: const [Duration.zero, Duration.zero, Duration.zero],
    );

    blocTest<CartBloc, CartState>(
      'CartStarted resolves items and products, and loads the quote',
      build: build,
      act: (bloc) => bloc.add(const CartStarted()),
      verify: (bloc) {
        expect(bloc.state.loadStatus, CartLoadStatus.loaded);
        expect(bloc.state.items, hasLength(2));
        expect(bloc.state.items[0].product, _cowMilk);
        expect(bloc.state.items[1].product, _buffaloMilk);
        expect(bloc.state.cartVersion, 1);
        expect(bloc.state.quote, _quote);
      },
    );

    blocTest<CartBloc, CartState>(
      'a per-item getProduct failure degrades only that row, not the whole load',
      build: () {
        catalogRepository.productsById = {'cow-milk': _cowMilk};
        return build();
      },
      act: (bloc) => bloc.add(const CartStarted()),
      verify: (bloc) {
        expect(bloc.state.loadStatus, CartLoadStatus.loaded);
        final buffaloRow = bloc.state.items.firstWhere(
          (v) => v.lineItem.id == 'li-2',
        );
        expect(buffaloRow.product, isNull);
      },
    );

    blocTest<CartBloc, CartState>(
      'a getCart failure resolves to a failed load state',
      build: () {
        cartRepository.getCartException = const ApiException(
          errorCode: 'NETWORK_ERROR',
          message: 'offline',
        );
        return build();
      },
      act: (bloc) => bloc.add(const CartStarted()),
      verify: (bloc) {
        expect(bloc.state.loadStatus, CartLoadStatus.failed);
        expect(bloc.state.loadErrorMessage, 'offline');
      },
    );

    blocTest<CartBloc, CartState>(
      'an empty cart (no items) loads with an empty list and no quote',
      build: () {
        cartRepository.getCartResult = const CartView(
          items: [],
          cartVersion: 0,
        );
        return build();
      },
      act: (bloc) => bloc.add(const CartStarted()),
      verify: (bloc) {
        expect(bloc.state.isEmpty, isTrue);
        expect(bloc.state.quote, isNull);
      },
    );

    blocTest<CartBloc, CartState>(
      'QuantityWriteRequested calls updateItem with the full item list and current cartVersion',
      build: build,
      act: (bloc) async {
        bloc.add(const CartStarted());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const QuantityWriteRequested(lineItemId: 'li-1', quantity: 3));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(cartRepository.updateItemRequests, hasLength(1));
        final request = cartRepository.updateItemRequests.single;
        expect(request.ifVersion, 1);
        expect(request.items, hasLength(2));
        expect(request.items.firstWhere((i) => i.id == 'li-1').quantity, 3);
      },
    );

    blocTest<CartBloc, CartState>(
      'a 409 on updateItem silently refetches and reapplies the target quantity, with no error',
      build: () {
        cartRepository = FakeCartRepository(
          getCartResult: const CartView(
            items: [_lineItem1, _lineItem2],
            cartVersion: 1,
            quote: _quote,
          ),
          updateItemException: const ApiException(
            errorCode: 'CART_VERSION_CONFLICT',
            message: 'stale version',
            statusCode: 409,
          ),
        )..updateItemFailuresRemaining = 1;
        return build();
      },
      act: (bloc) async {
        bloc.add(const CartStarted());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const QuantityWriteRequested(lineItemId: 'li-1', quantity: 5));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.writeErrorMessage, isNull);
        expect(cartRepository.updateItemRequests, hasLength(2));
        expect(
          cartRepository.updateItemRequests.last.items
              .firstWhere((i) => i.id == 'li-1')
              .quantity,
          5,
        );
      },
    );

    blocTest<CartBloc, CartState>(
      'removing the last item transitions straight to the empty state without an extra getCart call',
      build: () {
        cartRepository = FakeCartRepository(
          getCartResult: const CartView(
            items: [_lineItem1],
            cartVersion: 1,
            quote: _quote,
          ),
        );
        return build();
      },
      act: (bloc) async {
        bloc.add(const CartStarted());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const ItemRemoveConfirmed(lineItemId: 'li-1'));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.isEmpty, isTrue);
        expect(bloc.state.quote, isNull);
        // Exactly one getCart call: the initial CartStarted load. Removing
        // the last item must not trigger a second one (MA-123 FR-5).
        expect(cartRepository.getCartCallCount, 1);
      },
    );

    blocTest<CartBloc, CartState>(
      'ItemRemoveRequested sets pendingRemovalId without removing anything',
      build: build,
      act: (bloc) async {
        bloc.add(const CartStarted());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const ItemRemoveRequested(lineItemId: 'li-1'));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.pendingRemovalId, 'li-1');
        expect(bloc.state.items, hasLength(2));
      },
    );

    blocTest<CartBloc, CartState>(
      'back-to-back writes on different rows both reach the server (neither is cancelled)',
      build: build,
      act: (bloc) async {
        bloc.add(const CartStarted());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const QuantityWriteRequested(lineItemId: 'li-1', quantity: 2));
        bloc.add(const QuantityWriteRequested(lineItemId: 'li-2', quantity: 4));
      },
      wait: const Duration(milliseconds: 40),
      verify: (bloc) {
        expect(cartRepository.updateItemRequests, hasLength(2));
        expect(bloc.state.writeErrorMessage, isNull);
      },
    );

    blocTest<CartBloc, CartState>(
      'a 409 that persists through the retry reverts items and cartVersion together',
      build: () {
        cartRepository = FakeCartRepository(
          getCartResult: const CartView(
            items: [_lineItem1, _lineItem2],
            cartVersion: 1,
            quote: _quote,
          ),
          updateItemException: const ApiException(
            errorCode: 'CART_VERSION_CONFLICT',
            message: 'stale version',
            statusCode: 409,
          ),
        );
        return build();
      },
      act: (bloc) async {
        bloc.add(const CartStarted());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const QuantityWriteRequested(lineItemId: 'li-1', quantity: 9));
      },
      wait: const Duration(milliseconds: 40),
      verify: (bloc) {
        expect(bloc.state.writeErrorMessage, 'stale version');
        // Reverted to the refetched server snapshot (quantity 1), and
        // cartVersion still describes that same snapshot rather than being
        // left advanced past the items it no longer matches.
        expect(
          bloc.state.items
              .firstWhere((v) => v.lineItem.id == 'li-1')
              .lineItem
              .quantity,
          1,
        );
        expect(bloc.state.cartVersion, 1);
        expect(
          cartRepository.updateItemRequests,
          hasLength(2),
        ); // initial + one retry
      },
    );

    blocTest<CartBloc, CartState>(
      'a non-conflict write failure reverts the optimistic change and surfaces the message',
      build: () {
        cartRepository.updateItemException = const ApiException(
          errorCode: 'STOCK_EXCEEDED',
          message: 'Only 2 left in stock',
        );
        return build();
      },
      act: (bloc) async {
        bloc.add(const CartStarted());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(
          const QuantityWriteRequested(lineItemId: 'li-1', quantity: 10),
        );
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.writeErrorMessage, 'Only 2 left in stock');
        expect(
          bloc.state.items
              .firstWhere((v) => v.lineItem.id == 'li-1')
              .lineItem
              .quantity,
          1,
        );
      },
    );
  });

  group('CartBloc — Review Cart & Confirm Order (MA-137)', () {
    late FakeCartRepository cartRepository;
    late FakeCatalogRepository catalogRepository;
    late FakeWalletRepository walletRepository;
    late FakeProfileRepository profileRepository;
    late FakeCheckoutRepository checkoutRepository;
    late FakePendingCheckoutStore pendingCheckoutStore;
    String? currentUserId;

    const payNow = Quote(
      basePrice: 84,
      taxAmount: 4.2,
      taxRate: 5,
      deliveryFee: 20,
      netPayable: 108.2,
    );
    const perDelivery = Quote(
      basePrice: 90,
      taxAmount: 4.5,
      taxRate: 5,
      deliveryFee: 0,
      netPayable: 94.5,
      monthlyEstimate: 2835,
    );
    const address = DeliveryAddress(
      id: 'addr-1',
      lines: ['Flat 402, Sai Heights', 'Baner Road'],
      landmark: 'Near Baner Gaon bus stop',
      city: 'Pune',
      state: 'Maharashtra',
      pincode: '411045',
      lat: 18.559,
      lng: 73.786,
    );

    WalletView wallet(int balancePaise) => WalletView(
      walletId: 'w-1',
      status: WalletStatus.active,
      balancePaise: balancePaise,
      currency: 'INR',
      rechargeMinPaise: 10000,
      rechargeMaxPaise: 1000000,
    );

    setUp(() {
      cartRepository = FakeCartRepository(
        getCartResult: const CartView(
          items: [_lineItem1, _lineItem2],
          cartVersion: 7,
          quote: _quote,
          payNowQuote: payNow,
          perDeliveryQuote: perDelivery,
        ),
      );
      catalogRepository = FakeCatalogRepository(
        productsById: {'cow-milk': _cowMilk, 'buffalo-milk': _buffaloMilk},
      );
      walletRepository = FakeWalletRepository(getWalletResult: wallet(100000));
      profileRepository = FakeProfileRepository(
        profile: const UserProfile(
          userId: 'user-1',
          name: 'Priya Sharma',
          mobile: '+919876543210',
          accountType: 'B2C',
          defaultAddressId: 'addr-1',
          defaultAddress: address,
        ),
      );
      checkoutRepository = FakeCheckoutRepository();
      pendingCheckoutStore = FakePendingCheckoutStore();
      currentUserId = 'user-1';
    });

    CartBloc build() => CartBloc(
      cartRepository: cartRepository,
      catalogRepository: catalogRepository,
      walletRepository: walletRepository,
      profileRepository: profileRepository,
      checkoutRepository: checkoutRepository,
      pendingCheckoutStore: pendingCheckoutStore,
      currentUserId: () async => currentUserId,
      checkoutRetryDelays: const [Duration.zero, Duration.zero, Duration.zero],
    );

    Future<void> started(CartBloc bloc) async {
      bloc.add(const CartStarted());
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    Future<void> confirmed(CartBloc bloc) async {
      await started(bloc);
      bloc.add(const CheckoutRequested());
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    const incomplete = ApiException(
      errorCode: 'CHECKOUT_INCOMPLETE',
      message: 'finishing',
      statusCode: 503,
    );

    blocTest<CartBloc, CartState>(
      'loads split quotes, wallet balance and the saved address together',
      build: build,
      act: started,
      verify: (bloc) {
        final s = bloc.state;
        expect(s.payNowQuote, payNow);
        expect(s.perDeliveryQuote, perDelivery);
        expect(s.walletStatus, SideLoadStatus.loaded);
        expect(s.walletBalancePaise, 100000);
        expect(s.deliveryAddress, address);
        expect(s.userId, 'user-1');
        expect(s.payNowPaise, 10820);
        // Pay now + the ₹500 subscription minimum.
        expect(s.requiredPaise, 10820 + 50000);
        expect(s.shortfallPaise, 0);
        expect(s.canConfirm, isTrue);
      },
    );

    blocTest<CartBloc, CartState>(
      'a wallet read failure hides the balance but never blocks Confirm',
      build: () {
        walletRepository.getWalletException = const ApiException(
          errorCode: 'NETWORK_ERROR',
          message: 'offline',
        );
        return build();
      },
      act: started,
      verify: (bloc) {
        expect(bloc.state.walletStatus, SideLoadStatus.failed);
        expect(bloc.state.shortfallPaise, isNull);
        expect(bloc.state.canConfirm, isTrue);
      },
    );

    blocTest<CartBloc, CartState>(
      'shortfall is required minus balance',
      build: () {
        walletRepository.getWalletResult = wallet(5000);
        return build();
      },
      act: started,
      verify: (bloc) => expect(bloc.state.shortfallPaise, 10820 + 50000 - 5000),
    );

    blocTest<CartBloc, CartState>(
      'no default address loads as a missing address, not a failure',
      build: () {
        profileRepository.profile = const UserProfile(
          userId: 'user-1',
          name: 'Priya Sharma',
          mobile: '+919876543210',
          accountType: 'B2C',
          defaultAddressId: null,
        );
        return build();
      },
      act: started,
      verify: (bloc) {
        expect(bloc.state.addressStatus, SideLoadStatus.loaded);
        expect(bloc.state.deliveryAddress, isNull);
      },
    );

    blocTest<CartBloc, CartState>(
      'an all-one-time cart from a Cart Service without the split falls back to quote',
      build: () {
        cartRepository.getCartResult = const CartView(
          items: [_lineItem1],
          cartVersion: 1,
          quote: _quote,
        );
        return build();
      },
      act: started,
      verify: (bloc) {
        expect(bloc.state.effectivePayNowQuote, _quote);
        expect(bloc.state.payNowPaise, 18590);
      },
    );

    blocTest<CartBloc, CartState>(
      'Confirm sends cartVersion + expected pay-now with a persisted key, then clears it',
      build: build,
      act: confirmed,
      verify: (bloc) {
        final call = checkoutRepository.calls.single;
        expect(call.cartVersion, 7);
        expect(call.expectedPayNowPaise, 10820);
        expect(pendingCheckoutStore.writes, [
          PendingCheckout(key: call.idempotencyKey, cartVersion: 7, expectedPayNowPaise: 10820),
        ]);
        expect(pendingCheckoutStore.pending, isEmpty);
        expect(bloc.state.checkoutResult, FakeCheckoutRepository.defaultResult);
        expect(bloc.state.checkoutStatus, CheckoutStatus.idle);
        expect(bloc.state.pendingCheckout, isNull);
        expect(bloc.state.isCartLocked, isFalse);
      },
    );

    blocTest<CartBloc, CartState>(
      'an incomplete checkout is retried with the same key, then succeeds',
      build: () {
        checkoutRepository.outcomes.addAll([
          incomplete,
          const ApiException(errorCode: 'NETWORK_ERROR', message: 'offline'),
        ]);
        return build();
      },
      act: confirmed,
      verify: (bloc) {
        final keys = checkoutRepository.calls
            .map((c) => c.idempotencyKey)
            .toSet();
        expect(checkoutRepository.calls, hasLength(3));
        expect(keys, hasLength(1));
        expect(bloc.state.checkoutResult, isNotNull);
      },
    );

    blocTest<CartBloc, CartState>(
      'still incomplete after 3 retries: keeps the key and shows the banner state',
      build: () {
        checkoutRepository.outcomes.addAll(List.filled(4, incomplete));
        return build();
      },
      act: confirmed,
      verify: (bloc) {
        expect(checkoutRepository.calls, hasLength(4));
        expect(bloc.state.checkoutStatus, CheckoutStatus.incomplete);
        expect(bloc.state.pendingCheckout, isNotNull);
        expect(pendingCheckoutStore.pending['user-1'], bloc.state.pendingCheckout);
        expect(bloc.state.isCartLocked, isTrue);
      },
    );

    const fromBefore = PendingCheckout(
      key: 'key-from-before',
      cartVersion: 5,
      expectedPayNowPaise: 9000,
    );

    blocTest<CartBloc, CartState>(
      'a checkout left by a previous session locks the cart and resends its saved key and body',
      build: () {
        pendingCheckoutStore.pending['user-1'] = fromBefore;
        return build();
      },
      act: (bloc) async {
        await started(bloc);
        expect(bloc.state.checkoutStatus, CheckoutStatus.incomplete);
        expect(bloc.state.isCartLocked, isTrue);
        bloc.add(const CheckoutRequested());
        await Future<void>.delayed(const Duration(milliseconds: 10));
      },
      verify: (bloc) {
        final call = checkoutRepository.calls.single;
        expect(call.idempotencyKey, 'key-from-before');
        // The saved body, not the cart now on screen (version 7, ₹108.20).
        expect(call.cartVersion, 5);
        expect(call.expectedPayNowPaise, 9000);
        expect(pendingCheckoutStore.writes, isEmpty);
        expect(bloc.state.checkoutResult, isNotNull);
        expect(bloc.state.isCartLocked, isFalse);
      },
    );

    blocTest<CartBloc, CartState>(
      'the pending checkout is found even when the profile load fails',
      build: () {
        pendingCheckoutStore.pending['user-1'] = fromBefore;
        profileRepository.getMeException = const ApiException(
          errorCode: 'NETWORK_ERROR',
          message: 'offline',
        );
        return build();
      },
      act: started,
      verify: (bloc) {
        expect(bloc.state.addressStatus, SideLoadStatus.failed);
        expect(bloc.state.userId, 'user-1');
        expect(bloc.state.pendingCheckout, fromBefore);
        expect(bloc.state.checkoutStatus, CheckoutStatus.incomplete);
      },
    );

    blocTest<CartBloc, CartState>(
      'Confirm is disabled and sends nothing without a signed-in user id',
      build: () {
        currentUserId = null;
        return build();
      },
      act: confirmed,
      verify: (bloc) {
        expect(bloc.state.canConfirm, isFalse);
        expect(checkoutRepository.calls, isEmpty);
        expect(pendingCheckoutStore.writes, isEmpty);
      },
    );

    blocTest<CartBloc, CartState>(
      'nothing is sent when the pending checkout cannot be saved',
      build: () {
        pendingCheckoutStore.failWrites = true;
        return build();
      },
      act: confirmed,
      verify: (bloc) {
        expect(checkoutRepository.calls, isEmpty);
        expect(bloc.state.checkoutStatus, CheckoutStatus.idle);
        expect(bloc.state.pendingCheckout, isNull);
        expect(bloc.state.checkoutFailure, isA<Unexpected>());
      },
    );

    blocTest<CartBloc, CartState>(
      'quantity edits and removals are ignored while a checkout is pending',
      build: () {
        pendingCheckoutStore.pending['user-1'] = fromBefore;
        return build();
      },
      act: (bloc) async {
        await started(bloc);
        bloc
          ..add(const QuantityEditStarted(lineItemId: 'li-1'))
          ..add(const QuantityWriteRequested(lineItemId: 'li-1', quantity: 3))
          ..add(const ItemRemoveRequested(lineItemId: 'li-2'))
          ..add(const ItemRemoveConfirmed(lineItemId: 'li-2'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      verify: (bloc) {
        expect(cartRepository.updateItemRequests, isEmpty);
        expect(cartRepository.removeItemRequests, isEmpty);
        expect(bloc.state.items, hasLength(2));
        expect(bloc.state.items.first.lineItem.quantity, 1);
        expect(bloc.state.unsentQuantityEdits, isEmpty);
        expect(bloc.state.pendingRemovalId, isNull);
      },
    );

    blocTest<CartBloc, CartState>(
      'Confirm waits for a quantity edit that has not been sent yet',
      build: build,
      act: (bloc) async {
        await started(bloc);
        bloc.add(const QuantityEditStarted(lineItemId: 'li-1'));
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state.canConfirm, isFalse);
        bloc.add(const CheckoutRequested());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(checkoutRepository.calls, isEmpty);
        // The screen's debounce fires: the edit goes out, then Confirm works.
        bloc.add(const QuantityWriteRequested(lineItemId: 'li-1', quantity: 3));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.unsentQuantityEdits, isEmpty);
        expect(bloc.state.canConfirm, isTrue);
      },
      verify: (bloc) => expect(checkoutRepository.calls, isEmpty),
    );

    blocTest<CartBloc, CartState>(
      'insufficient balance clears the key and surfaces the shortfall',
      build: () {
        checkoutRepository.outcomes.add(
          const ApiException(
            errorCode: 'INSUFFICIENT_BALANCE',
            message: 'Not enough wallet balance',
            statusCode: 402,
            details: {'shortfallPaise': 2420},
          ),
        );
        return build();
      },
      act: confirmed,
      verify: (bloc) {
        expect(
          bloc.state.checkoutFailure,
          const InsufficientBalance(shortfallPaise: 2420),
        );
        expect(bloc.state.pendingCheckout, isNull);
        expect(pendingCheckoutStore.pending, isEmpty);
        expect(checkoutRepository.calls, hasLength(1));
      },
    );

    blocTest<CartBloc, CartState>(
      'LINE_INVALID marks the listed lines and refreshes the cart',
      build: () {
        checkoutRepository.outcomes.add(
          const ApiException(
            errorCode: 'LINE_INVALID',
            message: 'fix lines',
            statusCode: 422,
            details: {
              'lines': [
                {'lineId': 'li-2', 'reason': 'SLOT_MISSING'},
              ],
            },
          ),
        );
        return build();
      },
      act: confirmed,
      verify: (bloc) {
        expect(bloc.state.lineErrors, {'li-2': 'SLOT_MISSING'});
        expect(cartRepository.getCartCallCount, 2);
      },
    );

    blocTest<CartBloc, CartState>(
      'CART_CHANGED refreshes the cart and clears the key',
      build: () {
        checkoutRepository.outcomes.add(
          const ApiException(
            errorCode: 'CART_CHANGED',
            message: 'moved',
            statusCode: 409,
          ),
        );
        return build();
      },
      act: confirmed,
      verify: (bloc) {
        expect(bloc.state.checkoutFailure, const CartChanged());
        expect(bloc.state.pendingCheckout, isNull);
        expect(cartRepository.getCartCallCount, 2);
      },
    );

    blocTest<CartBloc, CartState>(
      'Confirm is ignored while a quantity write is still settling',
      build: build,
      act: (bloc) async {
        await started(bloc);
        bloc.add(const QuantityWriteRequested(lineItemId: 'li-1', quantity: 3));
        bloc.add(const CheckoutRequested());
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      verify: (bloc) {
        expect(checkoutRepository.calls, isEmpty);
        expect(bloc.state.writesInFlight, 0);
      },
    );

    blocTest<CartBloc, CartState>(
      'CheckoutFeedbackConsumed clears a shown failure',
      build: () {
        checkoutRepository.outcomes.add(
          const ApiException(
            errorCode: 'PRICE_CHANGED',
            message: 'moved',
            statusCode: 409,
          ),
        );
        return build();
      },
      act: (bloc) async {
        await confirmed(bloc);
        bloc.add(const CheckoutFeedbackConsumed());
      },
      verify: (bloc) => expect(bloc.state.checkoutFailure, isNull),
    );
  });
}
