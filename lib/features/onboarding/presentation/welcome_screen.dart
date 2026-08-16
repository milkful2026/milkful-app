import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';

/// Entry point (`/` and `/signup` both resolve here — see app_router.dart's
/// own comment on why `/signup` still exists as a route). Combines what used
/// to be two screens (a placeholder Welcome + a separate SignupScreen) into
/// one, matching the reference mockup's single branded card with an inline
/// mobile-number field, per the layout decision made for this restyle.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
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
          child: BlocBuilder<AuthBloc, AuthState>(
            builder: (context, state) {
              // MA-21 FR-3: while a stored session is being checked/silently
              // refreshed at app start, show a loading state here instead of
              // the real Welcome content — the router's redirect takes over
              // and moves to /home the moment bootstrap resolves to
              // AuthAuthenticated, so this is only ever visible briefly.
              if (state is AuthBootstrapping) {
                return const Center(child: CircularProgressIndicator());
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                      ),
                      child: Icon(Icons.eco, size: 36, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Freshoza',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your local harvest, delivered fresh to your door.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 32),
                    Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Get Started',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Enter your mobile number to login or join the community.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            Text('Mobile Number', style: Theme.of(context).textTheme.labelMedium),
                            const SizedBox(height: 4),
                            Semantics(
                              label: 'Mobile number',
                              child: TextField(
                                key: const Key('mobile-number-field'),
                                controller: _controller,
                                keyboardType: TextInputType.phone,
                                maxLength: 10,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: const InputDecoration(
                                  prefixText: '+91  ',
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
                            const SizedBox(height: 8),
                            if (_userAlreadyExists)
                              BlocBuilder<AuthBloc, AuthState>(
                                builder: (context, state) {
                                  final loggingIn =
                                      state is AuthOtpSending && state.flow == OtpFlow.login;
                                  final loginFailure =
                                      state is AuthOtpSendFailure && state.flow == OtpFlow.login
                                          ? state
                                          : null;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
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
                                                onPressed: () => context.read<AuthBloc>().add(
                                                      LoginOtpSendRequested(
                                                        '+91${_controller.text}',
                                                      ),
                                                    ),
                                                child: const Text('Log in'),
                                              ),
                                          ],
                                        ),
                                        if (loginFailure != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              loginFailure.message,
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.error,
                                              ),
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
                                  if (state is! AuthOtpSendFailure ||
                                      state.flow != OtpFlow.registration) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      state.message,
                                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                                    ),
                                  );
                                },
                              ),
                            const SizedBox(height: 8),
                            BlocBuilder<AuthBloc, AuthState>(
                              builder: (context, state) {
                                // Disabled whenever *any* OTP send is in flight — not
                                // just a registration one — so a concurrent tap here
                                // can't race an in-flight login send and cross-wire
                                // the two flows' requestIds. Spinner only shown for
                                // the registration send itself; an in-flight login
                                // send already has its own spinner above.
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
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text('Continue'),
                                              SizedBox(width: 8),
                                              Icon(Icons.arrow_forward, size: 18),
                                            ],
                                          ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "By continuing, you agree to our Terms & Conditions and Privacy Policy.",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
