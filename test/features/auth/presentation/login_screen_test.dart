import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/auth/bloc/auth_bloc.dart';
import 'package:milkful_app/features/auth/presentation/login_screen.dart';

import '../../../fakes/fake_auth_repository.dart';
import '../../../fakes/fake_profile_repository.dart';
import '../../../fakes/fake_secure_token_storage.dart';

void main() {
  late FakeAuthRepository authRepository;
  late AuthBloc authBloc;
  late GoRouter router;

  Future<void> pumpLogin(WidgetTester tester) async {
    authRepository = FakeAuthRepository();
    authBloc = AuthBloc(
      authRepository: authRepository,
      tokenStorage: FakeSecureTokenStorage(),
      profileRepository: FakeProfileRepository(),
    );
    addTearDown(() => authBloc.close());
    router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
        GoRoute(path: '/login/otp', builder: (context, state) => const Placeholder()),
        GoRoute(path: '/signup', builder: (context, state) => const Placeholder()),
      ],
    );
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  testWidgets('Continue is disabled for fewer than 10 digits', (tester) async {
    await pumpLogin(tester);

    await tester.enterText(find.bySemanticsLabel('Mobile number'), '98765');
    await tester.pump();

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'));
    expect(button.onPressed, isNull);
  });

  testWidgets('Continue is enabled once exactly 10 digits are entered', (tester) async {
    await pumpLogin(tester);

    await tester.enterText(find.bySemanticsLabel('Mobile number'), '9876543210');
    await tester.pump();

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('tapping Continue navigates to /login/otp on success', (tester) async {
    await pumpLogin(tester);

    await tester.enterText(find.bySemanticsLabel('Mobile number'), '9876543210');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/login/otp');
  });

  testWidgets('an unregistered number shows a Sign up link, no OTP sent', (tester) async {
    await pumpLogin(tester);
    authRepository.sendLoginOtpException = const ApiException(
      errorCode: 'USER_NOT_FOUND',
      message: 'no account',
    );

    await tester.enterText(find.bySemanticsLabel('Mobile number'), '9876543210');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('No account found for this number.'), findsOneWidget);
    expect(find.text('Sign up'), findsOneWidget);
    expect(router.state.matchedLocation, '/login');
  });

  testWidgets('a non-USER_NOT_FOUND send failure shows its error message', (tester) async {
    await pumpLogin(tester);
    authRepository.sendLoginOtpException = const ApiException(
      errorCode: 'RATE_LIMIT_EXCEEDED',
      message: 'Too many attempts',
    );

    await tester.enterText(find.bySemanticsLabel('Mobile number'), '9876543210');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Too many attempts'), findsOneWidget);
    expect(find.text('Sign up'), findsNothing);
  });

  testWidgets('tapping Sign up from the not-found state navigates to /signup', (tester) async {
    await pumpLogin(tester);
    authRepository.sendLoginOtpException = const ApiException(
      errorCode: 'USER_NOT_FOUND',
      message: 'no account',
    );
    await tester.enterText(find.bySemanticsLabel('Mobile number'), '9876543210');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/signup');
  });
}
