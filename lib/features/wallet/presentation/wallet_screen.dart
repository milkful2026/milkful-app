import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../onboarding/bloc/registration_bloc.dart';
import '../../onboarding/bloc/registration_state.dart';
import '../bloc/wallet_bloc.dart';
import '../bloc/wallet_event.dart';
import '../bloc/wallet_state.dart';
import '../data/pending_recharge_store.dart';
import '../data/razorpay_checkout.dart';
import '../data/wallet_repository.dart';
import '../models/payment_method.dart';
import '../models/wallet_status.dart';
import '../models/wallet_view.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

String _formatPaise(int paise) => _currencyFormat.format(paise / 100);

/// MA-24/MA-125's Wallet & Recharge screen — the bottom-nav **Wallet**
/// destination. Built against the MA-24 ticket mock (`image-20260806-
/// 182611.png`): balance card, Quick Top Up chips, a custom-amount sheet,
/// a UPI/Card method choice, and a Razorpay-backed "Proceed to Payment".
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // All four collaborators come from context.read — same convention
      // as ProductConfigBloc's five — so a widget test can substitute
      // Fakes for `RazorpayCheckout`/the two stores via RepositoryProvider
      // the same way it already does for `WalletRepository`, without this
      // screen needing a test-only constructor parameter. The wrapper is
      // owned by the bloc, not this widget — `WalletBloc.close()` already
      // disposes it.
      create: (context) => WalletBloc(
        walletRepository: context.read<WalletRepository>(),
        razorpayCheckout: context.read<RazorpayCheckout>(),
        pendingRechargeStore: context.read<PendingRechargeStore>(),
        paymentMethodStore: context.read<PaymentMethodStore>(),
      )..add(const WalletStarted()),
      child: const _WalletView(),
    );
  }
}

class _WalletView extends StatefulWidget {
  const _WalletView();

  @override
  State<_WalletView> createState() => _WalletViewState();
}

class _WalletViewState extends State<_WalletView> {
  Future<void> _openTopUpSheet(BuildContext context, WalletState state) async {
    final wallet = state.wallet;
    if (wallet == null) return;
    final amountPaise = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _TopUpAmountSheet(
        minPaise: wallet.rechargeMinPaise,
        maxPaise: wallet.rechargeMaxPaise,
      ),
    );
    if (amountPaise != null && context.mounted) {
      context.read<WalletBloc>().add(CustomAmountEntered(amountPaise));
    }
  }

  Future<void> _confirmAbandon(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start over?'),
        content: const Text(
          "We're still checking on your last top-up. Starting over won't affect it — "
          "if it went through, it'll still be credited.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep waiting'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Start over'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<WalletBloc>().add(const PendingRechargeAbandoned());
    }
  }

  void _showSuccessSheet(BuildContext context, int? amountPaise) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => _SuccessSheet(amountPaise: amountPaise),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<WalletBloc, WalletState>(
          listenWhen: (previous, current) => previous.rechargeStatus != current.rechargeStatus,
          listener: (context, state) {
            if (state.rechargeStatus == RechargeStatus.success) {
              _showSuccessSheet(context, state.lastConfirmedAmountPaise);
            }
          },
          builder: (context, state) {
            return Column(
              children: [
                const _WalletAppBarRow(),
                Expanded(
                  child: _WalletBody(
                    state: state,
                    onOpenTopUpSheet: _openTopUpSheet,
                    onAbandonRequested: () => _confirmAbandon(context),
                  ),
                ),
                if (!kIsWeb) _ProceedButtonBar(state: state) else const _WebUnsupportedBar(),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: const _WalletBottomNav(),
    );
  }
}

/// A local, minimal stand-in for Home's `_LandingHeader` row (that widget
/// is private to `home_screen.dart` and not worth extracting for one
/// reuse) — same location + notification-bell language, no logout action
/// (out of scope for this screen).
class _WalletAppBarRow extends StatelessWidget {
  const _WalletAppBarRow();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.location_on, color: primary),
          const SizedBox(width: 4),
          Expanded(
            child: BlocBuilder<RegistrationBloc, RegistrationState>(
              builder: (context, state) {
                final city = state.draft.address?.city;
                return Text(
                  city == null || city.isEmpty ? 'Mumbai, India' : city,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
          ),
          Text('Milkful', style: TextStyle(fontWeight: FontWeight.bold, color: primary)),
          IconButton(
            key: const Key('wallet-notification-action'),
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notifications',
            onPressed: null,
          ),
        ],
      ),
    );
  }
}

