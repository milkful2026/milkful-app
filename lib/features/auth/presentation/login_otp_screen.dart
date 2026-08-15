import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import 'otp_verification_view.dart';

/// MA-21 FR-2. Mirrors onboarding's OtpScreen via the shared
/// OtpVerificationView (same countdown/error/lockout pattern) but supplies
/// its own copy/test key per the spec's UI component map, and a different
/// post-verify destination (Home, not the registration wizard).
class LoginOtpScreen extends StatelessWidget {
  const LoginOtpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return OtpVerificationView(
      bodyText: "We've sent a 6-digit code to your mobile number.",
      pinKey: const Key('login-otp-input'),
      resendLabel: 'Resend Code',
      onCompleted: (context, otp) =>
          context.read<AuthBloc>().add(LoginOtpVerifyRequested(otp)),
      onResend: (context, mobile) =>
          context.read<AuthBloc>().add(LoginOtpResendRequested(mobile)),
      onAuthenticated: (context) async {
        context.go('/home');
      },
    );
  }
}
