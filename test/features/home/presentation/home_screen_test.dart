import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/features/auth/bloc/auth_bloc.dart';
import 'package:milkful_app/features/auth/bloc/auth_event.dart';
import 'package:milkful_app/features/auth/models/user_profile.dart';
import 'package:milkful_app/features/catalog/data/catalog_repository.dart';
import 'package:milkful_app/features/home/presentation/home_screen.dart';
import 'package:milkful_app/features/onboarding/bloc/registration_bloc.dart';

import '../../../fakes/fake_auth_repository.dart';
import '../../../fakes/fake_catalog_repository.dart';
import '../../../fakes/fake_draft_storage.dart';
import '../../../fakes/fake_profile_repository.dart';
import '../../../fakes/fake_registration_repository.dart';
import '../../../fakes/fake_secure_token_storage.dart';

void main() {
  late FakeAuthRepository authRepository;
  late FakeSecureTokenStorage tokenStorage;
  late AuthBloc authBloc;

  Widget wrapHome(AuthBloc authBloc) => RepositoryProvider<CatalogRepository>.value(
        value: FakeCatalogRepository(),
        child: BlocProvider<AuthBloc>.value(
          value: authBloc,
          child: BlocProvider<RegistrationBloc>(
            create: (_) => RegistrationBloc(
              repository: FakeRegistrationRepository(),
              draftStorage: FakeDraftStorage(),
            ),
            child: const MaterialApp(home: HomeScreen()),
          ),
        ),
      );

  Future<void> pumpHome(WidgetTester tester) async {
    authRepository = FakeAuthRepository();
    tokenStorage = FakeSecureTokenStorage()
      ..accessToken = 'stored-access'
      ..refreshToken = 'stored-refresh';
    authBloc = AuthBloc(
      authRepository: authRepository,
      tokenStorage: tokenStorage,
      profileRepository: FakeProfileRepository(),
    );
    addTearDown(() => authBloc.close());
    await tester.pumpWidget(wrapHome(authBloc));
  }

  testWidgets('B2B account shows the role indicator chip', (tester) async {
    authRepository = FakeAuthRepository();
    tokenStorage = FakeSecureTokenStorage()
      ..refreshToken = 'stored-refresh'
      ..accessToken = 'stored-access'
      ..accessTokenExpiresAt = DateTime.now().add(const Duration(hours: 1));
    authBloc = AuthBloc(
      authRepository: authRepository,
      tokenStorage: tokenStorage,
      profileRepository: FakeProfileRepository(
        profile: const UserProfile(
          userId: 'user-1',
          name: 'B2B Buyer',
          mobile: '+919876543210',
          accountType: 'B2B',
          defaultAddressId: 'addr-1',
        ),
      ),
    );
    addTearDown(() => authBloc.close());
    // SessionBootstrapRequested is the real path that resolves
    // accountType via GET /users/me — the same one app startup uses.
    authBloc.add(const SessionBootstrapRequested());
    await tester.pumpWidget(wrapHome(authBloc));
    await tester.pump();
    await tester.pump();

    expect(find.text('B2B account'), findsOneWidget);
  });

  testWidgets('Cancel in the logout dialog leaves the session intact', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('logout-action')));
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(authRepository.loggedOutWith, isEmpty);
    expect(tokenStorage.accessToken, 'stored-access');
  });

  testWidgets('Confirming in the logout dialog logs out and clears storage', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('logout-action')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Log out'));
    await tester.pumpAndSettle();

    expect(authRepository.loggedOutWith, ['stored-refresh']);
    expect(tokenStorage.accessToken, isNull);
  });

  testWidgets('Tapping the cart FAB navigates to /cart', (tester) async {
    authRepository = FakeAuthRepository();
    tokenStorage = FakeSecureTokenStorage()
      ..accessToken = 'stored-access'
      ..refreshToken = 'stored-refresh';
    authBloc = AuthBloc(
      authRepository: authRepository,
      tokenStorage: tokenStorage,
      profileRepository: FakeProfileRepository(),
    );
    addTearDown(() => authBloc.close());

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
        GoRoute(path: '/cart', builder: (context, state) => const Placeholder()),
      ],
    );

    await tester.pumpWidget(
      RepositoryProvider<CatalogRepository>.value(
        value: FakeCatalogRepository(),
        child: BlocProvider<AuthBloc>.value(
          value: authBloc,
          child: BlocProvider<RegistrationBloc>(
            create: (_) => RegistrationBloc(
              repository: FakeRegistrationRepository(),
              draftStorage: FakeDraftStorage(),
            ),
            child: MaterialApp.router(routerConfig: router),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('cart-fab')));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/cart');
  });
}