class _WalletBody extends StatelessWidget {
  const _WalletBody({
    required this.state,
    required this.onOpenTopUpSheet,
    required this.onAbandonRequested,
  });

  final WalletState state;
  final Future<void> Function(BuildContext, WalletState) onOpenTopUpSheet;
  final VoidCallback onAbandonRequested;

  @override
  Widget build(BuildContext context) {
    switch (state.walletLoadStatus) {
      case WalletLoadStatus.idle:
      case WalletLoadStatus.loading:
        return const _WalletLoadingSkeleton();
      case WalletLoadStatus.failed:
        return _WalletLoadError(
          message: state.walletErrorMessage,
          onRetry: () => context.read<WalletBloc>().add(const WalletRefreshRequested()),
        );
      case WalletLoadStatus.loaded:
        final wallet = state.wallet!;
        final controlsEnabled = state.pendingRecharge == null;
        return RefreshIndicator(
          onRefresh: () async => context.read<WalletBloc>().add(const WalletRefreshRequested()),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _BalanceCard(
                wallet: wallet,
                provisionRetryStatus: state.provisionRetryStatus,
                onTopUp: controlsEnabled ? () => onOpenTopUpSheet(context, state) : null,
                onPassbook: () => context.push('/wallet/transactions'),
                onRetrySetup: () => context.read<WalletBloc>().add(const WalletProvisionRetryRequested()),
              ),
              const SizedBox(height: 8),
              _ViewAllTransactionsLink(onTap: () => context.push('/wallet/transactions')),
              if (state.showPendingBanner)
                _PendingBanner(isStale: state.isPendingStale, onStartOver: onAbandonRequested),
              if (state.rechargeStatus == RechargeStatus.failed)
                _ErrorCard(
                  message: state.rechargeErrorMessage ?? 'The payment could not be completed',
                  canRetry: state.canRetryRecharge,
                  onRetry: () => context.read<WalletBloc>().add(const RechargeRequested()),
                ),
              const SizedBox(height: 20),
              _QuickTopUp(
                selectedAmountPaise: state.selectedAmountPaise,
                enabled: wallet.status == WalletStatus.active && controlsEnabled,
                minPaise: wallet.rechargeMinPaise,
                maxPaise: wallet.rechargeMaxPaise,
                onSelect: (amount) => context.read<WalletBloc>().add(QuickAmountSelected(amount)),
              ),
              const SizedBox(height: 20),
              _PaymentMethods(
                selected: state.selectedMethod,
                enabled: wallet.status == WalletStatus.active && controlsEnabled,
                onSelect: (method) => context.read<WalletBloc>().add(PaymentMethodSelected(method)),
              ),
            ],
          ),
        );
    }
  }
}

