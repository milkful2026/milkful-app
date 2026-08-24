import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../auth/data/profile_repository.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/models/product.dart';
import '../bloc/product_config_bloc.dart';
import '../bloc/product_config_event.dart';
import '../bloc/product_config_state.dart';
import '../data/cart_repository.dart';
import '../data/pricing_repository.dart';
import '../data/wallet_balance_repository.dart';
import '../models/frequency.dart';

/// MA-120 §7 — the documented fallback cap used whenever
/// `product.availableQuantity` is `null` (Catalog Service hasn't added the
/// field yet, see catalog_repository.dart), rather than being unbounded.
const _fallbackQuantityCap = 20;

class ProductConfigScreen extends StatelessWidget {
  const ProductConfigScreen({required this.product, super.key});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ProductConfigBloc(
        product: product,
        catalogRepository: context.read<CatalogRepository>(),
        pricingRepository: context.read<PricingRepository>(),
        cartRepository: context.read<CartRepository>(),
        walletBalanceRepository: context.read<WalletBalanceRepository>(),
        profileRepository: context.read<ProfileRepository>(),
      )..add(ProductConfigStarted(product)),
      child: const _ProductConfigView(),
    );
  }
}

class _ProductConfigView extends StatefulWidget {
  const _ProductConfigView();

  @override
  State<_ProductConfigView> createState() => _ProductConfigViewState();
}

class _ProductConfigViewState extends State<_ProductConfigView> {
  // Instant local feedback for the quantity number, decoupled from the
  // debounced bloc dispatch below — same split as catalog_page.dart's
  // search field (its own TextEditingController shows typed text
  // instantly; the bloc event that triggers a network call is debounced).
  late int _quantity;
  Timer? _quantityDebounce;

  @override
  void initState() {
    super.initState();
    _quantity = context.read<ProductConfigBloc>().state.quantity;
  }

  @override
  void dispose() {
    _quantityDebounce?.cancel();
    super.dispose();
  }

  int _maxQuantity(Product product) =>
      product.availableQuantity ?? _fallbackQuantityCap;

  void _changeQuantity(int delta, Product product) {
    final next = (_quantity + delta).clamp(1, _maxQuantity(product));
    if (next == _quantity) return;
    setState(() => _quantity = next);
    _quantityDebounce?.cancel();
    _quantityDebounce = Timer(const Duration(milliseconds: 300), () {
      context.read<ProductConfigBloc>().add(QuantityChanged(_quantity));
    });
  }

  Future<void> _pickStartDate(BuildContext context) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (selected != null && context.mounted) {
      context.read<ProductConfigBloc>().add(StartDateChanged(selected));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        actions: const [
          // Present per mockup, not yet wired — no share/favourite backend
          // exists yet, matching home_screen.dart's own established
          // "present per mockup, not yet wired" treatment.
          IconButton(icon: Icon(Icons.share_outlined), onPressed: null),
          IconButton(icon: Icon(Icons.favorite_border), onPressed: null),
        ],
      ),
      body: BlocConsumer<ProductConfigBloc, ProductConfigState>(
        listenWhen: (previous, current) =>
            previous.addStatus != current.addStatus,
        listener: (context, state) {
          if (state.addStatus == AddStatus.success) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Added to cart')));
            context.pop();
          }
        },
        builder: (context, state) {
          final product = state.product;
          final outOfStock = product.stockState == StockState.outOfStock;
          final availableFrom = product.stockState == StockState.availableFrom;
          final maxQuantity = _maxQuantity(product);

          return Column(
            // Default CrossAxisAlignment.center gives every child unbounded
            // width and shrinks it to its own intrinsic size instead — for
            // _BottomBar, whose Row contains an Expanded, that collapses
            // the whole bar to a near-zero width (each Text inside wraps
            // one character per line). .stretch makes both children (the
            // scroll view and the bottom bar) span the full Scaffold width.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ProductBanner(product: product),
                      const SizedBox(height: 16),
                      if (product.tag != null) ...[
                        _TagPill(label: product.tag!),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        product.name,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      if (outOfStock || availableFrom)
                        _StockBanner(
                          message: outOfStock
                              ? 'Currently out of stock'
                              : 'Available from ${DateFormat('MMM d').format(product.availableFrom!)}',
                        ),
                      if (product.subscriptionEligible) ...[
                        Text(
                          'Subscription Plan',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        _FrequencySelector(
                          selected: state.frequency,
                          disabled: outOfStock || availableFrom,
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (state.frequency.isSubscription) ...[
                        Text(
                          'Select Start Date',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        _StartDatePicker(
                          date: state.startDate,
                          onTap: (outOfStock || availableFrom)
                              ? null
                              : () => _pickStartDate(context),
                        ),
                        const SizedBox(height: 20),
                      ],
                      _QuantityStepper(
                        quantity: _quantity,
                        maxQuantity: maxQuantity,
                        disabled: outOfStock || availableFrom,
                        onDecrease: () => _changeQuantity(-1, product),
                        onIncrease: () => _changeQuantity(1, product),
                      ),
                      if (state.frequency.isSubscription &&
                          state.walletCheckStatus ==
                              WalletCheckStatus.insufficient)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            'A minimum wallet balance of ₹500 is required for subscriptions — '
                            'your balance is ₹${state.walletBalance}.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (state.frequency.isSubscription &&
                          state.walletCheckStatus == WalletCheckStatus.failed)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            state.walletErrorMessage ?? "Couldn't check your wallet balance — pull to retry",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _BottomBar(state: state),
            ],
          );
        },
      ),
    );
  }
}

