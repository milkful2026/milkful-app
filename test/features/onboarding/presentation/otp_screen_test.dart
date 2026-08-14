import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/core/storage/draft_storage.dart';
import 'package:milkful_app/features/auth/bloc/auth_bloc.dart';
import 'package:milkful_app/features/auth/bloc/auth_event.dart';
import 'package:milkful_app/features/onboarding/bloc/registration_bloc.dart';
import 'package:milkful_app/features/onboarding/presentation/otp_screen.dart';

import '../../../fakes/fake_auth_repository.dart';
import '../../../fakes/fake_draft_storage.dart';
import '../../../fakes/fake_profile_repository.dart';
import '../../../fakes/fake_registration_repository.dart';
import '../../../fakes/fake_secure_token_storage.dart';

void main() {
  late FakeAuthRepository authRepository;
  late AuthBloc authBloc;

  // OtpScreen starts a real Timer.periodic (30s countdown) in initState —
  // pumpAndSettle() never converges against a live periodic timer and
  // hangs until the test framework's own timeout, so every test here uses
  // bounded tester.pump() calls instead, and explicitly closes the
  // manually-constructed AuthBloc so its stream controller (and the
  // widget's timer, via dispose()) don't leak into the next test.
  Future<void> pumpOtp(WidgetTester tester) async {
    authRepository = FakeAuthRepository();
    authBloc = AuthBloc(
      authRepository: authRepository,
      tokenStorage: FakeSecureTokenStorage(),
      profileRepository: FakeProfileRepository(),
    );
    addTearDown(() => authBloc.close());
    // Drive the bloc into AuthOtpSent through a real event rather than
    // reaching for Bloc.emit (protected, not callable from a test).
    authBloc.add(const OtpSendRequested('+919876543210'));
    await tester.pumpWidget(
      MaterialApp(
        home: MultiRepositoryProvider(
          providers: [RepositoryProvider<DraftStorage>.value(value: FakeDraftStorage())],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: authBloc),
              BlocProvider(
                create: (_) => RegistrationBloc(
                  repository: FakeRegistrationRepository(),
                  draftStorage: FakeDraftStorage(),
                ),
              ),
            ],
            child: const OtpScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('resend is hidden behind a countdown, then becomes tappable after 30s', (
    tester,
  ) async {
    await pumpOtp(tester);

    expect(find.text('Resend OTP'), findsNothing);
    expect(find.textContaining('Resend OTP in 0:30'), findsOneWidget);

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.text('Resend OTP'), findsOneWidget);
    expect(find.textContaining('Resend OTP in'), findsNothing);
  });

  testWidgets('an invalid OTP shows the spec-mandated error copy', (tester) async {
    await pumpOtp(tester);
    authRepository.verifyOtpException = const ApiException(
      errorCode: 'OTP_INVALID',
      message: 'Invalid code',
    );

    await tester.enterText(find.byKey(const Key('otp-input')), '000000');
    await tester.pump();
    await tester.pump();

    expect(find.text('Invalid code. Try again.'), findsOneWidget);
  });

  testWidgets('an expired OTP shows the spec-mandated error copy', (tester) async {
    await pumpOtp(tester);
    authRepository.verifyOtpException = const ApiException(
      errorCode: 'OTP_EXPIRED',
      message: 'expired',
    );

    await tester.enterText(find.byKey(const Key('otp-input')), '000000');
    await tester.pump();
    await tester.pump();

    expect(find.text('Code expired. Tap Resend OTP.'), findsOneWidget);
  });
}
