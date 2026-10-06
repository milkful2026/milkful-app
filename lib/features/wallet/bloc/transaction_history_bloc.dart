import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/ist_clock.dart';
import '../../orders/data/order_repository.dart';
import '../../orders/models/order_summary.dart';
import '../data/wallet_repository.dart';
import '../models/ledger_entry.dart';
import 'transaction_history_event.dart';
import 'transaction_history_state.dart';

/// MA-149 — the balance and the ledger load independently; the type filter
/// reloads only the ledger (resetting the cursor); order-type chips come
/// from a per-order cache.
class TransactionHistoryBloc extends Bloc<TransactionHistoryEvent, TransactionHistoryState> {
  TransactionHistoryBloc({
    required WalletRepository walletRepository,
    required OrderRepository orderRepository,
    Clock? clock,
  }) : _wallet = walletRepository,
       _orders = orderRepository,
       _clock = clock ?? DateTime.now,
       super(TransactionHistoryState(today: istToday(clock ?? DateTime.now))) {
    on<HistoryOpened>((event, emit) => _loadAll(emit));
    on<HistoryRefreshed>(_onRefreshed);
    on<FilterChanged>(_onFilterChanged);
    on<NextPageRequested>(_onNextPage, transformer: droppable());
    on<RetryBalance>((event, emit) => _loadBalance(emit, keepOnFailure: false));
    on<RetryLedger>((event, emit) => _loadLedger(emit, keepOnFailure: false));
    on<OrderSourcesResolved>(
      (event, emit) => emit(state.copyWith(orderSources: {...state.orderSources, ...event.sources})),
    );
  }

  static const pageSize = 50;

  final WalletRepository _wallet;
  final OrderRepository _orders;
  final Clock _clock;

  /// Bumped by every ledger (re)load; an older page result is discarded.
  int _generation = 0;
  final Set<String> _requestedOrders = {};

  Future<void> _loadAll(Emitter<TransactionHistoryState> emit, {bool keepOnFailure = false}) async {
    emit(state.copyWith(today: istToday(_clock)));
    final results = await Future.wait([
      _loadBalance(emit, keepOnFailure: keepOnFailure),
      _loadLedger(emit, keepOnFailure: keepOnFailure),
    ]);
    if (keepOnFailure && results.contains(false) && !isClosed) {
      emit(state.copyWith(refreshFailedCount: state.refreshFailedCount + 1));
    }
  }

  Future<void> _onRefreshed(HistoryRefreshed event, Emitter<TransactionHistoryState> emit) async {
    try {
      await _loadAll(emit, keepOnFailure: true);
    } finally {
      if (!event.completer.isCompleted) event.completer.complete();
    }
  }

  Future<bool> _loadBalance(
    Emitter<TransactionHistoryState> emit, {
    required bool keepOnFailure,
  }) async {
    final keep = keepOnFailure && state.balanceStatus == BalanceStatus.loaded;
    if (!keep) emit(state.copyWith(balanceStatus: BalanceStatus.loading));
    try {
      final wallet = await _wallet.getWallet();
      if (isClosed || emit.isDone) return true;
      emit(state.copyWith(balanceStatus: BalanceStatus.loaded, wallet: wallet));
      return true;
    } catch (_) {
      if (!isClosed && !emit.isDone && !keep) {
        emit(state.copyWith(balanceStatus: BalanceStatus.failed));
      }
      return false;
    }
  }

