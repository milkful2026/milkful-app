import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/ist_clock.dart';
import '../../../core/utils/money.dart';
import '../../orders/data/order_repository.dart';
import '../../orders/domain/order_status_copy.dart' show ChipTone;
import '../../orders/presentation/widgets/status_chip.dart';
import '../bloc/transaction_history_bloc.dart';
import '../bloc/transaction_history_event.dart';
import '../bloc/transaction_history_state.dart';
import '../data/wallet_repository.dart';
import '../domain/ledger_copy.dart';
import '../models/ledger_entry.dart';
import '../models/wallet_status.dart';

/// MA-149 — `/wallet/transactions`: the passbook (mocks
/// `transaction_history` / `transaction_history_updated`). Pushed from the
/// Wallet screen and Profile, so it has a back arrow and no bottom bar.
class TransactionHistoryScreen extends StatelessWidget {
  const TransactionHistoryScreen({super.key, this.clock});

  final Clock? clock;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TransactionHistoryBloc(
        walletRepository: context.read<WalletRepository>(),
        orderRepository: context.read<OrderRepository>(),
        clock: clock,
      )..add(const HistoryOpened()),
      child: const _HistoryView(),
    );
  }
}

class _HistoryView extends StatelessWidget {
  const _HistoryView();

  Future<void> _refresh(BuildContext context) {
    final event = HistoryRefreshed();
    context.read<TransactionHistoryBloc>().add(event);
    return event.completer.future;
  }

