import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/features/auth/data/profile_repository.dart';
import 'package:milkful_app/features/auth/models/user_profile.dart';
import 'package:milkful_app/features/cart/data/cart_repository.dart';
import 'package:milkful_app/features/cart/data/pricing_repository.dart';
import 'package:milkful_app/features/cart/data/wallet_balance_repository.dart';
import 'package:milkful_app/features/cart/models/quote.dart';
import 'package:milkful_app/features/cart/presentation/product_config_screen.dart';
import 'package:milkful_app/features/catalog/data/catalog_repository.dart';
import 'package:milkful_app/features/catalog/models/product.dart';

import '../../../fakes/fake_cart_repository.dart';
import '../../../fakes/fake_catalog_repository.dart';
import '../../../fakes/fake_pricing_repository.dart';
import '../../../fakes/fake_profile_repository.dart';
import '../../../fakes/fake_wallet_balance_repository.dart';

const _quote = Quote(
  basePrice: 65,
  taxAmount: 3.25,
  taxRate: 5,
  deliveryFee: 10,
  netPayable: 78.25,
);

const _oneTimeOnlyProduct = Product(
  id: 'curd-500g',
  categoryId: 'curd',
  name: 'Fresh Curd',
  description: 'Set curd',
  unit: '500g Cup',
  price: 45,
  stockState: StockState.inStock,
);

const _subscriptionProduct = Product(
  id: 'sub-milk',
  categoryId: 'milk',
  name: 'Daily Milk Pack',
  description: 'Subscribe and save',
  unit: '1L Bottle',
  price: 65,
  stockState: StockState.inStock,
  subscriptionEligible: true,
  availableQuantity: 3,
);

void main() {
  late FakeCatalogRepository catalogRepository;
  late FakePricingRepository pricingRepository;
  late FakeCartRepository cartRepository;
  late FakeWalletBalanceRepository walletBalanceRepository;
  late FakeProfileRepository profileRepository;
  late GoRouter router;

  Future<void> pumpProductConfig(WidgetTester tester, Product product) async {
    catalogRepository = FakeCatalogRepository(
      productsById: {product.id: product},
    );
    pricingRepository = FakePricingRepository(result: _quote);
    cartRepository = FakeCartRepository();
    walletBalanceRepository = FakeWalletBalanceRepository(balance: 600);
    profileRepository = FakeProfileRepository(
      profile: const UserProfile(
        userId: 'user-1',
        name: 'Priya Sharma',
        mobile: '+919876543210',
        accountType: 'B2C',
        defaultAddressId: 'addr-1',
        defaultAddressState: 'Karnataka',
      ),
    );
    router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const Placeholder()),
        GoRoute(
          path: '/product/:productId',
          builder: (context, state) => ProductConfigScreen(product: product),
        ),
      ],
    );
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<CatalogRepository>.value(value: catalogRepository),
          RepositoryProvider<PricingRepository>.value(value: pricingRepository),
          RepositoryProvider<CartRepository>.value(value: cartRepository),
          RepositoryProvider<WalletBalanceRepository>.value(
            value: walletBalanceRepository,
          ),
          RepositoryProvider<ProfileRepository>.value(value: profileRepository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/product/${product.id}');
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Non-subscription-eligible product skips the frequency selector',
    (tester) async {
      await pumpProductConfig(tester, _oneTimeOnlyProduct);

      expect(find.byKey(const Key('frequency-daily')), findsNothing);
      expect(find.byKey(const Key('frequency-alternate')), findsNothing);
      expect(find.byKey(const Key('frequency-one-time')), findsNothing);
      expect(find.byKey(const Key('start-date-calendar')), findsNothing);
      expect(find.text('Add to Cart'), findsOneWidget);
    },
  );

  testWidgets(
    'Selecting a subscription frequency reveals the calendar and relabels the CTA',
    (tester) async {
      await pumpProductConfig(tester, _subscriptionProduct);
      expect(find.text('Add to Cart'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('frequency-daily')));
      await tester.tap(find.byKey(const Key('frequency-daily')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('start-date-calendar')), findsOneWidget);
      expect(find.text('Subscribe Now'), findsOneWidget);
    },
  );

  testWidgets(
    'Quantity stepper respects the max and shows a scarcity caption',
    (tester) async {
      await pumpProductConfig(
        tester,
        _subscriptionProduct,
      ); // availableQuantity: 3

      await tester.ensureVisible(
        find.byKey(const Key('quantity-stepper-increase')),
      );
      await tester.tap(find.byKey(const Key('quantity-stepper-increase')));
      await tester.tap(find.byKey(const Key('quantity-stepper-increase')));
      await tester.pump();

      expect(find.text('3'), findsOneWidget);
      expect(find.text('Only 3 left'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('quantity-stepper-increase')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('Subscribe Now is disabled below the ₹500 wallet threshold', (
    tester,
  ) async {
    await pumpProductConfig(tester, _subscriptionProduct);
    walletBalanceRepository.balance = 300;

    await tester.ensureVisible(find.byKey(const Key('frequency-daily')));
    await tester.tap(find.byKey(const Key('frequency-daily')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'A minimum wallet balance of ₹500 is required for subscriptions — '
        'your balance is ₹300.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets(
    'Confirming a one-time add succeeds and returns to the previous screen',
    (tester) async {
      await pumpProductConfig(tester, _oneTimeOnlyProduct);

      await tester.ensureVisible(
        find.byKey(const Key('quantity-stepper-increase')),
      );
      await tester.tap(find.byKey(const Key('quantity-stepper-increase')));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 400),
      ); // clears the 300ms debounce

      await tester.tap(find.text('Add to Cart'));
      // A bounded pump (not pumpAndSettle) — the SnackBar's own default 4s
      // display duration would otherwise be fully waited out by
      // pumpAndSettle before this assertion ever runs, since it advances
      // through scheduled timers along with animations.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Added to cart'), findsOneWidget);
      expect(cartRepository.requests, hasLength(1));
      expect(cartRepository.requests.single.quantity, 2);
      expect(find.byType(Placeholder), findsOneWidget);
    },
  );
}
