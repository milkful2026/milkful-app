import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../auth/data/profile_repository.dart';
import '../../auth/models/delivery_address.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../checkout/data/checkout_repository.dart';
import '../../checkout/data/pending_checkout_store.dart';
import '../../checkout/models/checkout_failure.dart';
import '../../checkout/presentation/order_success_screen.dart';
import '../../wallet/data/wallet_repository.dart';
import '../bloc/cart_bloc.dart';
import '../bloc/cart_event.dart';
import '../bloc/cart_state.dart';
import '../data/cart_repository.dart';
import '../models/frequency.dart';
import '../models/quote.dart';

/// MA-123's cart screen, turned into MA-137's **Review Cart**: line items
/// with quantity edit/removal, Add more items, the saved delivery address,
/// the Pay now / Subscriptions split, the wallet balance, and Confirm
/// Order (MA-136 checkout).
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CartBloc(
        cartRepository: context.read<CartRepository>(),
        catalogRepository: context.read<CatalogRepository>(),
        walletRepository: context.read<WalletRepository>(),
        profileRepository: context.read<ProfileRepository>(),
        checkoutRepository: context.read<CheckoutRepository>(),
        pendingCheckoutStore: context.read<PendingCheckoutStore>(),
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

  /// MA-137 FR-2/FR-5 — go somewhere that can change the cart or the
  /// wallet, then refresh on return (the route stays mounted underneath,
  /// so it would otherwise keep showing stale data).
  Future<void> _pushThenRefresh(BuildContext context, String location) async {
    final bloc = context.read<CartBloc>();
    await context.push(location);
    if (!bloc.isClosed) bloc.add(const CartRefreshRequested());
  }

  void _onCheckoutSucceeded(BuildContext context, CartState state) {
    final names = {
      for (final view in state.items)
        if (view.product != null) view.lineItem.productId: view.product!.name,
    };
    context.go(
      '/order-success',
      extra: OrderSuccessArgs(result: state.checkoutResult!, productNames: names),
    );
  }

  Future<void> _showCheckoutFailure(BuildContext context, CheckoutFailure failure) async {
    final messenger = ScaffoldMessenger.of(context);
    context.read<CartBloc>().add(const CheckoutFeedbackConsumed());
    switch (failure) {
      case InsufficientBalance(:final shortfallPaise):
        final topUp = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Not enough wallet balance'),
            content: Text(
              shortfallPaise != null
                  ? 'Add ${_rupees(shortfallPaise)} to place this order.'
                  : 'Top up your wallet to place this order.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('cart-topup-dialog-cta'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Top up'),
              ),
            ],
          ),
        );
        if ((topUp ?? false) && context.mounted) await _pushThenRefresh(context, '/wallet');
      case WalletNotActive():
        await _showInfoDialog(
          context,
          "Your wallet isn't active yet",
          'Please try again shortly.',
        );
      case AddressUnknown():
        await _showInfoDialog(
          context,
          'Add a delivery address to continue',
          'We need a delivery address on file before we can place your order.',
        );
      case CartChanged():
        messenger.showSnackBar(
          const SnackBar(content: Text('Your cart changed. Please review it and confirm again.')),
        );
      case PriceChanged():
        messenger.showSnackBar(
          const SnackBar(content: Text('Prices were updated. Please review the new total.')),
        );
      case LineInvalid():
        messenger.showSnackBar(
          const SnackBar(content: Text('Some items need attention before you can order.')),
        );
      case CheckoutInProgress():
        messenger.showSnackBar(
          const SnackBar(content: Text('An order is already being placed…')),
        );
      case Incomplete():
        // The persistent banner above Confirm Order says it; no SnackBar.
        break;
      case Unexpected(:final message):
        messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _showInfoDialog(BuildContext context, String title, String body) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: const Text('Review Cart')),
      body: BlocConsumer<CartBloc, CartState>(
        listenWhen: (previous, current) =>
            previous.pendingRemovalId != current.pendingRemovalId ||
            previous.writeErrorMessage != current.writeErrorMessage ||
            previous.items != current.items ||
            previous.checkoutFailure != current.checkoutFailure ||
            previous.checkoutResult != current.checkoutResult,
        listener: (context, state) {
          _reconcileLocalQuantities();
          if (state.checkoutResult != null) {
            _onCheckoutSucceeded(context, state);
            return;
          }
          if (state.pendingRemovalId != null && !_removalDialogOpen) {
            _confirmRemoval(context, state.pendingRemovalId!);
          }
          if (state.writeErrorMessage != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.writeErrorMessage!)));
          }
          if (state.checkoutFailure != null) {
            _showCheckoutFailure(context, state.checkoutFailure!);
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
          if (state.isEmpty) {
            return _EmptyCart(onBrowse: () => _pushThenRefresh(context, '/catalog'));
          }

          final locked = state.checkoutStatus == CheckoutStatus.submitting;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final view in state.items) ...[
                      _CartLineItemCard(
                        view: view,
                        quantity: _quantityFor(view),
                        errorReason: state.lineErrors[view.lineItem.id],
                        enabled: !locked,
                        onDecrease: () => _changeQuantity(context, view, -1),
                        onIncrease: () => _changeQuantity(context, view, 1),
                        onRemove: () => context.read<CartBloc>().add(
                          ItemRemoveRequested(lineItemId: view.lineItem.id),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('cart-add-more'),
                        onPressed: locked ? null : () => _pushThenRefresh(context, '/catalog'),
                        icon: const Icon(Icons.add),
                        label: const Text('Add more items'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _DeliveryCard(state: state),
                  ],
                ),
              ),
              _CartSummaryBar(
                state: state,
                onTopUp: () => _pushThenRefresh(context, '/wallet'),
              ),
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
  const _EmptyCart({required this.onBrowse});

  final VoidCallback onBrowse;

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
            onPressed: onBrowse,
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
    required this.enabled,
    required this.onDecrease,
    required this.onIncrease,
    required this.onRemove,
    this.errorReason,
  });

  final CartLineItemView view;
  final int quantity;
  final bool enabled;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onRemove;

  /// MA-137 FR-7 — a LINE_INVALID reason from the last Confirm.
  final String? errorReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = view.product;
    final lineItemId = view.lineItem.id;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: errorReason != null ? Border.all(color: theme.colorScheme.error) : null,
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
                  _frequencyLine(view.lineItem.frequency, view.lineItem.startDate),
                  key: Key('cart-item-frequency-$lineItemId'),
                  style: theme.textTheme.bodySmall,
                ),
                if (errorReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _lineErrorText(errorReason!),
                      key: Key('cart-item-error-$lineItemId'),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Semantics(
                      label: 'Decrease quantity',
                      child: IconButton(
                        key: Key('cart-item-quantity-decrease-$lineItemId'),
                        icon: const Icon(Icons.remove, size: 18),
                        onPressed: !enabled || quantity <= 1 ? null : onDecrease,
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
                        onPressed: enabled ? onIncrease : null,
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
              onPressed: enabled ? onRemove : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// "One Time", or "Daily · starts 27 Sep" (MA-137 screen structure).
String _frequencyLine(Frequency frequency, String? startDate) {
  final label = switch (frequency) {
    Frequency.oneTime => 'One Time',
    Frequency.daily => 'Daily',
    Frequency.alternateDays => 'Alternate Days',
  };
  if (!frequency.isSubscription) return label;
  final parsed = startDate == null ? null : DateTime.tryParse(startDate);
  return parsed == null ? label : '$label · starts ${DateFormat('d MMM').format(parsed)}';
}

String _lineErrorText(String reason) => switch (reason) {
  'SLOT_MISSING' => 'Remove and add again to choose a delivery slot',
  'START_DATE_PAST' => 'Start date has passed. Remove and add again',
  'PRODUCT_UNAVAILABLE' => 'No longer available',
  _ => "This item can't be ordered right now",
};

/// MA-137 FR-6 — the full address saved on the onboarding Google Maps /
/// Places screen, read-only, plus the one-time delivery date.
class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.state});

  final CartState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final address = state.deliveryAddress;
    return Container(
      key: const Key('cart-delivery-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('Deliver to', style: theme.textTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 6),
          if (state.addressStatus == SideLoadStatus.loading)
            Text('Loading address…', style: theme.textTheme.bodySmall)
          else if (address != null)
            _AddressLines(address: address)
          else if (state.addressStatus == SideLoadStatus.loaded)
            Text(
              'No delivery address on file',
              key: const Key('cart-delivery-missing'),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            )
          else
            Text("Couldn't load your address", style: theme.textTheme.bodySmall),
          if (state.hasOneTimeLines) ...[
            const SizedBox(height: 8),
            Text(
              'One-time items arrive ${DateFormat('EEE, d MMM').format(_estimatedDeliveryDate())}',
              key: const Key('cart-delivery-date'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _AddressLines extends StatelessWidget {
  const _AddressLines({required this.address});

  final DeliveryAddress address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          address.street,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        if (address.landmark != null && address.landmark!.trim().isNotEmpty)
          Text(address.landmark!, style: theme.textTheme.bodySmall),
        Text(address.cityStatePincode, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// MA-137 FR-6 — display only, same rule as the server's (MA-136 FR-8):
/// tomorrow if before 8 PM IST, else the day after. The Order Confirmed
/// screen always shows the server's own date.
DateTime _estimatedDeliveryDate() {
  final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  final today = DateTime(ist.year, ist.month, ist.day);
  return today.add(Duration(days: ist.hour < 20 ? 1 : 2));
}

class _CartSummaryBar extends StatelessWidget {
  const _CartSummaryBar({required this.state, required this.onTopUp});

  final CartState state;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payNow = state.effectivePayNowQuote;
    final perDelivery = state.perDeliveryQuote;
    final submitting = state.checkoutStatus == CheckoutStatus.submitting;
    final shortfall = state.shortfallPaise;

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
        child: ConstrainedBox(
          // Scrolls rather than clipping when text is scaled up.
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (payNow != null) ...[
                  _SectionHeader('Pay now'),
                  _SummaryRow('Subtotal', payNow.basePrice),
                  _SummaryRow('Tax (${_formatRate(payNow.taxRate)}%)', payNow.taxAmount),
                  _SummaryRow('Delivery Fee', payNow.deliveryFee),
                  if (payNow.discountAmount != null)
                    _SummaryRow('Discount', -payNow.discountAmount!),
                  _SummaryRow('Total', payNow.netPayable, emphasize: true),
                  const SizedBox(height: 12),
                ],
                if (perDelivery != null) ...[
                  _SectionHeader('Subscriptions'),
                  _SubscriptionsSummary(quote: perDelivery),
                  const SizedBox(height: 12),
                ],
                if (state.walletStatus == SideLoadStatus.loaded &&
                    state.walletBalancePaise != null)
                  _WalletRow(
                    balancePaise: state.walletBalancePaise!,
                    shortfallPaise: shortfall,
                    onTopUp: onTopUp,
                  ),
                if (state.checkoutStatus == CheckoutStatus.incomplete)
                  Container(
                    key: const Key('cart-checkout-incomplete'),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "We're finishing your order. Tap Confirm Order to try again.",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                Semantics(
                  button: true,
                  label: state.payNowPaise > 0
                      ? 'Confirm order, pay ${_rupees(state.payNowPaise)} now'
                      : 'Confirm order',
                  excludeSemantics: true,
                  child: FilledButton(
                    key: const Key('cart-checkout-cta'),
                    onPressed: state.canConfirm
                        ? () => context.read<CartBloc>().add(const CheckoutRequested())
                        : null,
                    child: submitting
                        ? SizedBox(
                            key: const Key('cart-checkout-progress'),
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              semanticsLabel: 'Placing order',
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                        : const Text('Confirm Order'),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// MA-137 FR-4 — what each subscription delivery costs; nothing is charged
/// for it at Confirm Order.
class _SubscriptionsSummary extends StatelessWidget {
  const _SubscriptionsSummary({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '₹${quote.netPayable.toStringAsFixed(2)} per delivery · charged from wallet',
          key: const Key('cart-per-delivery'),
          style: theme.textTheme.bodyMedium,
        ),
        if (quote.monthlyEstimate != null)
          Text(
            '≈ ₹${quote.monthlyEstimate!.toStringAsFixed(0)}/month',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

/// MA-137 FR-5 — balance, plus an advisory shortfall hint and Top up.
/// Confirm stays enabled either way; the server decides.
class _WalletRow extends StatelessWidget {
  const _WalletRow({
    required this.balancePaise,
    required this.shortfallPaise,
    required this.onTopUp,
  });

  final int balancePaise;
  final int? shortfallPaise;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final short = shortfallPaise != null && shortfallPaise! > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Wallet balance ${_rupees(balancePaise)}',
                  key: const Key('cart-wallet-balance'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (short)
                TextButton(
                  key: const Key('cart-wallet-topup'),
                  onPressed: onTopUp,
                  child: const Text('Top up'),
                ),
            ],
          ),
          if (short)
            Text(
              'Add ${_rupees(shortfallPaise!)} to confirm this order',
              key: const Key('cart-wallet-shortfall'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
        ],
      ),
    );
  }
}

String _rupees(int paise) => '₹${(paise / 100).toStringAsFixed(2)}';

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
