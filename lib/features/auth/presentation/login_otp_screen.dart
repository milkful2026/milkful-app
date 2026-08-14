import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';

import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

/// MA-21 FR-2. Mirrors onboarding's OtpScreen (same countdown/error/
/// lockout pattern) but is its own screen, not a shared widget — separate
/// test key and copy strings per the spec's own UI component map, and a
/// different post-verify destination (Home, not the registration wizard).
class LoginOtpScreen extends StatefulWidget {
  const LoginOtpScreen({super.key});

  @override
  State<LoginOtpScreen> createState() => _LoginOtpScreenState();
}

class _LoginOtpScreenState extends State<LoginOtpScreen> {
  final _pinController = TextEditingController();
  Timer? _timer;
  int _secondsRemaining = 30;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    _startCountdown(authState is AuthOtpSent ? authState.resendAfter : 30);
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _secondsRemaining = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
      } else {
        setState(() => _secondsRemaining -= 1);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  String _errorText(String errorCode) => switch (errorCode) {
        'OTP_EXPIRED' => 'Code expired. Tap Resend Code.',
        'OTP_ATTEMPTS_EXCEEDED' => 'Too many attempts. Request a new code.',
        _ => 'Invalid code. Try again.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your number')),
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            context.go('/home');
          }
          if (state is AuthOtpSent) {
            _startCountdown(state.resendAfter);
          }
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("We've sent a 6-digit code to your mobile number."),
                const SizedBox(height: 24),
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    final locked = state is AuthOtpVerifyFailure &&
                        state.errorCode == 'OTP_ATTEMPTS_EXCEEDED';
                    return Pinput(
                      key: const Key('login-otp-input'),
                      length: 6,
                      controller: _pinController,
                      enabled: !locked,
                      onCompleted: (otp) =>
                          context.read<AuthBloc>().add(LoginOtpVerifyRequested(otp)),
                    );
                  },
                ),
                const SizedBox(height: 16),
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    if (state is AuthOtpVerifyFailure) {
                      return Text(
                        _errorText(state.errorCode),
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (_secondsRemaining > 0)
                      Text('Resend Code in 0:${_secondsRemaining.toString().padLeft(2, '0')}')
                    else
                      BlocBuilder<AuthBloc, AuthState>(
                        builder: (context, state) {
                          final mobile = switch (state) {
                            AuthOtpSent(:final mobile) => mobile,
                            AuthOtpVerifying(:final mobile) => mobile,
                            AuthOtpVerifyFailure(:final mobile) => mobile,
                            _ => null,
                          };
                          return TextButton(
                            onPressed: mobile == null
                                ? null
                                : () => context
                                    .read<AuthBloc>()
                                    .add(LoginOtpResendRequested(mobile)),
                            child: const Text('Resend Code'),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    if (state is! AuthOtpVerifying) return const SizedBox.shrink();
                    return const Center(child: CircularProgressIndicator());
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
