import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';
import '../../catalog/bloc/catalog_bloc.dart';
import '../../catalog/presentation/catalog_screen.dart';

/// MA-1's spec explicitly puts a real Home (catalog, cart, subscriptions)
/// out of scope; MA-21 adds only the role-aware indicator (FR-4) and a
/// minimal logout entry point (FR-5) on top of the placeholder MA-1 left
/// here. Logout placement (an AppBar action) is provisional per the
/// spec's own note that a full Account/Settings screen doesn't exist yet.
///
/// MA-115 replaces the body below with the real catalog — this screen still
/// owns the AppBar/logout chrome; search/filter/sort icons live inside
/// [CatalogScreen] itself (MA-115 FR-5/6/7), not here.
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
        title: const Text('Freshoza'),
        actions: [
          IconButton(
            key: const Key('logout-action'),
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      body: Column(
        children: [
          BlocBuilder<AuthBloc, AuthState>(
            builder: (context, state) {
              final accountType = state is AuthAuthenticated ? state.accountType : null;
              if (accountType != 'B2B') return const SizedBox.shrink();
              return const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Chip(label: Text('B2B account')),
              );
            },
          ),
          Expanded(
            // CatalogRepository itself is provided app-wide from main.dart
            // (alongside PlacesRepository) — only the bloc is scoped here,
            // since its loading/search/filter state shouldn't outlive this
            // screen the way the repository/HTTP client should.
            child: BlocProvider(
              create: (context) => CatalogBloc(repository: context.read()),
              child: const CatalogScreen(),
            ),
          ),
        ],
      ),
    );
  }
}