  /// First page for the current filter. With [keepOnFailure] (refresh), a
  /// failure keeps what's shown.
  Future<bool> _loadLedger(
    Emitter<TransactionHistoryState> emit, {
    required bool keepOnFailure,
  }) async {
    final generation = ++_generation;
    final keep = keepOnFailure && state.ledgerStatus == LedgerStatus.loaded;
    if (!keep) {
      emit(state.copyWith(ledgerStatus: LedgerStatus.loading, pagingStatus: LedgerPagingStatus.idle));
    }
    try {
      final page = await _wallet.listTransactions(limit: pageSize, types: state.filter.types);
      if (isClosed || emit.isDone || generation != _generation) return true;
      emit(
        state.copyWith(
          ledgerStatus: LedgerStatus.loaded,
          entries: page.items,
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
          pagingStatus: LedgerPagingStatus.idle,
        ),
      );
      unawaited(_resolveOrders(page.items));
      return true;
    } on ApiException catch (e) {
      if (isClosed || emit.isDone || generation != _generation) return false;
      if (e.statusCode == 404 || e.errorCode == 'WALLET_NOT_FOUND') {
        emit(state.copyWith(ledgerStatus: LedgerStatus.walletNotReady, entries: const []));
      } else if (!keep) {
        emit(state.copyWith(ledgerStatus: LedgerStatus.failed));
      }
      return false;
    } catch (_) {
      if (!isClosed && !emit.isDone && generation == _generation && !keep) {
        emit(state.copyWith(ledgerStatus: LedgerStatus.failed));
      }
      return false;
    }
  }

  Future<void> _onFilterChanged(FilterChanged event, Emitter<TransactionHistoryState> emit) async {
    if (event.filter == state.filter) return;
    emit(state.copyWith(filter: event.filter, entries: const [], clearNextCursor: true));
    await _loadLedger(emit, keepOnFailure: false);
  }

  Future<void> _onNextPage(NextPageRequested event, Emitter<TransactionHistoryState> emit) async {
    final cursor = state.nextCursor;
    if (cursor == null || state.ledgerStatus != LedgerStatus.loaded) return;
    final generation = _generation;
    emit(state.copyWith(pagingStatus: LedgerPagingStatus.loading));
    try {
      final page = await _wallet.listTransactions(
        cursor: cursor,
        limit: pageSize,
        types: state.filter.types,
      );
      if (isClosed) return;
      if (generation != _generation) return _clearStalePaging(emit); // filter changed / refreshed
      final seen = {for (final e in state.entries) e.id};
      emit(
        state.copyWith(
          entries: [...state.entries, ...page.items.where((e) => !seen.contains(e.id))],
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
          pagingStatus: LedgerPagingStatus.idle,
        ),
      );
      // Not awaited: the droppable handler must finish as soon as the page is
      // shown, or load-more requests during the lookups are silently dropped.
      unawaited(_resolveOrders(page.items));
    } catch (_) {
      if (isClosed) return;
      if (generation != _generation) return _clearStalePaging(emit);
      emit(state.copyWith(pagingStatus: LedgerPagingStatus.failed));
    }
  }

  /// A page outdated by a reload is dropped; its spinner must not outlive it
  /// (a failed refresh keeps the old state, so nothing else would clear it).
  void _clearStalePaging(Emitter<TransactionHistoryState> emit) {
    if (state.pagingStatus == LedgerPagingStatus.loading) {
      emit(state.copyWith(pagingStatus: LedgerPagingStatus.idle));
    }
  }

  /// One `GET /orders/{id}` per distinct order for the bloc's lifetime;
  /// a failure caches null (the chip reads "Order"). Results arrive via
  /// [OrderSourcesResolved] so callers needn't wait on the lookups.
  Future<void> _resolveOrders(List<LedgerEntry> page) async {
    final ids = {
      for (final e in page)
        if (e.orderId != null && !_requestedOrders.contains(e.orderId)) e.orderId!,
    }.toList();
    if (ids.isEmpty) return;
    _requestedOrders.addAll(ids);
    final fetched = await Future.wait(
      ids.map((id) async {
        try {
          return MapEntry<String, OrderSource?>(id, (await _orders.getById(id)).source);
        } catch (_) {
          return MapEntry<String, OrderSource?>(id, null);
        }
      }),
    );
    if (!isClosed) add(OrderSourcesResolved(Map.fromEntries(fetched)));
  }
}
