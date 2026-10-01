import 'dart:async';

import 'package:equatable/equatable.dart';

import '../domain/ledger_copy.dart';

sealed class TransactionHistoryEvent extends Equatable {
  const TransactionHistoryEvent();

  @override
  List<Object?> get props => [];
}

class HistoryOpened extends TransactionHistoryEvent {
  const HistoryOpened();
}

/// Pull-to-refresh; [completer] resolves when it settles.
class HistoryRefreshed extends TransactionHistoryEvent {
  HistoryRefreshed({Completer<void>? completer}) : completer = completer ?? Completer<void>();

  final Completer<void> completer;

  @override
  List<Object?> get props => [completer];
}

class FilterChanged extends TransactionHistoryEvent {
  const FilterChanged(this.filter);

  final TransactionFilter filter;

  @override
  List<Object?> get props => [filter];
}

class NextPageRequested extends TransactionHistoryEvent {
  const NextPageRequested();
}

class RetryBalance extends TransactionHistoryEvent {
  const RetryBalance();
}

class RetryLedger extends TransactionHistoryEvent {
  const RetryLedger();
}
