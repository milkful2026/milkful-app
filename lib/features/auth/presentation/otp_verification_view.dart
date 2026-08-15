import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pinput/pinput.dart';

import '../bloc/auth_bloc.dart';
import '../bloc/auth_state.dart';

/// Shared countdown/error/lockout OTP-entry UI for both the registration
/// flow's OtpScreen and the login flow's LoginOtpScreen — the two used to
/// duplicate this almost verbatim (countdown timer, dispose, error
/// mapping), so a fix to one (e.g. the off-by-one at
/// `_secondsRemaining <= 1`, or a resend-count limit) could silently miss
/// the other. Callers supply only what actually differs: copy, the
/// Pinput's test key, the verify/resend events to dispatch, and what
/// happens once AuthAuthenticated arrives.
class OtpVerificationView extends StatefulWidget {
  const OtpVerificationView({
    super.key,
    required this.bodyText,
    required this.pinKey,
    required this.resendLabel,
    required this.onCompleted,
    required this.onResend,
    required this.onAuthenticated,
  });

  final String bodyText;
  final Key pinKey;

  /// Used both for the button ("Resend OTP"/"Resend Code") and the
  /// countdown text ("$resendLabel in 0:30").
  final String resendLabel;

  final void Function(BuildContext context, String otp) onCompleted;
  final void Function(BuildContext context, String mobile) onResend;
  final Future<void> Function(BuildContext context) onAuthenticated;

  @override
  State<OtpVerificationView> createState() => _OtpVerificationViewState();
}

class _OtpVerificationViewState extends State<OtpVerificationView> {
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
        'OTP_EXPIRED' => 'Code expired. Tap ${widget.resendLabel}.',
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
            await widget.onAuthenticated(context);
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
                Text(widget.bodyText),
                const SizedBox(height: 24),
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    final locked = state is AuthOtpVerifyFailure &&
                        state.errorCode == 'OTP_ATTEMPTS_EXCEEDED';
                    return Pinput(
                      key: widget.pinKey,
                      length: 6,
                      controller: _pinController,
                      enabled: !locked,
                      onCompleted: (otp) => widget.onCompleted(context, otp),
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
                      Text(
                        '${widget.resendLabel} in 0:${_secondsRemaining.toString().padLeft(2, '0')}',
                      )
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
                                : () => widget.onResend(context, mobile),
                            child: Text(widget.resendLabel),
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
