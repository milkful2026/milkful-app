import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';

/// FR-1. Spec's UI component map allows `intl_phone_field` "or custom" for
/// the phone input — a plain TextField with a fixed +91 prefix and
/// digits-only 10-char validation is used here instead of the package, to
/// keep this screen's third-party surface (and therefore test risk) small.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _controller = TextEditingController();

  // MA-21: registration's OTP send and the "Log in" link's login OTP send
  // both land in the same AuthOtpSent/AuthOtpSending states (see
  // auth_bloc.dart's shared OTP-state design) — a BlocBuilder narrowed to
  // `state is AuthUserAlreadyExists` loses that fact the moment sending
  // starts (the state moves on to AuthOtpSending), so these two flags are
  // tracked locally via the listener instead of re-derived from the
  // bloc's current state on every build.
  bool _userAlreadyExists = false;
  bool _loggingIn = false;

  bool get _isValid => RegExp(r'^\d{10}$').hasMatch(_controller.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign up')),
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthUserAlreadyExists) {
            setState(() => _userAlreadyExists = true);
          }
          if (state is AuthOtpSent) {
            context.go(_loggingIn ? '/login/otp' : '/otp', extra: state.mobile);
          }
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter your mobile number',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                Semantics(
                  label: 'Mobile number',
                  child: TextField(
                    controller: _controller,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      prefixText: '+91  ',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    onChanged: (value) => setState(() {
                      // A number has been changed since the "already
                      // exists" verdict — that verdict no longer applies
                      // to whatever's currently typed.
                      _userAlreadyExists = false;
                    }),
                  ),
                ),
                const SizedBox(height: 16),
                if (_userAlreadyExists)
                  BlocBuilder<AuthBloc, AuthState>(
                    builder: (context, state) {
                      final loggingIn = _loggingIn && state is AuthOtpSending;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          children: [
                            const Expanded(child: Text('Already registered?')),
                            if (loggingIn)
                              const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              TextButton(
                                onPressed: () {
                                  setState(() => _loggingIn = true);
                                  context
                                      .read<AuthBloc>()
                                      .add(LoginOtpSendRequested('+91${_controller.text}'));
                                },
                                child: const Text('Log in'),
                              ),
                          ],
                        ),
                      );
                    },
                  )
                else
                  BlocBuilder<AuthBloc, AuthState>(
                    builder: (context, state) {
                      if (state is! AuthOtpSendFailure) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          state.message,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      );
                    },
                  ),
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    final sending = state is AuthOtpSending && !_loggingIn;
                    return SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: !_isValid || sending
                            ? null
                            : () {
                                setState(() {
                                  _loggingIn = false;
                                  _userAlreadyExists = false;
                                });
                                context
                                    .read<AuthBloc>()
                                    .add(OtpSendRequested('+91${_controller.text}'));
                              },
                        child: sending
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Send OTP'),
                      ),
                    );
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
