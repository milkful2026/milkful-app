import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/ist_clock.dart';
import '../../../core/utils/money.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/models/product.dart';
import '../../subscriptions/data/subscription_repository.dart';
import '../bloc/scheduled_delivery_cubit.dart';
import '../data/order_repository.dart';
import '../domain/cancel_copy.dart';
import '../domain/order_buckets.dart';
import '../domain/order_status_copy.dart';
import '../models/order_entry.dart';
import 'order_formatting.dart';
import 'widgets/detail_cards.dart';

/// MA-146 FR-8 — `/orders/scheduled/:subscriptionId`: a subscription's next
/// delivery, not yet an order, with Cancel delivery (MA-155 FR-5). [entry]
/// comes from My Orders as `extra`; without it (deep link, restart) the cubit
/// fetches the subscription.
class ScheduledDeliveryScreen extends StatelessWidget {
  const ScheduledDeliveryScreen({
    super.key,
    required this.subscriptionId,
    this.entry,
    this.clock,
  });

  final String subscriptionId;
  final ScheduledEntry? entry;
  final Clock? clock;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ScheduledDeliveryCubit(
        subscriptionRepository: context.read<SubscriptionRepository>(),
        orderRepository: context.read<OrderRepository>(),
        catalogRepository: context.read<CatalogRepository>(),
        subscriptionId: subscriptionId,
        initial: entry,
        clock: clock,
      )..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Order Details'), centerTitle: true),
        body: BlocConsumer<ScheduledDeliveryCubit, ScheduledDeliveryState>(
          listenWhen: (previous, current) =>
              current is ScheduledDeliveryLoaded && current.change is! NoChange && !current.quiet,
          listener: (context, state) {
            final change = (state as ScheduledDeliveryLoaded).change;
            final messenger = ScaffoldMessenger.of(context);
            messenger.hideCurrentSnackBar();
            switch (change) {
              case BecameOrder(:final orderId):
                messenger.showSnackBar(
                  SnackBar(
                    content: const Text('This delivery is now an order.'),
                    action: SnackBarAction(
                      label: 'View order',
                      onPressed: () => _viewOrder(context, GoRouter.of(context), orderId),
                    ),
                  ),
                );
              case DateChanged():
                messenger.showSnackBar(
                  const SnackBar(content: Text('Your next delivery has changed.')),
                );
              case NoChange():
                break;
            }
          },
          builder: (context, state) => switch (state) {
            ScheduledDeliveryLoading() => const Center(child: CircularProgressIndicator()),
            ScheduledDeliveryGone() => DetailMessage(
              title: 'This delivery is no longer scheduled.',
              buttonLabel: 'Back to My Orders',
              onPressed: () => backToMyOrders(context),
            ),
            ScheduledDeliveryError() => DetailMessage(
              title: "Couldn't load this delivery.",
              buttonLabel: 'Retry',
              onPressed: () => context.read<ScheduledDeliveryCubit>().load(),
            ),
            ScheduledDeliveryLoaded(:final entry, :final product) => RefreshIndicator(
              onRefresh: () => context.read<ScheduledDeliveryCubit>().refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                children: [
                  const DetailHeaderCard(
                    label: 'SCHEDULED DELIVERY',
                    banner: scheduledChip,
                    note:
                        "This is your subscription's next delivery. It becomes an order "
                        'the evening before, when your wallet is charged.',
                  ),
                  DetailCard(
                    title: 'Items in this Order',
                    child: DetailItemRow(
                      name: product?.name ?? 'Item',
                      quantity: entry.quantity,
                      product: product,
                      fromSubscription: true,
                    ),
                  ),
                  DetailCard(
                    title: 'Bill Details',
                    child: _estimate(entry, product),
                  ),
                  DetailCard(
                    title: 'Delivery Info',
                    child: IconLine(
                      icon: Icons.schedule,
                      title: 'Delivery date',
                      value: formatLongDate(entry.date),
                    ),
                  ),
                  const DetailCard(
                    title: 'Payment Method',
                    child: IconLine(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Milkful Wallet',
                    ),
                  ),
                  _CancelDeliverySection(
                    date: entry.date,
                    now: (clock ?? DateTime.now)(),
                    onCancel: () => _cancelDelivery(context, entry, product),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () => context.go('/subscriptions'),
                      child: const Text('Manage subscription'),
                    ),
                  ),
                ],
              ),
            ),
          },
        ),
      ),
    );
  }

  /// MA-155 FR-5 — confirm, then cancel through Skip. Success closes the
  /// screen and tells My Orders to reload. When Skip says CUTOFF_PASSED, the
  /// cubit has refreshed quietly (no "now an order" notice); this SnackBar
  /// gives the specific reason, with View order if it became an order.
  Future<void> _cancelDelivery(BuildContext context, ScheduledEntry entry, Product? product) async {
    final cubit = context.read<ScheduledDeliveryCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('cancelDelivery.dialog'),
        title: const Text('Cancel this delivery?'),
        content: Text(cancelDeliveryBody(product?.name ?? 'Item', entry.date)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep delivery'),
          ),
          TextButton(
            key: const Key('cancelDelivery.confirm'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel delivery'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final outcome = await cubit.cancelDelivery();
    if (outcome == null) return;

    final state = cubit.state;
    final viewOrder = switch (state) {
      ScheduledDeliveryLoaded(change: BecameOrder(:final orderId)) => SnackBarAction(
        label: 'View order',
        onPressed: () => _viewOrder(context, router, orderId),
      ),
      _ => null,
    };
    messenger.hideCurrentSnackBar();
    switch (outcome) {
      case SkipOutcome.cancelled:
        messenger.showSnackBar(
          SnackBar(
            content: Text(deliveryCancelledMessage(entry.date)),
            action: SnackBarAction(
              label: shopForTomorrowLabel,
              onPressed: () => router.go('/catalog'),
            ),
          ),
        );
        if (router.canPop()) {
          router.pop(true);
        } else {
          router.go('/orders');
        }
      case SkipOutcome.cutoffPassed:
        messenger.showSnackBar(
          SnackBar(content: const Text(deliveryCutoffPassedMessage), action: viewOrder),
        );
      case SkipOutcome.alreadyOrder:
        messenger.showSnackBar(
          SnackBar(content: const Text(deliveryAlreadyOrderMessage), action: viewOrder),
        );
      case SkipOutcome.failed:
        messenger.showSnackBar(const SnackBar(content: Text(cancelFailedMessage)));
    }
  }

  Widget _estimate(ScheduledEntry entry, Product? product) {
    final estimate = estimatePaise(entry, product);
    if (estimate == null) {
      return const BillRow(
        label: 'Estimated Total',
        amount: '',
        caption: 'Price confirmed the evening before',
      );
    }
    return BillRow(
      label: 'Estimated Total',
      amount: '≈ ${formatPaise(estimate, alwaysDecimals: true)}',
      caption:
          'Final price (including any tax and delivery fee) is confirmed the evening before.',
    );
  }
}

/// View order, for a delivery that became an order. Not `pushReplacement`:
/// go_router drops the replaced route without completing its future, so My
/// Orders' `openOrderDetail` would never hear about a cancel made on the
/// order. Instead push the order, and once it closes, close this screen with
/// `true`: the delivery is an order now, so My Orders reloads either way.
Future<void> _viewOrder(BuildContext context, GoRouter router, String orderId) async {
  await router.push<bool>('/orders/$orderId');
  // Left some other way (e.g. Shop for tomorrow): nothing to close.
  if (!context.mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
  if (router.canPop()) {
    router.pop(true);
  } else {
    router.go('/orders');
  }
}

/// MA-155 FR-5/FR-6 — before the cut-off (worked out on the device: the
/// subscription has no `cancellableUntil`, and Subscription Service rejects a
/// late skip anyway), the policy line and Cancel delivery; after it, the
/// closed line.
class _CancelDeliverySection extends StatelessWidget {
  const _CancelDeliverySection({required this.date, required this.now, required this.onCancel});

  final DateTime date;
  final DateTime now;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    if (!now.isBefore(deliveryCutoff(date))) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(cancellationClosedLine, style: muted, textAlign: TextAlign.center),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(deliveryPolicyLine(date), style: muted, textAlign: TextAlign.center),
          TextButton(
            key: const Key('scheduled.cancel'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: onCancel,
            child: const Text('Cancel delivery'),
          ),
        ],
      ),
    );
  }
}
