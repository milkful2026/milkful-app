import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';

import '../../../core/storage/draft_storage.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';
import '../bloc/registration_bloc.dart';
import '../bloc/registration_event.dart';

/// FR-2.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _pinController = TextEditingController();
  Timer? _timer;
  int _secondsRemaining = 30;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsRemaining = 30);
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
        'OTP_EXPIRED' => 'Code expired. Tap Resend OTP.',
        'OTP_ATTEMPTS_EXCEEDED' => 'Too many attempts. Request a new code.',
        _ => 'Invalid code. Try again.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your number')),
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) async {
          if (state is AuthAuthenticated) {
            final draft = await context.read<DraftStorage>().load();
            if (!context.mounted) return;
            context.read<RegistrationBloc>().add(DraftRestored(draft));
            context.go('/profile');
          }
          if (state is AuthOtpSent) {
            _startCountdown();
          }
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Enter the 6-digit code we sent you'),
                const SizedBox(height: 24),
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    final locked = state is AuthOtpVerifyFailure &&
                        state.errorCode == 'OTP_ATTEMPTS_EXCEEDED';
                    return Pinput(
                      key: const Key('otp-input'),
                      length: 6,
                      controller: _pinController,
                      enabled: !locked,
                      onCompleted: (otp) =>
                          context.read<AuthBloc>().add(OtpVerifyRequested(otp)),
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
                      Text('Resend OTP in 0:${_secondsRemaining.toString().padLeft(2, '0')}')
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
                                    .add(OtpResendRequested(mobile)),
                            child: const Text('Resend OTP'),
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