class _WalletLoadingSkeleton extends StatelessWidget {
  const _WalletLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListView(
      key: const Key('wallet-loading-skeleton'),
      padding: const EdgeInsets.all(16),
      children: [
        Container(height: 180, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(20))),
        const SizedBox(height: 20),
        Row(
          children: List.generate(
            3,
            (i) => Expanded(
              child: Container(
                height: 56,
                margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WalletLoadError extends StatelessWidget {
  const _WalletLoadError({this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('wallet-load-error'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 40),
            const SizedBox(height: 12),
            Text(
              message ?? "Couldn't load your wallet",
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            FilledButton(key: const Key('wallet-load-retry'), onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.wallet,
    required this.provisionRetryStatus,
    required this.onTopUp,
    required this.onPassbook,
    required this.onRetrySetup,
  });

  final WalletView wallet;
  final ProvisionRetryStatus provisionRetryStatus;
  final VoidCallback? onTopUp;
  final VoidCallback onPassbook;
  final VoidCallback onRetrySetup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notActive = wallet.status != WalletStatus.active;
    return Container(
      key: const Key('wallet-balance-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Available Balance', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          if (notActive)
            Text(
              wallet.status == WalletStatus.failed ? 'Wallet setup failed' : 'Wallet setup in progress',
              key: const Key('wallet-not-provisioned'),
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            )
          else
            Semantics(
              label: 'Available balance, ${(wallet.balancePaise / 100).toStringAsFixed(2)} rupees',
              child: ExcludeSemantics(
                child: Text(
                  key: const Key('wallet-balance-amount'),
                  _formatPaise(wallet.balancePaise),
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (wallet.status == WalletStatus.failed)
                FilledButton.tonal(
                  key: const Key('wallet-retry-setup'),
                  onPressed: provisionRetryStatus == ProvisionRetryStatus.loading ? null : onRetrySetup,
                  child: provisionRetryStatus == ProvisionRetryStatus.loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Retry setup'),
                )
              else
                FilledButton.icon(
                  key: const Key('wallet-topup-button'),
                  onPressed: onTopUp,
                  icon: const Icon(Icons.add),
                  label: const Text('Top Up'),
                ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                key: const Key('wallet-passbook-button'),
                onPressed: onPassbook,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Passbook'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ViewAllTransactionsLink extends StatelessWidget {
  const _ViewAllTransactionsLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        key: const Key('wallet-view-all-transactions'),
        onPressed: onTap,
        icon: const Icon(Icons.history, size: 18),
        label: const Text('View All Transactions'),
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.isStale, required this.onStartOver});

  final bool isStale;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('wallet-recharge-pending'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isStale
                  ? "We'll update your balance shortly"
                  : 'Payment received — updating your balance…',
            ),
          ),
          if (isStale)
            TextButton(
              key: const Key('wallet-recharge-abandon'),
              onPressed: onStartOver,
              child: const Text('Not you?'),
            ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.canRetry, required this.onRetry});

  final String message;
  final bool canRetry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('wallet-recharge-error'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          if (canRetry)
            TextButton(
              key: const Key('wallet-recharge-retry'),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

class _QuickTopUp extends StatelessWidget {
  const _QuickTopUp({
    required this.selectedAmountPaise,
    required this.enabled,
    required this.minPaise,
    required this.maxPaise,
    required this.onSelect,
  });

  final int? selectedAmountPaise;
  final bool enabled;
  final int minPaise;
  final int maxPaise;
  final ValueChanged<int> onSelect;

  static const _amounts = [50000, 100000, 200000];

  @override
  Widget build(BuildContext context) {
    // MA-125 §6: the recharge bounds are server-configured, not hard-coded
    // (see wallet_repository.dart) — a chip outside the wallet's current
    // [minPaise, maxPaise] must not render, or tapping it would silently
    // leave the Proceed button disabled with no explanation.
    final amounts = _amounts.where((amount) => amount >= minPaise && amount <= maxPaise).toList();
    if (amounts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Top Up', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final amount in amounts)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: amount == amounts.last ? 0 : 8),
                  child: _QuickAmountChip(
                    amountPaise: amount,
                    selected: selectedAmountPaise == amount,
                    enabled: enabled,
                    onTap: () => onSelect(amount),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _QuickAmountChip extends StatelessWidget {
  const _QuickAmountChip({
    required this.amountPaise,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final int amountPaise;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: Key('wallet-quick-topup-${amountPaise ~/ 100}'),
      color: selected ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Text(
            'Add ₹${amountPaise ~/ 100}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: enabled
                  ? (selected ? Colors.white : theme.colorScheme.onSurface)
                  : theme.colorScheme.onSurface.withValues(alpha: 0.38),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentMethods extends StatelessWidget {
  const _PaymentMethods({required this.selected, required this.enabled, required this.onSelect});

  final PaymentMethod selected;
  final bool enabled;
  final ValueChanged<PaymentMethod> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payment Methods', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Semantics(
          label: 'UPI Payments, Google Pay PhonePe BHIM',
          child: _PaymentMethodTile(
            optionKey: 'wallet-method-upi',
            title: 'UPI Payments',
            subtitle: 'Google Pay, PhonePe, BHIM',
            selected: selected == PaymentMethod.upi,
            enabled: enabled,
            onTap: () => onSelect(PaymentMethod.upi),
          ),
        ),
        Semantics(
          label: 'Credit or Debit Card, Visa Mastercard RuPay',
          child: _PaymentMethodTile(
            optionKey: 'wallet-method-card',
            title: 'Credit / Debit Card',
            subtitle: 'Visa, Mastercard, RuPay',
            selected: selected == PaymentMethod.card,
            enabled: enabled,
            onTap: () => onSelect(PaymentMethod.card),
          ),
        ),
      ],
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.optionKey,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String optionKey;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: InkWell(
        key: Key(optionKey),
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: enabled
                    ? (selected ? theme.colorScheme.primary : theme.colorScheme.outline)
                    : theme.disabledColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: enabled ? null : theme.disabledColor)),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: enabled ? theme.colorScheme.onSurfaceVariant : theme.disabledColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProceedButtonBar extends StatelessWidget {
  const _ProceedButtonBar({required this.state});

  final WalletState state;

  @override
  Widget build(BuildContext context) {
    final loading = switch (state.rechargeStatus) {
      RechargeStatus.creatingOrder || RechargeStatus.awaitingGateway || RechargeStatus.confirming => true,
      _ => false,
    };
    final label = state.selectedAmountPaise != null
        ? 'Proceed to Payment · ${_formatPaise(state.selectedAmountPaise!)}'
        : 'Proceed to Payment';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            key: const Key('wallet-proceed-to-payment'),
            onPressed: state.canStartRecharge ? () => context.read<WalletBloc>().add(const RechargeRequested()) : null,
            child: loading
                ? const SizedBox(
                    key: Key('wallet-proceed-loading'),
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(label),
          ),
        ),
      ),
    );
  }
}

class _WebUnsupportedBar extends StatelessWidget {
  const _WebUnsupportedBar();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      key: const Key('wallet-web-unsupported'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          children: [
            const SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(onPressed: null, child: Text('Proceed to Payment')),
            ),
            const SizedBox(height: 8),
            Text(
              'Open the Milkful app on your phone to add money',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopUpAmountSheet extends StatefulWidget {
  const _TopUpAmountSheet({required this.minPaise, required this.maxPaise});

  final int minPaise;
  final int maxPaise;

  @override
  State<_TopUpAmountSheet> createState() => _TopUpAmountSheetState();
}

class _TopUpAmountSheetState extends State<_TopUpAmountSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    final trimmed = _controller.text.trim();
    final rupees = int.tryParse(trimmed);
    if (trimmed.isEmpty || rupees == null) {
      setState(() => _error = 'Enter an amount');
      return;
    }
    final amountPaise = rupees * 100;
    if (amountPaise < widget.minPaise) {
      setState(() => _error = 'Minimum top-up is ${_formatPaise(widget.minPaise)}');
      return;
    }
    if (amountPaise > widget.maxPaise) {
      setState(() => _error = 'Maximum top-up is ${_formatPaise(widget.maxPaise)}');
      return;
    }
    Navigator.of(context).pop(amountPaise);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('wallet-topup-sheet'),
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top Up Wallet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            key: const Key('wallet-topup-amount-field'),
            controller: _controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(prefixText: '₹ ', labelText: 'Amount'),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                key: const Key('wallet-topup-amount-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _continue, child: const Text('Continue')),
          ),
        ],
      ),
    );
  }
}

class _SuccessSheet extends StatelessWidget {
  const _SuccessSheet({required this.amountPaise});

  final int? amountPaise;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('wallet-recharge-success'),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 48),
          const SizedBox(height: 12),
          Text(
            amountPaise != null
                ? '${_formatPaise(amountPaise!)} added to your wallet'
                : 'Money added to your wallet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
          ),
        ],
      ),
    );
  }
}

/// Mirrors `home_screen.dart`'s `_HomeBottomNav` (same items, same visual
/// language) with **Wallet** as the active tab — `/wallet` is a top-level
/// `go` destination (FR-1), not a pushed screen on top of Home, so it
/// needs its own copy of the same chrome rather than reusing Home's
/// (private, and mounted on a different page in the Navigator stack).
class _WalletBottomNav extends StatelessWidget {
  const _WalletBottomNav();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return BottomNavigationBar(
      currentIndex: 2,
      selectedItemColor: primary,
      unselectedItemColor: Colors.grey.shade400,
      onTap: (index) {
        if (index == 0) context.go('/home');
        // 1 (Schedule) and 3 (Profile) remain stubs, same as Home's nav.
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_today_outlined), label: 'Schedule'),
        BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
      ],
    );
  }
}
