import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../catalog/data/catalog_repository.dart';
import '../bloc/cart_bloc.dart';
import '../bloc/cart_event.dart';
import '../bloc/cart_state.dart';
import '../data/cart_repository.dart';

/// MA-123's cart review screen — line items, quantity edit, removal, and
/// the live server-computed price breakdown.
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CartBloc(
        cartRepository: context.read<CartRepository>(),
        catalogRepository: context.read<CatalogRepository>(),
      )..add(const CartStarted()),
      child: const _CartView(),
    );
  }
}

class _CartView extends StatefulWidget {
  const _CartView();

  @override
  State<_CartView> createState() => _CartViewState();
}

class _CartViewState extends State<_CartView> {
  // Instant local feedback per line item, decoupled from the debounced
  // bloc dispatch below — same split as ProductConfigScreen's own quantity
  // stepper (product_config_screen.dart) and catalog_page.dart's search
  // field.
  final Map<String, int> _localQuantities = {};
  final Map<String, Timer> _debounceTimers = {};
  bool _removalDialogOpen = false;

  @override
  void dispose() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  int _quantityFor(CartLineItemView view) => _localQuantities[view.lineItem.id] ?? view.lineItem.quantity;

  void _changeQuantity(BuildContext context, CartLineItemView view, int delta) {
    final lineItemId = view.lineItem.id;
    final next = (_quantityFor(view) + delta).clamp(1, 99);
    if (next == _quantityFor(view)) return;
    // Resolve the bloc now, not inside the delayed closure — by the time
    // the timer fires this row's element may have been scrolled off and
    // deactivated, making its `context` unsafe to look up a provider from.
    final bloc = context.read<CartBloc>();
    setState(() => _localQuantities[lineItemId] = next);
    _debounceTimers[lineItemId]?.cancel();
    _debounceTimers[lineItemId] = Timer(const Duration(milliseconds: 500), () {
      _debounceTimers.remove(lineItemId);
      bloc.add(QuantityWriteRequested(lineItemId: lineItemId, quantity: next));
    });
  }

  /// Drops the instant-feedback override for any row whose debounced write
  /// has already been dispatched, so the row falls back to bloc state as
  /// the source of truth. Without this, a write that fails (and reverts in
  /// the bloc) or that the server adjusts would leave the stepper stuck on
  /// the user's last-typed number, diverging from the real cart.
  void _reconcileLocalQuantities() {
    final settled = _localQuantities.keys
        .where((id) => !_debounceTimers.containsKey(id))
        .toList();
    if (settled.isEmpty) return;
    setState(() => settled.forEach(_localQuantities.remove));
  }

  Future<void> _confirmRemoval(BuildContext context, String lineItemId) async {
    _removalDialogOpen = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Remove item'),
          content: const Text('Remove this item from your cart?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      if (confirmed ?? false) {
        context.read<CartBloc>().add(ItemRemoveConfirmed(lineItemId: lineItemId));
      } else {
        context.read<CartBloc>().add(const ItemRemoveCancelled());
      }
    } finally {
      _removalDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: const Text('Your Cart')),
      body: BlocConsumer<CartBloc, CartState>(
        listenWhen: (previous, current) =>
            previous.pendingRemovalId != current.pendingRemovalId ||
            previous.writeErrorMessage != current.writeErrorMessage ||
            previous.items != current.items,
        listener: (context, state) {
          _reconcileLocalQuantities();
          if (state.pendingRemovalId != null && !_removalDialogOpen) {
            _confirmRemoval(context, state.pendingRemovalId!);
          }
          if (state.writeErrorMessage != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.writeErrorMessage!)));
          }
        },
        builder: (context, state) {
          if (state.loadStatus == CartLoadStatus.loading) {
            return const _CartLoadingSkeleton();
          }
          if (state.loadStatus == CartLoadStatus.failed) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.loadErrorMessage ?? 'Something went wrong'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => context.read<CartBloc>().add(const CartStarted()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          if (state.isEmpty) return const _EmptyCart();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.items.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final view = state.items[index];
                    return _CartLineItemCard(
                      view: view,
                      quantity: _quantityFor(view),
                      onDecrease: () => _changeQuantity(context, view, -1),
                      onIncrease: () => _changeQuantity(context, view, 1),
                      onRemove: () =>
                          context.read<CartBloc>().add(ItemRemoveRequested(lineItemId: view.lineItem.id)),
                    );
                  },
                ),
              ),
              _CartSummaryBar(state: state),
            ],
          );
        },
      ),
    );
  }
}

