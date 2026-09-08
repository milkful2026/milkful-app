import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/features/cart/data/cart_repository.dart';
import 'package:milkful_app/features/cart/models/cart_line_item.dart';
import 'package:milkful_app/features/cart/models/cart_view.dart';
import 'package:milkful_app/features/cart/models/frequency.dart';
import 'package:milkful_app/features/cart/models/quote.dart';
import 'package:milkful_app/features/cart/presentation/cart_screen.dart';
import 'package:milkful_app/features/catalog/data/catalog_repository.dart';
import 'package:milkful_app/features/catalog/models/product.dart';

import '../../../fakes/fake_cart_repository.dart';
import '../../../fakes/fake_catalog_repository.dart';

const _cowMilk = Product(
  id: 'cow-milk',
  categoryId: 'milk',
  name: 'Cow Milk',
  description: 'Farm-fresh cow milk',
  unit: '1L Bottle',
  price: 68,
  stockState: StockState.inStock,
);

const _lineItem = CartLineItem(
  id: 'li-1',
  productId: 'cow-milk',
  quantity: 1,
  frequency: Frequency.oneTime,
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

void main() {
  late FakeCartRepository cartRepository;
  late FakeCatalogRepository catalogRepository;
  late GoRouter router;

  Future<void> pumpCart(WidgetTester tester) async {
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const Placeholder()),
        GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
        GoRoute(path: '/catalog', builder: (context, state) => const Placeholder()),
      ],
    );
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<CartRepository>.value(value: cartRepository),
          RepositoryProvider<CatalogRepository>.value(value: catalogRepository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/cart');
    await tester.pumpAndSettle();
  }

  setUp(() {
    catalogRepository = FakeCatalogRepository(productsById: {'cow-milk': _cowMilk});
  });

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
}
