import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/money.dart';
import '../../../catalog/models/product.dart';
import '../../domain/order_buckets.dart';
import '../../domain/order_status_copy.dart';
import '../../models/order_entry.dart';
import '../../models/order_summary.dart';
import '../order_formatting.dart';
import 'product_thumb.dart';
import 'status_chip.dart';

/// MA-145 FR-9 — one card per delivery date: header with the date and the
/// day's total, then one row per entry on that date.
class DayGroupCard extends StatelessWidget {
  const DayGroupCard({
    super.key,
    required this.group,
    required this.today,
    required this.products,
    required this.upcoming,
  });

  final DayGroup group;
  final DateTime today;
  final Map<String, Product?> products;
  final bool upcoming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = dayTotal(group.entries, products);
    return Container(
      key: Key('orders.group.${_isoDate(group.date)}'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatGroupDate(group.date, today, upcoming: upcoming),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${total.hasEstimate ? '≈ ' : ''}${formatPaise(total.paise)} Total',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final entry in group.entries) EntryRow(entry: entry, products: products),
        ],
      ),
    );
  }
}

class EntryRow extends StatelessWidget {
  const EntryRow({super.key, required this.entry, required this.products});

  final OrderEntry entry;
  final Map<String, Product?> products;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final productIds = switch (entry) {
      OrderedEntry(:final order) => [for (final i in order.items) i.productId],
      ScheduledEntry(:final productId) => [productId],
    };
    final chip = switch (entry) {
      OrderedEntry(:final order) =>
        order.status == OrderStatus.confirmed ? null : statusChip(order.status),
      ScheduledEntry() => scheduledChip,
    };
    final (key, location, extra) = switch (entry) {
      OrderedEntry(:final order) => (
        Key('orders.row.${order.orderId}'),
        '/orders/${order.orderId}',
        null,
      ),
      ScheduledEntry(:final subscriptionId) => (
        Key('orders.row.scheduled.$subscriptionId'),
        '/orders/scheduled/$subscriptionId',
        entry,
      ),
    };
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push(location, extra: extra),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              _Thumbs(productIds: productIds, products: products),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _summary(productIds, products, scheduled: entry is ScheduledEntry),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    ..._amountLine(context),
                    if (chip != null) ...[const SizedBox(height: 4), StatusChip(chip)],
                  ],
                ),
              ),
              Semantics(
                label: 'Open order',
                button: true,
                excludeSemantics: true,
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.chevron_right, color: theme.colorScheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _amountLine(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    switch (entry) {
      case OrderedEntry(:final order):
        final text = formatPaise(order.amountPaise);
        return [
          Text(
            text,
            style: isAmountStruck(order)
                ? style?.copyWith(decoration: TextDecoration.lineThrough)
                : style,
          ),
        ];
      case final ScheduledEntry scheduled:
        final estimate = estimatePaise(scheduled, products[scheduled.productId]);
        return [
          Text(
            estimate == null
                ? 'Price confirmed the evening before'
                : '≈ ${formatPaise(estimate)} est.',
            style: style,
          ),
        ];
    }
  }
}

String _summary(List<String> ids, Map<String, Product?> products, {required bool scheduled}) {
  final names = ids.map((id) => productNameFor(products, id)).toList();
  final base = switch (names.length) {
    0 => 'Order',
    1 => names[0],
    2 => '${names[0]}, ${names[1]}',
    _ => '${names[0]}, ${names[1]} & more',
  };
  return scheduled ? '$base (Subscription)' : base;
}

class _Thumbs extends StatelessWidget {
  const _Thumbs({required this.productIds, required this.products});

  final List<String> productIds;
  final Map<String, Product?> products;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = productIds.take(2).toList();
    final extra = productIds.length - shown.length;
    const size = 40.0;
    final count = shown.length + (extra > 0 ? 1 : 0);
    return SizedBox(
      width: count == 0 ? size : size + (count - 1) * 26,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 26,
              child: ProductThumb(product: products[shown[i]], size: size, circle: true),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * 26,
              child: CircleAvatar(
                radius: size / 2,
                backgroundColor: theme.colorScheme.primary,
                child: Text(
                  '+$extra',
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onPrimary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
