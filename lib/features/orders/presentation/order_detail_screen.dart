import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/money.dart';
import '../../cart/data/cart_repository.dart';
import '../../catalog/data/catalog_repository.dart';
import '../bloc/order_detail_cubit.dart';
import '../data/order_repository.dart';
import '../domain/order_status_copy.dart';
import '../models/order_summary.dart';
import 'order_formatting.dart';
import 'widgets/detail_cards.dart';
import 'widgets/product_thumb.dart';

/// MA-146 — `/orders/:orderId`: the subset of `order_details_inr` that real
/// data backs today, plus Reorder and Support (MA-152). No invoice or
/// feedback (MA-38 / MA-28).
class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  /// A failed refresh keeps the order on screen and says so.
  Future<void> _refresh(BuildContext context) async {
    final cubit = context.read<OrderDetailCubit>();
    final ok = await cubit.refresh();
    if (!ok && cubit.state is OrderDetailLoaded && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't refresh. Try again.")),
      );
    }
  }

  /// MA-152 FR-1 — the result SnackBar, with "View Cart" if anything landed.
  Future<void> _reorder(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final result = await context.read<OrderDetailCubit>().reorder();
    if (result == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.message),
        action: result.showViewCart
            ? SnackBarAction(label: 'View Cart', onPressed: () => router.push('/cart'))
            : null,
      ),
    );
  }

  /// MA-152 FR-2 — the mail app, with the display ID (no `#`, never the full
  /// order ID) in the subject.
  Future<void> _openSupport(BuildContext context, String orderId) async {
    final messenger = ScaffoldMessenger.of(context);
    final subject = 'Order ${displayOrderId(orderId).substring(1)}';
    // Built by hand so a space is `%20`: Uri.queryParameters would use `+`,
    // which some mail apps show literally.
    final uri = Uri(
      scheme: 'mailto',
      path: AppConfig.supportEmail,
      query: 'subject=${Uri.encodeComponent(subject)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No email app found. Contact us at ${AppConfig.supportEmail}.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => OrderDetailCubit(
        orderRepository: context.read<OrderRepository>(),
        catalogRepository: context.read<CatalogRepository>(),
        cartRepository: context.read<CartRepository>(),
        orderId: orderId,
      )..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Order Details'), centerTitle: true),
        body: BlocBuilder<OrderDetailCubit, OrderDetailState>(
          builder: (context, state) => switch (state) {
            OrderDetailLoading() => const _DetailSkeleton(),
            OrderDetailNotFound() => DetailMessage(
              title: 'Order not found',
              body: "This order doesn't exist or isn't on your account.",
              buttonLabel: 'Back to My Orders',
              onPressed: () => backToMyOrders(context),
            ),
            OrderDetailError() => DetailMessage(
              title: "Couldn't load this order.",
              buttonLabel: 'Retry',
              onPressed: () => context.read<OrderDetailCubit>().load(),
            ),
            OrderDetailLoaded(:final order, :final products, :final reordering) => RefreshIndicator(
              onRefresh: () => _refresh(context),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                children: [
                  DetailHeaderCard(
                    orderId: order.orderId,
                    placedOn: order.createdAt == null ? null : formatPlacedOn(order.createdAt!),
                    banner: bannerSpec(order.status),
                    note: showsReason(order.status) ? reasonText(order.failureReason) : null,
                  ),
                  DetailCard(
                    title: 'Items in this Order',
                    child: Column(
                      children: [
                        for (var i = 0; i < order.items.length; i++)
                          DetailItemRow(
                            key: Key('orderDetail.item.$i'),
                            name: productNameFor(products, order.items[i].productId),
                            quantity: order.items[i].quantity,
                            product: products[order.items[i].productId],
                            fromSubscription: order.source == OrderSource.subscription,
                          ),
                      ],
                    ),
                  ),
                  DetailCard(
                    title: 'Bill Details',
                    child: BillRow(
                      label: 'Grand Total',
                      // A pre-pricing failure (MA-132) has no real amount.
                      amount: order.amountPaise == 0
                          ? '—'
                          : formatPaise(order.amountPaise, alwaysDecimals: true),
                      struck: order.amountPaise != 0 && isAmountStruck(order),
                      caption: order.amountPaise == 0 ? null : billCaption(order),
                    ),
                  ),
                  DetailCard(
                    title: 'Delivery Info',
                    child: IconLine(
                      icon: Icons.schedule,
                      title: 'Delivery date',
                      value: formatLongDate(order.deliveryDate),
                    ),
                  ),
                  const DetailCard(
                    title: 'Payment Method',
                    child: IconLine(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Milkful Wallet',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The spinner replaces the label, so a screen reader
                        // still hears the button's name while it's busy.
                        Semantics(
                          button: true,
                          enabled: !reordering,
                          label: 'Reorder Items',
                          excludeSemantics: reordering,
                          child: FilledButton(
                            key: const Key('orderDetail.reorder'),
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                            onPressed: reordering ? null : () => _reorder(context),
                            child: reordering
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Reorder Items'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          key: const Key('orderDetail.support'),
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          onPressed: () => _openSupport(context, order.orderId),
                          child: const Text('Support'),
                        ),
                      ],
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
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHigh;
    Widget block(double h) => Container(
      height: h,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(28)),
    );
    return Semantics(
      label: 'Loading order',
      child: ListView(
        padding: const EdgeInsets.only(top: 8),
        children: [block(150), block(160)],
      ),
    );
  }
}