class _ProductBanner extends StatelessWidget {
  const _ProductBanner({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: product.imageUrl != null
            ? Image.network(
                product.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
              )
            : Container(color: Theme.of(context).colorScheme.primaryContainer),
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: primary, letterSpacing: 0.5),
      ),
    );
  }
}

class _StockBanner extends StatelessWidget {
  const _StockBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('stock-banner'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _FrequencySelector extends StatelessWidget {
  const _FrequencySelector({required this.selected, required this.disabled});

  final Frequency selected;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _frequencyCard(
          context,
          Frequency.daily,
          'Daily',
          'Every morning delivery',
          Icons.today_outlined,
          'frequency-daily',
        ),
        const SizedBox(height: 10),
        _frequencyCard(
          context,
          Frequency.alternateDays,
          'Alternate Days',
          'Tue, Thu, Sat, Sun',
          Icons.event_repeat_outlined,
          'frequency-alternate',
        ),
        const SizedBox(height: 10),
        _frequencyCard(
          context,
          Frequency.oneTime,
          'One Time',
          'Pick your own days',
          Icons.edit_calendar_outlined,
          'frequency-one-time',
        ),
      ],
    );
  }

  Widget _frequencyCard(
    BuildContext context,
    Frequency value,
    String label,
    String subtitle,
    IconData icon,
    String keyName,
  ) {
    final isSelected = selected == value;
    final theme = Theme.of(context);
    return InkWell(
      key: Key(keyName),
      onTap: disabled
          ? null
          : () =>
                context.read<ProductConfigBloc>().add(FrequencyChanged(value)),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.06)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(subtitle, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _StartDatePicker extends StatelessWidget {
  const _StartDatePicker({required this.date, required this.onTap});

  final DateTime? date;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('start-date-calendar'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        key: const Key('start-date-selected'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 18),
            const SizedBox(width: 8),
            Text(
              date == null
                  ? 'Choose a start date'
                  : DateFormat('MMM d, yyyy').format(date!),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.maxQuantity,
    required this.disabled,
    required this.onDecrease,
    required this.onIncrease,
  });

  final int quantity;
  final int maxQuantity;
  final bool disabled;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final atMax = quantity >= maxQuantity;
    final nearMax = maxQuantity - quantity <= 5;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quantity per delivery',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Recommended for family of 2',
                  style: theme.textTheme.bodySmall,
                ),
                if (!disabled && nearMax)
                  Text(
                    'Only $maxQuantity left',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Semantics(
                  label: 'Decrease quantity',
                  child: IconButton(
                    key: const Key('quantity-stepper-decrease'),
                    icon: const Icon(Icons.remove),
                    color: theme.colorScheme.primary,
                    onPressed: (disabled || quantity <= 1) ? null : onDecrease,
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '$quantity',
                    key: const Key('quantity-stepper-value'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Semantics(
                  label: 'Increase quantity',
                  child: IconButton(
                    key: const Key('quantity-stepper-increase'),
                    icon: const Icon(Icons.add),
                    color: theme.colorScheme.primary,
                    onPressed: (disabled || atMax) ? null : onIncrease,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.state});

  final ProductConfigState state;

  @override
  Widget build(BuildContext context) {
    final outOfStock = state.product.stockState == StockState.outOfStock;
    final availableFrom = state.product.stockState == StockState.availableFrom;
    final stockBlocked = outOfStock || availableFrom;

    final canConfirm = state.canConfirm && !stockBlocked;
    final isSubscribing = state.frequency.isSubscription;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _PriceEstimate(state: state, isSubscribing: isSubscribing),
            ),
            const SizedBox(width: 16),
            FilledButton(
              // The app-wide FilledButton theme sets minimumSize to
              // Size.fromHeight(48) — infinite width, min height 48 — for
              // the full-width buttons used everywhere else in this app
              // (always wrapped in `SizedBox(width: double.infinity, ...)`
              // there). This button is a compact pill next to the price,
              // not full-width, so it needs its own bounded minimumSize —
              // without this override, an infinite-width constraint
              // propagates into a Row that doesn't bound it, which crashes
              // layout (BoxConstraints forces an infinite width).
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: canConfirm
                  ? () => context.read<ProductConfigBloc>().add(
                      const AddToCartRequested(),
                    )
                  : null,
              child: state.addStatus == AddStatus.loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(isSubscribing ? 'Subscribe Now' : 'Add to Cart'),
                        if (isSubscribing) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward, size: 18),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceEstimate extends StatelessWidget {
  const _PriceEstimate({required this.state, required this.isSubscribing});

  final ProductConfigState state;
  final bool isSubscribing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = Text(
      'Estimated Total',
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    switch (state.quoteStatus) {
      case QuoteStatus.idle:
      case QuoteStatus.loading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label,
            const SizedBox(
              height: 24,
              width: 80,
              child: LinearProgressIndicator(),
            ),
          ],
        );
      case QuoteStatus.failed:
        return Text(
          state.quoteErrorMessage ?? 'Price unavailable — pull to retry',
          style: TextStyle(color: theme.colorScheme.error),
        );
      case QuoteStatus.loaded:
        final quote = state.quote!;
        final amount = isSubscribing
            ? (quote.monthlyEstimate ?? quote.netPayable)
            : quote.netPayable;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label,
            RichText(
              text: TextSpan(
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
                children: [
                  TextSpan(text: '₹${amount.toStringAsFixed(0)}'),
                  if (isSubscribing)
                    TextSpan(
                      text: ' / month',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
    }
  }
}
