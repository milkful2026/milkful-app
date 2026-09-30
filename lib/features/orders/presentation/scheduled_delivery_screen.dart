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
import '../domain/order_buckets.dart';
import '../domain/order_status_copy.dart';
import '../models/order_entry.dart';
import 'order_formatting.dart';
import 'widgets/detail_cards.dart';

/// MA-146 FR-8 — `/orders/scheduled/:subscriptionId`: a subscription's next
/// delivery, not yet an order. [entry] comes from My Orders as `extra`;
/// without it (deep link, restart) the cubit fetches the subscription.
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
              current is ScheduledDeliveryLoaded && current.change is! NoChange,
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
                      onPressed: () => context.pushReplacement('/orders/$orderId'),
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
              onPressed: () => context.pop(),
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
