import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../catalog/data/catalog_repository.dart';
import '../bloc/subscription_bloc.dart';
import '../bloc/subscription_event.dart';
import '../bloc/subscription_state.dart';
import '../data/subscription_repository.dart';
import '../models/subscription_status.dart';
import '../models/subscription_view.dart';
import 'subscription_detail_sheet.dart';

final _dateFormat = DateFormat('MMM d');

/// MA-25/MA-133's My Subscriptions screen — the bottom-nav **Schedule**
/// destination. Built against the MA-25 ticket mock
/// (`image-20260807-175447.png`).
class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SubscriptionBloc(
        repository: context.read<SubscriptionRepository>(),
        catalogRepository: context.read<CatalogRepository>(),
      )..add(const SubscriptionsStarted()),
      child: const _SubscriptionsView(),
    );
  }
}

class _SubscriptionsView extends StatelessWidget {
  const _SubscriptionsView();

  Future<void> _openDetailSheet(BuildContext context, SubscriptionView subscription) {
    final bloc = context.read<SubscriptionBloc>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => BlocProvider.value(
        value: bloc,
        child: SubscriptionDetailSheet(subscription: subscription),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<SubscriptionBloc, SubscriptionsState>(
          listenWhen: (previous, current) =>
              previous.lastActionMessage != current.lastActionMessage &&
              current.lastActionMessage != null,
          listener: (context, state) {
            final message = state.lastActionMessage!;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(message.message),
                  backgroundColor: message.isError
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              );
          },
          builder: (context, state) {
            return Column(
              children: [
                const _SubscriptionsAppBarRow(),
                Expanded(child: _SubscriptionsBody(state: state, onOpenDetail: _openDetailSheet)),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: const _SubscriptionsBottomNav(),
    );
  }
}

class _SubscriptionsAppBarRow extends StatelessWidget {
  const _SubscriptionsAppBarRow();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.menu),
          const Spacer(),
          Text('Freshoza', style: TextStyle(fontWeight: FontWeight.bold, color: primary)),
          const Spacer(),
          const SizedBox(width: 24),
        ],
      ),
    );
  }
}

class _SubscriptionsBody extends StatelessWidget {
  const _SubscriptionsBody({required this.state, required this.onOpenDetail});

  final SubscriptionsState state;
  final Future<void> Function(BuildContext, SubscriptionView) onOpenDetail;