/// List-shaped placeholder rows while `getCart` + per-item `getProduct`
/// are in flight (MA-123 FR-2), matching `catalog_screen.dart`'s
/// `_LoadingSkeleton` treatment.
class _CartLoadingSkeleton extends StatelessWidget {
  const _CartLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      itemBuilder: (context, index) => Container(
        height: 88,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('cart-empty-state'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_basket_outlined,
            size: 64,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text('Your cart is empty', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('cart-browse-products-cta'),
            onPressed: () => context.push('/catalog'),
            child: const Text('Browse Products'),
          ),
        ],
      ),
    );
  }
}

class _CartLineItemCard extends StatelessWidget {
  const _CartLineItemCard({
    required this.view,
    required this.quantity,
    required this.onDecrease,
    required this.onIncrease,
    required this.onRemove,
  });

  final CartLineItemView view;
  final int quantity;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = view.product;
    final lineItemId = view.lineItem.id;
    final frequency = view.lineItem.frequency;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 56,
              height: 56,
              child: product?.imageUrl != null
                  ? Image.network(
                      product!.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Container(color: theme.colorScheme.primaryContainer),
                    )
                  : Container(color: theme.colorScheme.primaryContainer),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product?.name ?? 'Product unavailable',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  frequency.isSubscription
                      ? '${frequency.wireValue.replaceAll('_', ' ')} · ${view.lineItem.startDate ?? ''}'
                      : 'One Time',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Semantics(
                      label: 'Decrease quantity',
                      child: IconButton(
                        key: Key('cart-item-quantity-decrease-$lineItemId'),
                        icon: const Icon(Icons.remove, size: 18),
                        onPressed: quantity <= 1 ? null : onDecrease,
                      ),
                    ),
                    SizedBox(
                      width: 24,
                      child: Text(
                        '$quantity',
                        key: Key('cart-item-quantity-value-$lineItemId'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Semantics(
                      label: 'Increase quantity',
                      child: IconButton(
                        key: Key('cart-item-quantity-increase-$lineItemId'),
                        icon: const Icon(Icons.add, size: 18),
                        onPressed: onIncrease,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Semantics(
            label: 'Remove item',
            child: IconButton(
              key: Key('cart-item-remove-$lineItemId'),
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartSummaryBar extends StatelessWidget {
  const _CartSummaryBar({required this.state});

  final CartState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quote = state.quote;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(color: theme.shadowColor.withValues(alpha: 0.08), blurRadius: 12),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (quote != null) ...[
              _SummaryRow('Subtotal', quote.basePrice),
              _SummaryRow('Tax (${_formatRate(quote.taxRate)}%)', quote.taxAmount),
              _SummaryRow('Delivery Fee', quote.deliveryFee),
              if (quote.discountAmount != null) _SummaryRow('Discount', -quote.discountAmount!),
              _SummaryRow('Total', quote.netPayable, emphasize: true),
              if (quote.monthlyEstimate != null)
                Text(
                  '≈ ₹${quote.monthlyEstimate!.toStringAsFixed(0)}/month',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              key: const Key('cart-checkout-cta'),
              onPressed: null,
              child: const Text('Proceed to Checkout — coming soon'),
            ),
          ],
        ),
      ),
    );
  }
}

/// `taxRate` is always a `double`; render integral rates as "5%", not
/// "5.0%", while keeping real fractions ("12.5%").
String _formatRate(double rate) =>
    rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toString();

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.amount, {this.emphasize = false});

  final String label;
  final double amount;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasize
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(
            amount < 0
                ? '-₹${(-amount).toStringAsFixed(2)}'
                : '₹${amount.toStringAsFixed(2)}',
            style: style,
          ),
        ],
      ),
    );
  }
}
