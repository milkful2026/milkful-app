import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/core/router/app_router.dart';
import 'package:milkful_app/features/auth/bloc/auth_bloc.dart';
import 'package:milkful_app/features/auth/bloc/auth_event.dart';
import 'package:milkful_app/features/auth/bloc/auth_state.dart';
import 'package:milkful_app/features/auth/data/profile_repository.dart';
import 'package:milkful_app/features/cart/data/cart_repository.dart';
import 'package:milkful_app/features/cart/data/pricing_repository.dart';
import 'package:milkful_app/features/cart/data/wallet_balance_repository.dart';
import 'package:milkful_app/features/catalog/data/catalog_repository.dart';
import 'package:milkful_app/features/catalog/models/product.dart';
import 'package:milkful_app/features/onboarding/bloc/registration_bloc.dart';

import '../../fakes/fake_auth_repository.dart';
import '../../fakes/fake_cart_repository.dart';
import '../../fakes/fake_catalog_repository.dart';
import '../../fakes/fake_draft_storage.dart';
import '../../fakes/fake_pricing_repository.dart';
import '../../fakes/fake_profile_repository.dart';
import '../../fakes/fake_registration_repository.dart';
import '../../fakes/fake_secure_token_storage.dart';
import '../../fakes/fake_wallet_balance_repository.dart';

const _cowMilk = Product(
  id: 'cow-milk',
  categoryId: 'milk',
  name: 'Cow Milk',
  description: 'Farm-fresh cow milk',
  unit: '1L Bottle',
  price: 68,
  stockState: StockState.inStock,
);

void main() {
  late AuthBloc authBloc;

  Widget wrapRouter(GoRouter router, AuthBloc authBloc) =>
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<CatalogRepository>.value(
            value: FakeCatalogRepository(productsById: {'cow-milk': _cowMilk}),
          ),
          RepositoryProvider<PricingRepository>.value(
            value: FakePricingRepository(),
          ),
          RepositoryProvider<CartRepository>.value(value: FakeCartRepository()),
          RepositoryProvider<WalletBalanceRepository>.value(
            value: FakeWalletBalanceRepository(),
          ),
          RepositoryProvider<ProfileRepository>.value(
            value: FakeProfileRepository(),
          ),
        ],
        child: BlocProvider<AuthBloc>.value(
          value: authBloc,
          child: BlocProvider<RegistrationBloc>(
            // Home now reads this directly (the inline name prompt +
            // calendar picker), so any test that can route to /home needs
            // one provided, same as the real app's MultiBlocProvider.
            create: (_) => RegistrationBloc(
              repository: FakeRegistrationRepository(),
              draftStorage: FakeDraftStorage(),
            ),
            child: MaterialApp.router(routerConfig: router),
          ),
        ),
      );

  Future<GoRouter> pumpAuthenticatedRouter(WidgetTester tester) async {
    final tokenStorage = FakeSecureTokenStorage()
      ..refreshToken = 'stored-refresh'
      ..accessToken = 'stored-access'
      ..accessTokenExpiresAt = DateTime.now().add(const Duration(hours: 1));
    authBloc = AuthBloc(
      authRepository: FakeAuthRepository(),
      tokenStorage: tokenStorage,
      profileRepository: FakeProfileRepository(),
    );
    addTearDown(() => authBloc.close());
    authBloc.add(const SessionBootstrapRequested());
    await authBloc.stream.firstWhere((s) => s is AuthAuthenticated);

    final router = buildAppRouter(authBloc);
    await tester.pumpWidget(wrapRouter(router, authBloc));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('an authenticated user landing on / is redirected to /home', (
    tester,
  ) async {
    final router = await pumpAuthenticatedRouter(tester);

    expect(router.state.matchedLocation, '/home');
  });

  testWidgets(
    'an authenticated user navigating to /login (e.g. web back-button, deep '
    'link) is left there, not bounced to /home — this is what would strand a '
    'mid-registration user off their in-progress wizard',
    (tester) async {
      final router = await pumpAuthenticatedRouter(tester);
      expect(router.state.matchedLocation, '/home');

      router.go('/login');
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, '/login');
    },
  );

  testWidgets(
    'an unauthenticated user navigating to /home is redirected to /',
    (tester) async {
      authBloc = AuthBloc(
        authRepository: FakeAuthRepository(),
        tokenStorage: FakeSecureTokenStorage(),
        profileRepository: FakeProfileRepository(),
      );
      addTearDown(() => authBloc.close());

      final router = buildAppRouter(authBloc);
      await tester.pumpWidget(wrapRouter(router, authBloc));
      await tester.pumpAndSettle();

      router.go('/home');
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, '/');
    },
  );

  testWidgets(
    '/product/:productId with a Product passed via extra: renders the configuration screen',
    (tester) async {
      final router = await pumpAuthenticatedRouter(tester);

      router.push('/product/cow-milk', extra: _cowMilk);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, '/product/cow-milk');
      expect(find.text('Cow Milk'), findsOneWidget);
    },
  );

  testWidgets(
    '/product/:productId with no extra: (e.g. a deep link) falls back to Home instead of crashing',
    (tester) async {
      final router = await pumpAuthenticatedRouter(tester);

      router.push('/product/cow-milk');
      await tester.pumpAndSettle();

      expect(find.text('Cow Milk'), findsNothing);
    },
  );
}