  Future<void> _openFilter(BuildContext context, TransactionFilter current) async {
    final bloc = context.read<TransactionHistoryBloc>();
    final chosen = await showModalBottomSheet<TransactionFilter>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text('Show', style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            RadioGroup<TransactionFilter>(
              groupValue: current,
              onChanged: (value) => Navigator.of(sheetContext).pop(value),
              child: Column(
                children: [
                  for (final f in TransactionFilter.values)
                    RadioListTile<TransactionFilter>(value: f, title: Text(f.label)),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen != null) bloc.add(FilterChanged(chosen));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TransactionHistoryBloc, TransactionHistoryState>(
      listenWhen: (a, b) => b.refreshFailedCount > a.refreshFailedCount,
      listener: (context, state) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't refresh. Try again."))),
      builder: (context, state) {
        final notReady = state.ledgerStatus == LedgerStatus.walletNotReady;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Transaction History'),
            actions: [
              if (!notReady)
                IconButton(
                  key: const Key('txn.filter'),
                  tooltip: 'Filter transactions',
                  icon: const Icon(Icons.filter_list),
                  onPressed: () => _openFilter(context, state.filter),
                ),
            ],
          ),
          body: notReady
              ? _Message(
                  title: 'Your wallet is being set up.',
                  body: "Your transactions will appear here once it's ready.",
                  action: FilledButton(
                    onPressed: () => context.go('/wallet'),
                    child: const Text('Back to Wallet'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _refresh(context),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (state.hasMore &&
                          state.pagingStatus == LedgerPagingStatus.idle &&
                          n.metrics.extentAfter < 300) {
                        context.read<TransactionHistoryBloc>().add(const NextPageRequested());
                      }
                      return false;
                    },
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(child: _BalanceCard(state: state)),
                        if (state.filter != TransactionFilter.all)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: InputChip(
                                  label: Text(state.filter.chipLabel),
                                  onDeleted: () => context.read<TransactionHistoryBloc>().add(
                                    const FilterChanged(TransactionFilter.all),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ..._ledgerSlivers(context, state),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  List<Widget> _ledgerSlivers(BuildContext context, TransactionHistoryState state) {
    final bloc = context.read<TransactionHistoryBloc>();
    switch (state.ledgerStatus) {
      case LedgerStatus.loading:
        return [const SliverToBoxAdapter(child: _RowSkeletons())];
      case LedgerStatus.failed:
        return [
          SliverToBoxAdapter(
            child: _Message(
              title: "Couldn't load your transactions.",
              action: TextButton(
                onPressed: () => bloc.add(const RetryLedger()),
                child: const Text('Retry'),
              ),
            ),
          ),
        ];
      case LedgerStatus.walletNotReady:
        return const [];
      case LedgerStatus.loaded:
        break;
    }
    if (state.entries.isEmpty) {
      final filtered = state.filter != TransactionFilter.all;
      return [
        SliverToBoxAdapter(
          child: _Message(
            title: state.filter.emptyText,
            body: filtered ? null : 'Top up your wallet to get started.',
            action: filtered
                ? TextButton(
                    onPressed: () => bloc.add(const FilterChanged(TransactionFilter.all)),
                    child: const Text('Show all transactions'),
                  )
                : null,
          ),
        ),
      ];
    }
    return [
      for (final group in state.groupedByMonth) ...[
        SliverToBoxAdapter(child: _MonthHeader(formatMonthHeader(group.month, state.today))),
        SliverList.builder(
          itemCount: group.entries.length,
          itemBuilder: (context, i) => _LedgerRow(
            entry: group.entries[i],
            chip: ledgerChipLabel(group.entries[i], state.orderSources[group.entries[i].orderId]),
          ),
        ),
      ],
      SliverToBoxAdapter(child: _pagingFooter(context, state)),
    ];
  }

  Widget _pagingFooter(BuildContext context, TransactionHistoryState state) {
    switch (state.pagingStatus) {
      case LedgerPagingStatus.loading:
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        );
      case LedgerPagingStatus.failed:
        return Center(
          child: TextButton(
            key: const Key('txn.loadMoreRetry'),
            onPressed: () => context.read<TransactionHistoryBloc>().add(const NextPageRequested()),
            child: const Text("Couldn't load more. Retry"),
          ),
        );
      case LedgerPagingStatus.idle:
        return const SizedBox.shrink();
    }
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.state});

  final TransactionHistoryState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallet = state.wallet;
    final active = wallet?.status == WalletStatus.active;
    return Container(
      key: const Key('txn.balance'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current Balance', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 4),
                switch (state.balanceStatus) {
                  BalanceStatus.loaded when wallet != null => Text(
                    formatPaise(wallet.balancePaise, alwaysDecimals: true),
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  BalanceStatus.failed => Row(
                    children: [
                      Text('—', style: theme.textTheme.headlineSmall),
                      TextButton(
                        onPressed: () =>
                            context.read<TransactionHistoryBloc>().add(const RetryBalance()),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                  _ => Container(
                    width: 120,
                    height: 24,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                },
              ],
            ),
          ),
          // A fixed width: the theme's FilledButton has an infinite minimum
          // width, which a Row can't lay out (the bug bb3b6fd fixed on Wallet).
          SizedBox(
            width: 140,
            child: FilledButton(
              onPressed: active ? () => context.go('/wallet') : null,
              child: const Text('ADD MONEY'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry, required this.chip});

  final LedgerEntry entry;
  final String chip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = ledgerTitle(entry);
    final amount = formatSignedAmount(entry.amountPaise);
    final timestamp = formatLedgerTimestamp(entry.createdAt);
    final closing = formatPaise(entry.balanceAfterPaise, alwaysDecimals: true);
    final orderId = entry.orderId;
    final spokenAmount = entry.amountPaise > 0
        ? 'plus ${formatPaise(entry.amountPaise)}'
        : entry.amountPaise < 0
        ? 'minus ${formatPaise(-entry.amountPaise)}'
        : formatPaise(0);
    final chipColors = toneColors(
      context,
      entry.type == LedgerType.recharge ? ChipTone.primary : ChipTone.neutral,
    );
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RowIcon(ledgerIcon(entry)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    Text(timestamp, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Text(
                amount,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: entry.amountPaise > 0 ? theme.colorScheme.primary : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: chipColors.background,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  chip,
                  style: theme.textTheme.labelSmall?.copyWith(color: chipColors.foreground),
                ),
              ),
              const Spacer(),
              Flexible(
                flex: 4,
                child: Text(
                  'Closing balance: $closing',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return Semantics(
      key: Key('txn.row.${entry.id}'),
      label: '$title, $spokenAmount, $timestamp, closing balance $closing',
      button: orderId != null,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
        ),
        child: orderId == null
            ? content
            : InkWell(onTap: () => context.push('/orders/$orderId'), child: content),
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  const _RowIcon(this.icon);

  final LedgerIcon icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = switch (icon) {
      LedgerIcon.cart => Icons.shopping_cart_outlined,
      LedgerIcon.walletAdd => Icons.account_balance_wallet_outlined,
      LedgerIcon.gift => Icons.card_giftcard,
      LedgerIcon.people => Icons.people_outline,
      LedgerIcon.tune => Icons.tune,
      LedgerIcon.wallet => Icons.wallet_outlined,
      LedgerIcon.receipt => Icons.receipt_long_outlined,
    };
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: scheme.primaryContainer,
            child: Icon(data, color: scheme.primary),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: CircleAvatar(
              radius: 9,
              backgroundColor: scheme.surface,
              child: Icon(Icons.check_circle_outline, size: 16, color: scheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, this.body, this.action});

  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        if (body != null) ...[
          const SizedBox(height: 6),
          Text(body!, textAlign: TextAlign.center),
        ],
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    ),
  );
}

class _RowSkeletons extends StatelessWidget {
  const _RowSkeletons();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHigh;
    return Semantics(
      label: 'Loading transactions',
      child: Column(
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              height: 76,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
            ),
        ],
      ),
    );
  }
}
