import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/core/storage/secure_token_storage.dart';
import 'package:milkful_app/features/auth/data/profile_repository.dart';
import 'package:milkful_app/features/auth/models/delivery_address.dart';
import 'package:milkful_app/features/auth/models/user_profile.dart';
import 'package:milkful_app/features/cart/data/cart_repository.dart';
import 'package:milkful_app/features/cart/models/cart_line_item.dart';
import 'package:milkful_app/features/cart/models/cart_view.dart';
import 'package:milkful_app/features/cart/models/frequency.dart';
import 'package:milkful_app/features/cart/models/quote.dart';
import 'package:milkful_app/features/cart/presentation/cart_screen.dart';
import 'package:milkful_app/features/catalog/data/catalog_repository.dart';
import 'package:milkful_app/features/catalog/models/product.dart';
import 'package:milkful_app/features/checkout/data/checkout_repository.dart';
import 'package:milkful_app/features/checkout/data/pending_checkout_store.dart';
import 'package:milkful_app/features/checkout/presentation/order_success_screen.dart';
import 'package:milkful_app/features/wallet/data/wallet_repository.dart';
import 'package:milkful_app/features/wallet/models/wallet_status.dart';
import 'package:milkful_app/features/wallet/models/wallet_view.dart';

import '../../../fakes/fake_cart_repository.dart';
import '../../../fakes/fake_catalog_repository.dart';
import '../../../fakes/fake_checkout_repository.dart';
import '../../../fakes/fake_pending_checkout_store.dart';
import '../../../fakes/fake_profile_repository.dart';
import '../../../fakes/fake_secure_token_storage.dart';
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
  price: 84,
  stockState: StockState.inStock,
  subscriptionEligible: true,
);

const _lineItem = CartLineItem(
  id: 'li-1',
  productId: 'cow-milk',
  quantity: 1,
  frequency: Frequency.oneTime,
  addedAt: '2026-08-31T10:00:00.000Z',
);

const _dailyLine = CartLineItem(
  id: 'li-2',
  productId: 'buffalo-milk',
  quantity: 1,
  frequency: Frequency.daily,
  startDate: '2026-09-27',
  slotId: 'slot-am',
  addedAt: '2026-08-31T10:00:00.000Z',
);

const _quote = Quote(
  basePrice: 68,
  taxAmount: 3.4,
  taxRate: 5,
  deliveryFee: 20,
  netPayable: 91.4,
  discountAmount: 5,
);

const _payNow = Quote(
  basePrice: 84,
  taxAmount: 4.2,
  taxRate: 5,
  deliveryFee: 20,
  netPayable: 108.2,
);

const _perDelivery = Quote(
  basePrice: 84,
  taxAmount: 4.2,
  taxRate: 5,
  deliveryFee: 0,
  netPayable: 88.2,
  monthlyEstimate: 2646,
);

const _address = DeliveryAddress(
  id: 'addr-1',
  lines: ['Flat 402, Sai Heights', 'Baner Road'],
  landmark: 'Near Baner Gaon bus stop',
  city: 'Pune',
  state: 'Maharashtra',
  pincode: '411045',
  lat: 18.559,
  lng: 73.786,
);

WalletView _wallet(int balancePaise) => WalletView(
  walletId: 'w-1',
  status: WalletStatus.active,
  balancePaise: balancePaise,
  currency: 'INR',
  rechargeMinPaise: 10000,
  rechargeMaxPaise: 1000000,
);

/// A structurally valid JWT whose payload carries `sub` — the cart reads
/// only that claim, locally (MA-137 FR-9).
String _jwtWithSub(String sub) {
  String part(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'sub': sub})}.sig';
}

