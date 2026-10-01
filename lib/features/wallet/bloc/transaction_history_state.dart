import 'package:equatable/equatable.dart';

import '../../orders/models/order_summary.dart';
import '../domain/ledger_copy.dart';
import '../models/ledger_entry.dart';
import '../models/wallet_view.dart';

enum BalanceStatus { loading, loaded, failed }

/// `walletNotReady`: the ledger answered 404 WALLET_NOT_FOUND (still
/// being provisioned) — not an error.
enum LedgerStatus { loading, loaded, failed, walletNotReady }

enum LedgerPagingStatus { idle, loading, failed }

class MonthGroup {
  const MonthGroup(this.month, this.entries);

  final DateTime month;
  final List<LedgerEntry> entries;
}

class TransactionHistoryState extends Equatable {
  const TransactionHistoryState({
    required this.today,
    this.balanceStatus = BalanceStatus.loading,
    this.wallet,
    this.ledgerStatus = LedgerStatus.loading,
    this.entries = const [],
    this.nextCursor,
    this.filter = TransactionFilter.all,
    this.orderSources = const {},
    this.pagingStatus = LedgerPagingStatus.idle,
    this.refreshFailedCount = 0,
  });

  /// IST today (date-only), for month-header years.
  final DateTime today;
  final BalanceStatus balanceStatus;
  final WalletView? wallet;
  final LedgerStatus ledgerStatus;
  final List<LedgerEntry> entries;
  final String? nextCursor;
  final TransactionFilter filter;

  /// Order lookups by id: a present key mapped to null = lookup failed.
  final Map<String, OrderSource?> orderSources;
  final LedgerPagingStatus pagingStatus;
  final int refreshFailedCount;

  bool get hasMore => nextCursor != null;

  /// Entries in order, grouped by IST calendar month (newest first).
  List<MonthGroup> get groupedByMonth {
    final groups = <MonthGroup>[];
    for (final e in entries) {
      final month = istMonth(e.createdAt);
      if (groups.isEmpty || groups.last.month != month) {
        groups.add(MonthGroup(month, [e]));
      } else {
        groups.last.entries.add(e);
      }
    }
    return groups;
  }

  TransactionHistoryState copyWith({
    DateTime? today,
    BalanceStatus? balanceStatus,
    WalletView? wallet,
    LedgerStatus? ledgerStatus,
    List<LedgerEntry>? entries,
    String? nextCursor,
    bool clearNextCursor = false,
    TransactionFilter? filter,
    Map<String, OrderSource?>? orderSources,
    LedgerPagingStatus? pagingStatus,
    int? refreshFailedCount,
  }) => TransactionHistoryState(
    today: today ?? this.today,
    balanceStatus: balanceStatus ?? this.balanceStatus,
    wallet: wallet ?? this.wallet,
    ledgerStatus: ledgerStatus ?? this.ledgerStatus,
    entries: entries ?? this.entries,
    nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
    filter: filter ?? this.filter,
    orderSources: orderSources ?? this.orderSources,
    pagingStatus: pagingStatus ?? this.pagingStatus,
    refreshFailedCount: refreshFailedCount ?? this.refreshFailedCount,
  );

  @override
  List<Object?> get props => [
    today,
    balanceStatus,
    wallet,
    ledgerStatus,
    entries,
    nextCursor,
    filter,
    orderSources,
    pagingStatus,
    refreshFailedCount,
  ];
}
