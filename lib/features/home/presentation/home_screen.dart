import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';

/// MA-1's spec explicitly puts a real Home (catalog, cart, subscriptions)
/// out of scope; MA-21 adds only the role-aware indicator (FR-4) and a
/// minimal logout entry point (FR-5) on top of the placeholder MA-1 left
/// here. Logout placement (an AppBar action) is provisional per the
/// spec's own note that a full Account/Settings screen doesn't exist yet.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text("You'll need to verify your number again to sign back in."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<AuthBloc>().add(const LogoutRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Milkful'),
        actions: [
          IconButton(
            key: const Key('logout-action'),
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      body: Center(
        child: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            final accountType = state is AuthAuthenticated ? state.accountType : null;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("You're signed in."),
                if (accountType == 'B2B') ...[
                  const SizedBox(height: 8),
                  const Chip(label: Text('B2B account')),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
