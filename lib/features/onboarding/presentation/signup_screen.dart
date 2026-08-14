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
  String _mobile = '';

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
          if (state is AuthOtpSent) {
            context.go('/otp', extra: state.mobile);
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
                    onChanged: (value) => setState(() => _mobile = value),
                  ),
                ),
                const SizedBox(height: 16),
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    if (state is AuthUserAlreadyExists) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          children: [
                            const Expanded(child: Text('Already registered?')),
                            TextButton(
                              onPressed: () {
                                // MA-21's /login route doesn't exist yet in
                                // this PR — see plan's scope note. Wired to
                                // a no-op for now rather than a dead route.
                              },
                              child: const Text('Log in'),
                            ),
                          ],
                        ),
                      );
                    }
                    if (state is AuthOtpSendFailure) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          state.message,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    final sending = state is AuthOtpSending;
                    return SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: !_isValid || sending
                            ? null
                            : () => context
                                .read<AuthBloc>()
                                .add(OtpSendRequested('+91$_mobile')),
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