void main() {
  late FakeCartRepository cartRepository;
  late FakeCatalogRepository catalogRepository;
  late FakeWalletRepository walletRepository;
  late FakeProfileRepository profileRepository;
  late FakeCheckoutRepository checkoutRepository;
  late FakePendingCheckoutStore pendingCheckoutStore;
  late FakeSecureTokenStorage tokenStorage;
  late GoRouter router;

  Future<void> pumpCart(WidgetTester tester) async {
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const Placeholder()),
        GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
        GoRoute(
          path: '/catalog',
          builder: (context, state) => const Scaffold(body: Text('catalog-page')),
        ),
        GoRoute(
          path: '/wallet',
          builder: (context, state) => const Scaffold(body: Text('wallet-page')),
        ),
        GoRoute(
          path: '/order-success',
          builder: (context, state) =>
              OrderSuccessScreen(args: state.extra! as OrderSuccessArgs),
        ),
        GoRoute(path: '/home', builder: (context, state) => const Placeholder()),
      ],
    );
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<CartRepository>.value(value: cartRepository),
          RepositoryProvider<CatalogRepository>.value(value: catalogRepository),
          RepositoryProvider<WalletRepository>.value(value: walletRepository),
          RepositoryProvider<ProfileRepository>.value(value: profileRepository),
          RepositoryProvider<CheckoutRepository>.value(value: checkoutRepository),
          RepositoryProvider<PendingCheckoutStore>.value(value: pendingCheckoutStore),
          RepositoryProvider<SecureTokenStorage>.value(value: tokenStorage),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/cart');
    await tester.pumpAndSettle();
  }

  setUp(() {
    catalogRepository = FakeCatalogRepository(
      productsById: {'cow-milk': _cowMilk, 'buffalo-milk': _buffaloMilk},
    );
    walletRepository = FakeWalletRepository(getWalletResult: _wallet(100000));
    profileRepository = FakeProfileRepository(
      profile: const UserProfile(
        userId: 'user-1',
        name: 'Priya Sharma',
        mobile: '+919876543210',
        accountType: 'B2C',
        defaultAddressId: 'addr-1',
        defaultAddress: _address,
      ),
    );
    checkoutRepository = FakeCheckoutRepository();
    pendingCheckoutStore = FakePendingCheckoutStore();
    tokenStorage = FakeSecureTokenStorage()..accessToken = _jwtWithSub('user-1');
  });

  // --- MA-123 behaviour, unchanged -------------------------------------------

  testWidgets('Empty cart shows the empty state', (tester) async {
    cartRepository = FakeCartRepository(getCartResult: const CartView(items: [], cartVersion: 0));

    await pumpCart(tester);

    expect(find.byKey(const Key('cart-empty-state')), findsOneWidget);
    expect(find.byKey(const Key('cart-checkout-cta')), findsNothing);
  });

  testWidgets('Non-empty cart shows the aggregate quote breakdown', (tester) async {
    cartRepository = FakeCartRepository(
      getCartResult: const CartView(items: [_lineItem], cartVersion: 1, quote: _quote),
    );

    await pumpCart(tester);

    expect(find.text('₹68.00'), findsOneWidget); // Subtotal
    expect(find.text('₹91.40'), findsOneWidget); // Total
    expect(find.text('-₹5.00'), findsOneWidget); // Discount
    expect(find.byKey(const Key('cart-checkout-cta')), findsOneWidget);
  });

  testWidgets('Increasing quantity calls updateItem with the full item list', (tester) async {
    cartRepository = FakeCartRepository(
      getCartResult: const CartView(items: [_lineItem], cartVersion: 1, quote: _quote),
    );

    await pumpCart(tester);

    await tester.tap(find.byKey(const Key('cart-item-quantity-increase-li-1')));
    await tester.pump(const Duration(milliseconds: 600));

    expect(cartRepository.updateItemRequests, hasLength(1));
    expect(cartRepository.updateItemRequests.single.items.single.quantity, 2);
    expect(cartRepository.updateItemRequests.single.ifVersion, 1);
  });

  testWidgets('Removing the last item returns to the empty state', (tester) async {
    cartRepository = FakeCartRepository(
      getCartResult: const CartView(items: [_lineItem], cartVersion: 1, quote: _quote),
    );

    await pumpCart(tester);

    await tester.tap(find.byKey(const Key('cart-item-remove-li-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cart-empty-state')), findsOneWidget);
  });

  testWidgets('a failed quantity write snaps the stepper back to the real quantity', (tester) async {
    cartRepository = FakeCartRepository(
      getCartResult: const CartView(items: [_lineItem], cartVersion: 1, quote: _quote),
      updateItemException: const ApiException(
        errorCode: 'STOCK_EXCEEDED',
        message: 'Only 1 left in stock',
      ),
    );

    await pumpCart(tester);

    await tester.tap(find.byKey(const Key('cart-item-quantity-increase-li-1')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('cart-item-quantity-value-li-1'))).data,
      '2',
    );

    // Debounce fires -> write -> fails -> bloc reverts -> the local
    // instant-feedback override must not keep the row stuck on 2.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const Key('cart-item-quantity-value-li-1'))).data,
      '1',
    );
  });

  testWidgets('Cancelling the remove dialog keeps the item', (tester) async {
    cartRepository = FakeCartRepository(
      getCartResult: const CartView(items: [_lineItem], cartVersion: 1, quote: _quote),
    );

    await pumpCart(tester);

    await tester.tap(find.byKey(const Key('cart-item-remove-li-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cart-empty-state')), findsNothing);
    expect(find.byKey(const Key('cart-item-remove-li-1')), findsOneWidget);
    expect(cartRepository.removeItemRequests, isEmpty);
  });

  // --- MA-137 Review Cart & Confirm Order ---------------------------------------

  CartView mixedCart({int version = 3}) => CartView(
    items: const [_lineItem, _dailyLine],
    cartVersion: version,
    quote: _quote,
    payNowQuote: _payNow,
    perDeliveryQuote: _perDelivery,
  );

  testWidgets('Title reads Review Cart and the CTA reads Confirm Order, enabled', (tester) async {
    cartRepository = FakeCartRepository(getCartResult: mixedCart());

    await pumpCart(tester);

    expect(find.text('Review Cart'), findsOneWidget);
    expect(find.text('Confirm Order'), findsOneWidget);
    expect(find.textContaining('coming soon'), findsNothing);
    final cta = tester.widget<FilledButton>(find.byKey(const Key('cart-checkout-cta')));
    expect(cta.onPressed, isNotNull);
  });

  testWidgets('Mixed cart shows Pay now and Subscriptions separately', (tester) async {
    cartRepository = FakeCartRepository(getCartResult: mixedCart());

    await pumpCart(tester);

    expect(find.text('PAY NOW'), findsOneWidget);
    expect(find.text('SUBSCRIPTIONS'), findsOneWidget);
    expect(find.text('₹108.20'), findsOneWidget); // pay-now total
    expect(find.text('₹88.20 per delivery · charged from wallet'), findsOneWidget);
    expect(find.text('≈ ₹2646/month'), findsOneWidget);
    expect(find.text('Daily · starts 27 Sep'), findsOneWidget);
  });

  testWidgets('Full delivery address from the saved profile is shown', (tester) async {
    cartRepository = FakeCartRepository(getCartResult: mixedCart());

    await pumpCart(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('cart-delivery-card')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    final card = find.byKey(const Key('cart-delivery-card'));
    expect(
      find.descendant(of: card, matching: find.text('Flat 402, Sai Heights, Baner Road')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Near Baner Gaon bus stop')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Pune, Maharashtra 411045')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('cart-delivery-date')), findsOneWidget);
  });

  testWidgets('No saved address shows the missing-address line; Confirm stays enabled', (
    tester,
  ) async {
    cartRepository = FakeCartRepository(getCartResult: mixedCart());
    profileRepository.profile = const UserProfile(
      userId: 'user-1',
      name: 'Priya Sharma',
      mobile: '+919876543210',
      accountType: 'B2C',
      defaultAddressId: null,
    );

    await pumpCart(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('cart-delivery-missing')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byKey(const Key('cart-delivery-missing')), findsOneWidget);
    final cta = tester.widget<FilledButton>(find.byKey(const Key('cart-checkout-cta')));
    expect(cta.onPressed, isNotNull);
  });

  testWidgets('Add more items opens the Catalog and refreshes the cart on return', (
    tester,
  ) async {
    cartRepository = FakeCartRepository(
      getCartResult: const CartView(
        items: [_lineItem],
        cartVersion: 1,
        quote: _quote,
        payNowQuote: _quote,
      ),
    );
    await pumpCart(tester);

    await tester.tap(find.byKey(const Key('cart-add-more')));
    await tester.pumpAndSettle();
    expect(find.text('catalog-page'), findsOneWidget);

    // Something was added while on the Catalog.
    cartRepository.getCartResult = mixedCart(version: 2);
    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('Buffalo Milk'), findsOneWidget);
    expect(find.text('SUBSCRIPTIONS'), findsOneWidget);
  });

  testWidgets('Shortfall hint and Top up show before confirming; Confirm stays enabled', (
    tester,
  ) async {
    cartRepository = FakeCartRepository(getCartResult: mixedCart());
    walletRepository.getWalletResult = _wallet(5000); // ₹50

    await pumpCart(tester);

    // Pay now ₹108.20 + ₹500 subscription minimum − ₹50 balance.
    expect(find.text('Add ₹558.20 to confirm this order'), findsOneWidget);
    expect(find.byKey(const Key('cart-wallet-topup')), findsOneWidget);
    final cta = tester.widget<FilledButton>(find.byKey(const Key('cart-checkout-cta')));
    expect(cta.onPressed, isNotNull);
  });

  testWidgets('Confirm Order places the order and lands on Order confirmed', (tester) async {
    cartRepository = FakeCartRepository(getCartResult: mixedCart());

    await pumpCart(tester);
    await tester.tap(find.byKey(const Key('cart-checkout-cta')));
    await tester.pumpAndSettle();

    expect(checkoutRepository.calls.single.cartVersion, 3);
    expect(checkoutRepository.calls.single.expectedPayNowPaise, 10820);
    expect(find.text('Order confirmed!'), findsOneWidget);
    expect(find.byKey(const Key('order-success-id')), findsOneWidget);
    expect(find.text('ord_1'), findsOneWidget);
  });

  testWidgets('Insufficient balance offers Top up, which opens the Wallet', (tester) async {
    cartRepository = FakeCartRepository(getCartResult: mixedCart());
    checkoutRepository.outcomes.add(
      const ApiException(
        errorCode: 'INSUFFICIENT_BALANCE',
        message: 'Not enough wallet balance',
        statusCode: 402,
        details: {'shortfallPaise': 2420},
      ),
    );

    await pumpCart(tester);
    await tester.tap(find.byKey(const Key('cart-checkout-cta')));
    await tester.pumpAndSettle();

    expect(find.text('Not enough wallet balance'), findsOneWidget);
    expect(find.text('Add ₹24.20 to place this order.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cart-topup-dialog-cta')));
    await tester.pumpAndSettle();
    expect(find.text('wallet-page'), findsOneWidget);
  });

  testWidgets('An incomplete checkout shows the finishing banner', (tester) async {
    cartRepository = FakeCartRepository(getCartResult: mixedCart());
    const incomplete = ApiException(
      errorCode: 'CHECKOUT_INCOMPLETE',
      message: 'finishing',
      statusCode: 503,
    );
    // More failures than the bloc's automatic retries.
    checkoutRepository.outcomes.addAll(List.filled(4, incomplete));

    await pumpCart(tester);
    await tester.tap(find.byKey(const Key('cart-checkout-cta')));
    // Real retry delays are 1s + 2s + 4s.
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cart-checkout-incomplete')), findsOneWidget);
    expect(checkoutRepository.calls.map((c) => c.idempotencyKey).toSet(), hasLength(1));
  });

  testWidgets('Confirm is disabled while a quantity change waits to be sent', (tester) async {
    cartRepository = FakeCartRepository(getCartResult: mixedCart());

    await pumpCart(tester);
    await tester.tap(find.byKey(const Key('cart-item-quantity-increase-li-1')));
    await tester.pump();

    FilledButton cta() => tester.widget<FilledButton>(find.byKey(const Key('cart-checkout-cta')));
    expect(cta().onPressed, isNull);
    await tester.tap(find.byKey(const Key('cart-checkout-cta')));
    await tester.pump();
    expect(checkoutRepository.calls, isEmpty);

    // The debounce fires and the write settles: Confirm comes back.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(cartRepository.updateItemRequests.single.items.first.quantity, 2);
    expect(cta().onPressed, isNotNull);
  });

  testWidgets('A pending checkout locks the cart and offers Finish placing order', (tester) async {
    // One line, so Add more items is on screen without scrolling.
    cartRepository = FakeCartRepository(
      getCartResult: const CartView(
        items: [_lineItem],
        cartVersion: 3,
        quote: _payNow,
        payNowQuote: _payNow,
      ),
    );
    pendingCheckoutStore.pending['user-1'] = const PendingCheckout(
      key: 'key-from-before',
      cartVersion: 2,
      expectedPayNowPaise: 9000,
    );

    await pumpCart(tester);

    expect(find.byKey(const Key('cart-checkout-incomplete')), findsOneWidget);
    expect(find.text('Finish placing order'), findsOneWidget);
    IconButton button(String key) => tester.widget<IconButton>(find.byKey(Key(key)));
    expect(button('cart-item-quantity-increase-li-1').onPressed, isNull);
    expect(button('cart-item-remove-li-1').onPressed, isNull);
    expect(
      tester.widget<TextButton>(find.byKey(const Key('cart-add-more'))).onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('cart-checkout-cta')));
    await tester.pumpAndSettle();
    final call = checkoutRepository.calls.single;
    expect(call.idempotencyKey, 'key-from-before');
    expect(call.cartVersion, 2);
    expect(call.expectedPayNowPaise, 9000);
  });

  testWidgets('The pending checkout is found even if the profile fails to load', (tester) async {
    cartRepository = FakeCartRepository(getCartResult: mixedCart());
    profileRepository.getMeException = const ApiException(
      errorCode: 'NETWORK_ERROR',
      message: 'offline',
    );
    pendingCheckoutStore.pending['user-1'] = const PendingCheckout(
      key: 'key-from-before',
      cartVersion: 2,
      expectedPayNowPaise: 9000,
    );

    await pumpCart(tester);

    expect(find.byKey(const Key('cart-checkout-incomplete')), findsOneWidget);
    expect(find.text('Finish placing order'), findsOneWidget);
  });

  testWidgets('An invalid line is marked inline after Confirm', (tester) async {
    cartRepository = FakeCartRepository(getCartResult: mixedCart());
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

    await pumpCart(tester);
    await tester.tap(find.byKey(const Key('cart-checkout-cta')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cart-item-error-li-2')), findsOneWidget);
    expect(find.text('Remove and add again to choose a delivery slot'), findsOneWidget);
  });
}
