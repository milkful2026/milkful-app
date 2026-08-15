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

  // MA-21: `AuthUserAlreadyExists` doesn't persist once the "Log in" link
  // triggers a login OTP send (state moves on to AuthOtpSending), so this
  // one flag is still tracked locally via the listener. Which *flow* a
  // subsequent AuthOtpSending/AuthOtpSent/AuthOtpSendFailure belongs to is
  // no longer guessed from a second local flag — it's read directly off
  // each state's own `flow` field (see auth_state.dart's OtpFlow), so a
  // failed login send can't be silently dropped, and a concurrent
  // registration send can't cross-wire with an in-flight login send.
  bool _userAlreadyExists = false;

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
            context.go(state.flow == OtpFlow.login ? '/login/otp' : '/otp', extra: state.mobile);
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
                      final loggingIn = state is AuthOtpSending && state.flow == OtpFlow.login;
                      final loginFailure =
                          state is AuthOtpSendFailure && state.flow == OtpFlow.login
                              ? state
                              : null;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
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
                                    onPressed: () => context
                                        .read<AuthBloc>()
                                        .add(LoginOtpSendRequested('+91${_controller.text}')),
                                    child: const Text('Log in'),
                                  ),
                              ],
                            ),
                            if (loginFailure != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  loginFailure.message,
                                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  )
                else
                  BlocBuilder<AuthBloc, AuthState>(
                    builder: (context, state) {
                      if (state is! AuthOtpSendFailure || state.flow != OtpFlow.registration) {
                        return const SizedBox.shrink();
                      }
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
                    // Disabled whenever *any* OTP send is in flight — not just a
                    // registration one — so a concurrent tap here can't race an
                    // in-flight login send and cross-wire the two flows' requestIds.
                    // Spinner only shown for the registration send itself; an
                    // in-flight login send already has its own spinner above.
                    final anySending = state is AuthOtpSending;
                    final registrationSending =
                        state is AuthOtpSending && state.flow == OtpFlow.registration;
                    return SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: !_isValid || anySending
                            ? null
                            : () {
                                setState(() => _userAlreadyExists = false);
                                context
                                    .read<AuthBloc>()
                                    .add(OtpSendRequested('+91${_controller.text}'));
                              },
                        child: registrationSending
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
