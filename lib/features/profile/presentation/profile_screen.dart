import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/profile_repository.dart';
import '../bloc/profile_header_cubit.dart';
import 'mobile_format.dart';

/// MA-147 — `/profile`, a bottom-bar tab (like `/subscriptions` and
/// `/wallet`). The minimal subset of mock `my_profile`: a name/mobile
/// header and the rows that work today (My Subscription, My Orders,
/// Transactions). Refer & Earn, Offer Zone and Account & Preferences come
/// with their own stories.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          ProfileHeaderCubit(context.read<ProfileRepository>())..load(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          automaticallyImplyLeading: false,
        ),
        bottomNavigationBar: const _ProfileBottomNav(),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const _Header(),
            const SizedBox(height: 16),
            _SubscriptionHeroRow(onTap: () => context.go('/subscriptions')),
            const SizedBox(height: 12),
            _ProfileRow(
              key: const Key('profile.row.orders'),
              icon: Icons.inventory_2_outlined,
              label: 'My Orders',
              onTap: () => context.push('/orders'),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('FINANCIALS'),
            const SizedBox(height: 8),
            _ProfileRow(
              key: const Key('profile.row.transactions'),
              icon: Icons.receipt_long_outlined,
              label: 'Transactions',
              onTap: () => context.push('/wallet/transactions'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('profile.header'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: BlocBuilder<ProfileHeaderCubit, ProfileHeaderState>(
        builder: (context, state) => switch (state) {
          ProfileHeaderLoading() => const _HeaderContent(
            name: null,
            mobile: null,
          ),
          ProfileHeaderError() => Row(
            children: [
              const Expanded(child: Text("Couldn't load your profile")),
              TextButton(
                onPressed: () => context.read<ProfileHeaderCubit>().load(),
                child: const Text('Retry'),
              ),
            ],
          ),
          ProfileHeaderLoaded(:final profile) => _HeaderContent(
            name: profile.name.trim().isEmpty
                ? 'Milkful customer'
                : profile.name.trim(),
            initials: initialsOf(profile.name),
            mobile: formatIndianMobile(profile.mobile),
            loaded: true,
          ),
        },
      ),
    );
  }
}

class _HeaderContent extends StatelessWidget {
  const _HeaderContent({
    required this.name,
    required this.mobile,
    this.initials = '',
    this.loaded = false,
  });

  final String? name;
  final String? mobile;
  final String initials;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget placeholder(double width) => Container(
      width: width,
      height: 14,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
    );
    return Semantics(
      label: loaded
          ? [name, mobile].whereType<String>().join(', ')
          : 'Loading profile',
      excludeSemantics: true,
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: initials.isEmpty
                ? const Icon(Icons.person_outline, size: 32)
                : Text(initials, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (loaded)
                  Text(name!, style: theme.textTheme.titleLarge)
                else
                  placeholder(140),
                if (loaded && mobile != null)
                  Text(mobile!, style: theme.textTheme.bodyLarge)
                else if (!loaded)
                  placeholder(110),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionHeroRow extends StatelessWidget {
  const _SubscriptionHeroRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = theme.colorScheme.onPrimary;
    return Material(
      key: const Key('profile.row.subscription'),
      color: theme.colorScheme.primary,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(Icons.autorenew, color: on),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'My Subscription',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: on,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: on.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Manage',
                        style: theme.textTheme.labelLarge?.copyWith(color: on),
                      ),
                      Icon(Icons.chevron_right, size: 18, color: on),
                    ],
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

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(icon, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(label, style: theme.textTheme.titleMedium),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(letterSpacing: 1.2),
    ),
  );
}

class _ProfileBottomNav extends StatelessWidget {
  const _ProfileBottomNav();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return BottomNavigationBar(
      currentIndex: 3,
      selectedItemColor: primary,
      unselectedItemColor: Colors.grey.shade400,
      onTap: (index) {
        if (index == 0) context.go('/home');
        if (index == 1) context.go('/subscriptions');
        if (index == 2) context.go('/wallet');
        // 3 (Profile) is the current tab — a no-op.
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
        BottomNavigationBarItem(
          icon: Icon(Icons.calendar_today_outlined),
          label: 'Schedule',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.account_balance_wallet_outlined),
          label: 'Wallet',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
      ],
    );
  }
}