  @override
  Widget build(BuildContext context) {
    switch (state.loadStatus) {
      case SubscriptionsLoadStatus.idle:
      case SubscriptionsLoadStatus.loading:
        return const _LoadingSkeleton();
      case SubscriptionsLoadStatus.failed:
        return _LoadError(
          message: state.loadErrorMessage,
          onRetry: () => context.read<SubscriptionBloc>().add(const SubscriptionsStarted()),
        );
      case SubscriptionsLoadStatus.loaded:
        return RefreshIndicator(
          onRefresh: () async =>
              context.read<SubscriptionBloc>().add(const SubscriptionsRefreshRequested()),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                'My Subscriptions',
                key: const Key('subscriptions-title'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage your fresh recurring essentials.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              _VacationModeRow(
                on: state.vacationModeOn,
                onToggle: (on) => context.read<SubscriptionBloc>().add(VacationModeToggled(on)),
              ),
              const SizedBox(height: 24),
              _ActiveSubscriptionsHeader(count: state.subscriptions.length),
              const SizedBox(height: 12),
              if (state.subscriptions.isEmpty)
                const _EmptyState()
              else
                for (final subscription in state.subscriptions) ...[
                  _SubscriptionCard(
                    subscription: subscription,
                    onTap: () => onOpenDetail(context, subscription),
                  ),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 12),
              _NewProductPromo(onSubscribe: () => context.push('/catalog')),
            ],
          ),
        );
    }
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListView(
      key: const Key('subscriptions-loading-skeleton'),
      padding: const EdgeInsets.all(16),
      children: [
        Container(height: 60, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(16))),
        const SizedBox(height: 16),
        for (var i = 0; i < 2; i++) ...[
          Container(height: 110, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(16))),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('subscriptions-load-error'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 40),
            const SizedBox(height: 12),
            Text(
              message ?? "Couldn't load your subscriptions",
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            FilledButton(key: const Key('subscriptions-load-retry'), onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _VacationModeRow extends StatelessWidget {
  const _VacationModeRow({required this.on, required this.onToggle});

  final bool on;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Text('🏖', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vacation Mode', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                Text('Pause all deliveries', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Semantics(
            label: on ? 'Vacation Mode on' : 'Vacation Mode off',
            child: Switch(
              key: const Key('subscriptions-vacation-toggle'),
              value: on,
              onChanged: onToggle,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveSubscriptionsHeader extends StatelessWidget {
  const _ActiveSubscriptionsHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Active Subscriptions', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        Container(
          key: const Key('subscriptions-active-count'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count Active',
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('subscriptions-empty-state'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          const Text('No active subscriptions yet'),
        ],
      ),
    );
  }
}

Color _statusColor(BuildContext context, SubscriptionStatus status) {
  final theme = Theme.of(context);
  return switch (status) {
    SubscriptionStatus.active => Colors.green,
    SubscriptionStatus.paused => Colors.orange,
    SubscriptionStatus.stopped => theme.colorScheme.outline,
  };
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.subscription, required this.onTap});

  final SubscriptionView subscription;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(context, subscription.status);
    return InkWell(
      key: Key('subscription-card-${subscription.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12)],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 56,
                height: 56,
                color: theme.colorScheme.primaryContainer,
                child: const Icon(Icons.local_drink_outlined),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subscription.productName ?? subscription.productId,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          subscription.status.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Quantity: ${subscription.quantity} Unit', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 2),
                  Text(subscription.schedule.label(), style: theme.textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Text(
                    _nextDeliveryLabel(subscription),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _nextDeliveryLabel(SubscriptionView subscription) {
    if (subscription.status == SubscriptionStatus.stopped) return 'Stopped';
    if (subscription.status == SubscriptionStatus.paused) return 'Paused';
    final date = subscription.nextDeliveryDate;
    if (date == null) return 'No upcoming delivery';
    final today = DateTime.now();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final target = DateTime(date.year, date.month, date.day);
    if (target == tomorrow) return 'Next delivery: Tomorrow';
    return 'Next delivery: ${_dateFormat.format(date)}';
  }
}

class _NewProductPromo extends StatelessWidget {
  const _NewProductPromo({required this.onSubscribe});

  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Never run out of essentials',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Subscribe to our farm-fresh eggs, paneer, and more.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                key: const Key('subscriptions-new-product-cta'),
                onPressed: onSubscribe,
                icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                label: const Text('Subscribe to New Product'),
              ),
              const SizedBox(width: 12),
              TextButton(
                key: const Key('subscriptions-custom-schedule-cta'),
                // FR-7 — reaches WEEKLY/CUSTOM_DAYS schedules, which
                // ProductConfigScreen's own frequency selector (FR-6)
                // deliberately doesn't cover. Not yet wired to a
                // dedicated flow (see this PR's own description).
                onPressed: null,
                child: const Text('Custom schedule'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mirrors `home_screen.dart`'s `_HomeBottomNav`/`wallet_screen.dart`'s
/// `_WalletBottomNav` (same items, same visual language) with **Schedule**
/// as the active tab.
class _SubscriptionsBottomNav extends StatelessWidget {
  const _SubscriptionsBottomNav();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return BottomNavigationBar(
      currentIndex: 1,
      selectedItemColor: primary,
      unselectedItemColor: Colors.grey.shade400,
      onTap: (index) {
        if (index == 0) context.go('/home');
        if (index == 2) context.go('/wallet');
        // 3 (Profile) remains a stub, same as Home's nav.
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Schedule'),
        BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Wallet'),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
      ],
    );
  }
}
