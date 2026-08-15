import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_state.dart';

/// Minimal placeholder entry point — NOT the full branded 3-slide carousel
/// from MA-XXX-welcome-screen-story.md (that needs real hero images/icons
/// and a confirmed design-system color token this pass doesn't have).
/// Exists only so the sign-up flow has somewhere to start from.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
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
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Milkful', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Farm-fresh milk and groceries delivered to your doorstep.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => context.go('/signup'),
                      child: const Text('Get Started'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
