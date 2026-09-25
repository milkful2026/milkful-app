import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/checkout_result.dart';

/// What the Review Cart screen hands to `/order-success` via `extra:` —
/// the checkout result plus the product names it already resolved, so
/// this screen makes no Catalog calls of its own (MA-137 FR-10).
class OrderSuccessArgs {
  const OrderSuccessArgs({required this.result, required this.productNames});

  final CheckoutResult result;
  final Map<String, String> productNames; // productId -> name
}

/// MA-137 FR-10 — reached with `go`, so Back can't return to the cart that
/// was just checked out.
class OrderSuccessScreen extends StatelessWidget {
  const OrderSuccessScreen({super.key, required this.args});

  final OrderSuccessArgs args;

  String _name(String productId) => args.productNames[productId] ?? 'Item';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = args.result;
    final order = result.order;
    final created = result.createdSubscriptions;
    final failed = result.failedSubscriptions;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          children: [
            Icon(Icons.check_circle, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                'Order confirmed!',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 24),
            if (order != null) ...[
              _InfoRow(
                label: 'Order ID',
                child: SelectableText(
                  order.orderId,
                  key: const Key('order-success-id'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              _InfoRow(
                label: 'Arriving',
                child: Text(_formatDate(order.deliveryDate), style: theme.textTheme.bodyMedium),
              ),
              _InfoRow(
                label: 'Paid from wallet',
                child: Text(_rupees(order.amountPaise), style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(height: 16),
            ],
            if (created.isNotEmpty) ...[
              Text('Subscriptions started', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final sub in created)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    sub.nextDeliveryDate != null
                        ? '${_name(sub.productId)} · starts ${_formatDate(sub.nextDeliveryDate!)}'
                        : _name(sub.productId),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              const SizedBox(height: 16),
            ],
            for (final sub in failed)
              Container(
                key: Key('order-success-failed-${sub.lineId}'),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "${_name(sub.productId)} couldn't be subscribed. It's still in your cart.",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (result.walletBalanceAfterPaise != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Wallet balance ${_rupees(result.walletBalanceAfterPaise!)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 32),
            FilledButton(
              key: const Key('order-success-home'),
              onPressed: () => context.go('/home'),
              child: const Text('Back to Home'),
            ),
            if (created.isNotEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('order-success-subscriptions'),
                onPressed: () => context.go('/subscriptions'),
                child: const Text('View subscriptions'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 16),
          Flexible(child: child),
        ],
      ),
    );
  }
}

String _rupees(int paise) => '₹${(paise / 100).toStringAsFixed(2)}';

/// `yyyy-MM-dd` -> "Fri, 26 Sep".
String _formatDate(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  return parsed == null ? isoDate : DateFormat('EEE, d MMM').format(parsed);
}
