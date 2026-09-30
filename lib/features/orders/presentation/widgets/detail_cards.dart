import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../catalog/models/product.dart';
import '../../domain/order_status_copy.dart';
import 'product_thumb.dart';
import 'status_chip.dart';

/// MA-146 — the `order_details_inr` cards, filled only with data that
/// exists today. Shared by the order and scheduled-delivery screens.
class DetailCard extends StatelessWidget {
  const DetailCard({super.key, this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(title!, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

/// Header: an ID column (or a label), a placed-on column, the status banner
/// and optional explanatory text under it.
class DetailHeaderCard extends StatelessWidget {
  const DetailHeaderCard({
    super.key,
    required this.banner,
    this.orderId,
    this.label,
    this.placedOn,
    this.note,
  });

  /// Full order id (copied on long-press); null for a scheduled delivery.
  final String? orderId;

  /// Shown instead of ORDER ID (e.g. "SCHEDULED DELIVERY").
  final String? label;
  final String? placedOn;
  final StatusChipSpec banner;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = toneColors(context, banner.tone);
    final icon = chipIconData(banner.icon);
    final small = theme.textTheme.labelSmall?.copyWith(letterSpacing: 0.8);
    return DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: orderId != null
                    ? GestureDetector(
                        key: const Key('orderDetail.orderId'),
                        // The whole ID area, not just the glyphs, takes the press.
                        behavior: HitTestBehavior.opaque,
                        onLongPress: () async {
                          await Clipboard.setData(ClipboardData(text: orderId!));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Order ID copied')),
                            );
                          }
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ORDER ID', style: small),
                            Text(displayOrderId(orderId!), style: theme.textTheme.titleLarge),
                          ],
                        ),
                      )
                    : Text(label ?? '', style: small),
              ),
              if (placedOn != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Placed On', style: small),
                    Text(placedOn!, style: theme.textTheme.titleSmall),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Semantics(
            key: const Key('orderDetail.statusBanner'),
            label: 'Status: ${banner.label}${note == null ? '' : '. $note'}',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: colors.foreground),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    banner.label,
                    style: theme.textTheme.titleSmall?.copyWith(color: colors.foreground),
                  ),
                ],
              ),
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 10),
            ExcludeSemantics(child: Text(note!, style: theme.textTheme.bodyMedium)),
          ],
        ],
      ),
    );
  }
}

class DetailItemRow extends StatelessWidget {
  const DetailItemRow({
    super.key,
    required this.name,
    required this.quantity,
    required this.product,
    this.fromSubscription = false,
  });

  final String name;
  final int quantity;
  final Product? product;
  final bool fromSubscription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = product?.unit;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          ProductThumb(product: product, size: 56, circle: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.titleSmall),
                if (fromSubscription)
                  Text('From your subscription', style: theme.textTheme.bodySmall),
                Text(
                  unit == null ? 'Quantity: $quantity' : '$quantity × $unit',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Grand Total / Estimated Total row with an optional caption.
class BillRow extends StatelessWidget {
  const BillRow({
    super.key,
    required this.label,
    required this.amount,
    this.struck = false,
    this.caption,
  });

  final String label;
  final String amount;
  final bool struck;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleLarge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: style)),
            Text(
              amount,
              key: const Key('orderDetail.grandTotal'),
              style: struck ? style?.copyWith(decoration: TextDecoration.lineThrough) : style,
            ),
          ],
        ),
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(caption!, textAlign: TextAlign.end, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

class IconLine extends StatelessWidget {
  const IconLine({super.key, required this.icon, required this.title, this.value});

  final IconData icon;
  final String title;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              if (value != null) Text(value!, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full-screen message with one button (not found / gone / error).
class DetailMessage extends StatelessWidget {
  const DetailMessage({
    super.key,
    required this.title,
    this.body,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String? body;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(body!, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
        ],
      ),
    ),
  );
}
