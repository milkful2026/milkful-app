import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/core/router/app_router.dart';
import 'package:milkful_app/features/auth/bloc/auth_bloc.dart';
import 'package:milkful_app/features/auth/bloc/auth_event.dart';
import 'package:milkful_app/features/auth/bloc/auth_state.dart';

import '../../fakes/fake_auth_repository.dart';
import '../../fakes/fake_profile_repository.dart';
import '../../fakes/fake_secure_token_storage.dart';

void main() {
  late AuthBloc authBloc;

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
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('an authenticated user landing on / is redirected to /home', (tester) async {
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

  testWidgets('an unauthenticated user navigating to /home is redirected to /', (tester) async {
    authBloc = AuthBloc(
      authRepository: FakeAuthRepository(),
      tokenStorage: FakeSecureTokenStorage(),
      profileRepository: FakeProfileRepository(),
    );
    addTearDown(() => authBloc.close());

    final router = buildAppRouter(authBloc);
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go('/home');
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/');
  });
}
