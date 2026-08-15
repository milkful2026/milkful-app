import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/auth/bloc/auth_bloc.dart';
import 'package:milkful_app/features/onboarding/presentation/signup_screen.dart';

import '../../../fakes/fake_auth_repository.dart';
import '../../../fakes/fake_profile_repository.dart';
import '../../../fakes/fake_secure_token_storage.dart';

void main() {
  late FakeAuthRepository authRepository;
  late AuthBloc authBloc;
  late GoRouter router;

  // SignupScreen navigates via context.go on OTP-sent — a real (if
  // minimal) GoRouter is needed so that call has somewhere to land,
  // rather than throwing for lack of a Router ancestor.
  Future<void> pumpSignup(WidgetTester tester) async {
    authRepository = FakeAuthRepository();
    authBloc = AuthBloc(
      authRepository: authRepository,
      tokenStorage: FakeSecureTokenStorage(),
      profileRepository: FakeProfileRepository(),
    );
    addTearDown(() => authBloc.close());
    router = GoRouter(
      initialLocation: '/signup',
      routes: [
        GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
        GoRoute(path: '/otp', builder: (context, state) => const Placeholder()),
        GoRoute(path: '/login/otp', builder: (context, state) => const Placeholder()),
      ],
    );
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  testWidgets('Send OTP is disabled for fewer than 10 digits', (tester) async {
    await pumpSignup(tester);

    await tester.enterText(find.bySemanticsLabel('Mobile number'), '98765');
    await tester.pump();

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send OTP'));
    expect(button.onPressed, isNull);
  });

  testWidgets('Send OTP is enabled once exactly 10 digits are entered', (tester) async {
    await pumpSignup(tester);

    await tester.enterText(find.bySemanticsLabel('Mobile number'), '9876543210');
    await tester.pump();

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send OTP'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('non-digit characters are filtered out of the mobile field', (tester) async {
    await pumpSignup(tester);

    await tester.enterText(find.bySemanticsLabel('Mobile number'), '98a76!54@321#0');
    await tester.pump();

    expect(find.text('9876543210'), findsOneWidget);
  });

  testWidgets('tapping Send OTP navigates to /otp, not /login/otp', (tester) async {
    await pumpSignup(tester);

    await tester.enterText(find.bySemanticsLabel('Mobile number'), '9876543210');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send OTP'));
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/otp');
  });

  testWidgets('USER_EXISTS shows a Log in link; tapping it fires a login OTP send '
      'and navigates to /login/otp, not /otp', (tester) async {
    await pumpSignup(tester);
    authRepository.sendOtpException = const ApiException(
      errorCode: 'USER_EXISTS',
      message: 'already registered',
    );

    await tester.enterText(find.bySemanticsLabel('Mobile number'), '9876543210');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send OTP'));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsOneWidget);

    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(authRepository.loginSentTo, ['+919876543210']);
    expect(router.state.matchedLocation, '/login/otp');
  });

  testWidgets('editing the mobile number after USER_EXISTS hides the Log in link again', (
    tester,
  ) async {
    await pumpSignup(tester);
    authRepository.sendOtpException = const ApiException(
      errorCode: 'USER_EXISTS',
      message: 'already registered',
    );

    await tester.enterText(find.bySemanticsLabel('Mobile number'), '9876543210');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send OTP'));
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsOneWidget);

    await tester.enterText(find.bySemanticsLabel('Mobile number'), '9876543211');
    await tester.pump();

    expect(find.text('Log in'), findsNothing);
  });

  testWidgets(
    'a failed login OTP send (not USER_NOT_FOUND) shows an error message, '
    'not silence, and the Log in button becomes tappable again',
    (tester) async {
      await pumpSignup(tester);
      authRepository.sendOtpException = const ApiException(
        errorCode: 'USER_EXISTS',
        message: 'already registered',
      );

      await tester.enterText(find.bySemanticsLabel('Mobile number'), '9876543210');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Send OTP'));
      await tester.pumpAndSettle();
      expect(find.text('Log in'), findsOneWidget);

      authRepository.sendLoginOtpException = const ApiException(
        errorCode: 'RATE_LIMIT_EXCEEDED',
        message: 'Too many attempts',
      );
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();

      expect(find.text('Too many attempts'), findsOneWidget);
      expect(find.text('Log in'), findsOneWidget);
    },
  );

  testWidgets(
    'Send OTP is disabled while a login send is in flight, preventing a '
    'concurrent registration send from racing it',
    (tester) async {
      await pumpSignup(tester);
      authRepository.sendOtpException = const ApiException(
        errorCode: 'USER_EXISTS',
        message: 'already registered',
      );

      await tester.enterText(find.bySemanticsLabel('Mobile number'), '9876543210');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Send OTP'));
      await tester.pumpAndSettle();
      expect(find.text('Log in'), findsOneWidget);

      final gate = Completer<void>();
      authRepository.sendLoginOtpGate = gate;
      await tester.tap(find.text('Log in'));
      await tester.pump();

      final sendButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Send OTP'),
      );
      expect(sendButton.onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();
    },
  );
}
