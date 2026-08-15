import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/auth/bloc/auth_bloc.dart';
import 'package:milkful_app/features/auth/bloc/auth_event.dart';
import 'package:milkful_app/features/auth/presentation/login_otp_screen.dart';
import 'package:pinput/pinput.dart';

import '../../../fakes/fake_auth_repository.dart';
import '../../../fakes/fake_profile_repository.dart';
import '../../../fakes/fake_secure_token_storage.dart';

void main() {
  late FakeAuthRepository authRepository;
  late AuthBloc authBloc;
  late GoRouter router;

  // Same real-Timer.periodic caveat as onboarding's OtpScreen tests —
  // bounded tester.pump() calls only, never pumpAndSettle(), and the
  // manually-constructed AuthBloc is explicitly closed so its timer/
  // stream don't leak into the next test.
  Future<void> pumpLoginOtp(WidgetTester tester) async {
    authRepository = FakeAuthRepository();
    authBloc = AuthBloc(
      authRepository: authRepository,
      tokenStorage: FakeSecureTokenStorage(),
      profileRepository: FakeProfileRepository(),
    );
    addTearDown(() => authBloc.close());
    authBloc.add(const LoginOtpSendRequested('+919876543210'));
    router = GoRouter(
      initialLocation: '/login/otp',
      routes: [
        GoRoute(path: '/login/otp', builder: (context, state) => const LoginOtpScreen()),
        GoRoute(path: '/home', builder: (context, state) => const Placeholder()),
      ],
    );
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
  }

  testWidgets('resend is hidden behind a countdown, then becomes tappable after 30s', (
    tester,
  ) async {
    await pumpLoginOtp(tester);

    expect(find.text('Resend Code'), findsNothing);
    expect(find.textContaining('Resend Code in 0:30'), findsOneWidget);

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.text('Resend Code'), findsOneWidget);
  });

  testWidgets('a successful verify navigates to /home', (tester) async {
    await pumpLoginOtp(tester);

    await tester.enterText(find.byKey(const Key('login-otp-input')), '123456');
    await tester.pump();
    await tester.pump();

    expect(router.state.matchedLocation, '/home');
  });

  testWidgets('lockout after 3 failed attempts disables the input and shows the lockout copy', (
    tester,
  ) async {
    await pumpLoginOtp(tester);
    authRepository.verifyLoginOtpException = const ApiException(
      errorCode: 'OTP_ATTEMPTS_EXCEEDED',
      message: 'too many attempts',
    );

    await tester.enterText(find.byKey(const Key('login-otp-input')), '000000');
    await tester.pump();
    await tester.pump();

    expect(find.text('Too many attempts. Request a new code.'), findsOneWidget);
    final pinput = tester.widget<Pinput>(find.byKey(const Key('login-otp-input')));
    expect(pinput.enabled, isFalse);
  });
}
