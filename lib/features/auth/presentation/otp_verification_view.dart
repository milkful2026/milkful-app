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
    // The new "Verify & Proceed" button's enabled state depends on the
    // pin's current length — Pinput's own onCompleted callback doesn't fire
    // until the field is already full, so this listener is what lets the
    // button light up in step with typing rather than only after the fact.
    _pinController.addListener(() => setState(() {}));
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
    final theme = Theme.of(context);
    final pinTheme = PinTheme(
      width: 48,
      height: 52,
      textStyle: theme.textTheme.titleLarge,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
    );
    final focusedPinTheme = pinTheme.copyWith(
      decoration: pinTheme.decoration!.copyWith(
        border: Border.all(color: theme.colorScheme.primary, width: 2),
      ),
    );

    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
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
                Center(
                  child: CircleAvatar(
                    radius: 36,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.sms_outlined, size: 32, color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    'Verify your number',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: Text(widget.bodyText, textAlign: TextAlign.center),
                ),
                const SizedBox(height: 24),
                Center(
                  child: BlocBuilder<AuthBloc, AuthState>(
                    builder: (context, state) {
                      final locked = state is AuthOtpVerifyFailure &&
                          state.errorCode == 'OTP_ATTEMPTS_EXCEEDED';
                      return Pinput(
                        key: widget.pinKey,
                        length: 6,
                        controller: _pinController,
                        enabled: !locked,
                        defaultPinTheme: pinTheme,
                        focusedPinTheme: focusedPinTheme,
                        onCompleted: (otp) => widget.onCompleted(context, otp),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    if (state is AuthOtpVerifyFailure) {
                      return Text(
                        _errorText(state.errorCode),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const SizedBox(height: 24),
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    final verifying = state is AuthOtpVerifying;
                    return SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _pinController.text.length != 6 || verifying
                            ? null
                            : () => widget.onCompleted(context, _pinController.text),
                        child: verifying
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Verify & Proceed'),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Center(
                  child: _secondsRemaining > 0
                      ? Text(
                          '${widget.resendLabel} in 0:${_secondsRemaining.toString().padLeft(2, '0')}',
                        )
                      : BlocBuilder<AuthBloc, AuthState>(
                          builder: (context, state) {
                            final mobile = switch (state) {
                              AuthOtpSent(:final mobile) => mobile,
                              AuthOtpVerifying(:final mobile) => mobile,
                              AuthOtpVerifyFailure(:final mobile) => mobile,
                              _ => null,
                            };
                            return TextButton(
                              onPressed:
                                  mobile == null ? null : () => widget.onResend(context, mobile),
                              child: Text(widget.resendLabel),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
