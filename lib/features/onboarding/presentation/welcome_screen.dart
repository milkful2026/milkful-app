import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
        child: Padding(
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
        ),
      ),
    );
  }
}
