import 'package:flutter/material.dart';

import '../../../../core/utils/money.dart';
import '../../../catalog/models/product.dart';
import '../../domain/order_status_copy.dart';
import '../../models/order_summary.dart';
import 'open_order_detail.dart';
import 'product_thumb.dart';
import 'status_chip.dart';

/// MA-145 FR-5 — one card per item of every order delivered today. The
/// amount is shown once per order (Order Service stores no per-item
/// price): on the card for a single-item order, on an "Order total" header
/// above a multi-item order's cards.
class TodaySection extends StatelessWidget {
  const TodaySection({
    super.key,
    required this.orders,
    required this.products,
    required this.ordersFailed,
    this.ordersLoading = false,
  });

  final List<OrderSummary> orders;
  final Map<String, Product?> products;

  /// The orders source failed: show "Couldn't load…", never the empty text.
  final bool ordersFailed;

  /// The orders source is being (re)loaded, e.g. after Retry: show a
  /// spinner, never the empty text.
  final bool ordersLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemCount = orders.fold<int>(0, (n, o) => n + o.items.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Today's Delivery",
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!ordersFailed && !ordersLoading && itemCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    itemCount == 1 ? '1 Item' : '$itemCount Items',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
            ),
            child: ordersLoading
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : ordersFailed
                ? const _SectionMessage("Couldn't load today's deliveries.")
                : orders.isEmpty
                ? const _SectionMessage('No deliveries today')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final order in orders) ..._orderCards(context, order)],
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _orderCards(BuildContext context, OrderSummary order) {
    final multi = order.items.length > 1;
    final struck = isAmountStruck(order);
    return [
      if (multi)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: _Amount(
            'Order total ${formatPaise(order.amountPaise)}',
            struck: struck,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      for (var i = 0; i < order.items.length; i++)
        _TodayItemCard(
          key: Key('orders.today.card.${order.orderId}.$i'),
          order: order,
          item: order.items[i],
          products: products,
          amount: multi ? null : formatPaise(order.amountPaise),
          struck: struck,
        ),
    ];
  }
}

class _TodayItemCard extends StatelessWidget {
  const _TodayItemCard({
    super.key,
    required this.order,
    required this.item,
    required this.products,
    required this.amount,
    required this.struck,
  });

  final OrderSummary order;
  final OrderItem item;
  final Map<String, Product?> products;
  final String? amount;
  final bool struck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = products[item.productId];
    final unit = product?.unit;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => openOrderDetail(context, '/orders/${order.orderId}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProductThumb(product: product, size: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productNameFor(products, item.productId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        unit == null
                            ? 'Quantity: ${item.quantity}'
                            : '$unit • Quantity: ${item.quantity}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      StatusChip(statusChip(order.status)),
                    ],
                  ),
                ),
                if (amount != null)
                  _Amount(
                    amount!,
                    struck: struck,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
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

class _Amount extends StatelessWidget {
  const _Amount(this.text, {required this.struck, this.style});

  final String text;
  final bool struck;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: struck ? style?.copyWith(decoration: TextDecoration.lineThrough) : style,
  );
}

class _SectionMessage extends StatelessWidget {
  const _SectionMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
  );
}
