import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/orders/models/order_summary.dart';
import 'package:milkful_app/features/wallet/bloc/transaction_history_bloc.dart';
import 'package:milkful_app/features/wallet/bloc/transaction_history_event.dart';
import 'package:milkful_app/features/wallet/bloc/transaction_history_state.dart';
import 'package:milkful_app/features/wallet/domain/ledger_copy.dart';
import 'package:milkful_app/features/wallet/models/ledger_entry.dart';
import 'package:milkful_app/features/wallet/models/wallet_status.dart';
import 'package:milkful_app/features/wallet/models/wallet_view.dart';

import '../../../fakes/fake_order_repository.dart';
import '../../../fakes/fake_wallet_repository.dart';

DateTime _clock() => DateTime.utc(2026, 10, 2, 4, 30);

const _wallet = WalletView(
  walletId: 'wal_1',
  status: WalletStatus.active,
  balancePaise: 662146,
  currency: 'INR',
  rechargeMinPaise: 10000,
  rechargeMaxPaise: 10000000,
);

LedgerEntry entry(String id, String type, {String ref = '', int amount = -100}) => LedgerEntry(
  id: id,
  type: LedgerType(type),
  amountPaise: amount,
  balanceAfterPaise: 1000,
  ref: ref,
  description: '',
  createdAt: DateTime.utc(2026, 8, 6),
);

const _boom = ApiException(errorCode: 'SERVICE_UNAVAILABLE', message: 'down', statusCode: 503);

void main() {
  late FakeWalletRepository wallet;
  late FakeOrderRepository orders;

  setUp(() {
    wallet = FakeWalletRepository(getWalletResult: _wallet);
    wallet.ledgerPages['|'] = LedgerPage(
      items: [
        entry('led_3', 'ORDER_DEBIT', ref: 'order:ord_1'),
        entry('led_2', 'REFUND', ref: 'refund:ord_1:rf_1', amount: 50),
        entry('led_1', 'RECHARGE', ref: 'razorpay_payment:p1', amount: 10000),
      ],
      nextCursor: 'c2',
    );
    wallet.ledgerPages['|c2'] = LedgerPage(items: [entry('led_0', 'OPENING', amount: 0)]);
    wallet.ledgerPages['RECHARGE|'] = LedgerPage(
      items: [entry('led_1', 'RECHARGE', ref: 'razorpay_payment:p1', amount: 10000)],
    );
    orders = FakeOrderRepository(
      byId: {
        'ord_1': testOrder('ord_1', deliveryDate: DateTime(2026, 8, 6), source: OrderSource.subscription),
      },
    );
  });

  TransactionHistoryBloc build() =>
      TransactionHistoryBloc(walletRepository: wallet, orderRepository: orders, clock: _clock);

  Future<TransactionHistoryState> settle(TransactionHistoryBloc bloc) async {
    await Future<void>.delayed(Duration.zero);
    await pumpEventQueue();
    return bloc.state;
  }

  test('opened → balance and ledger load independently; order sources resolve', () async {
    final bloc = build()..add(const HistoryOpened());
    final s = await settle(bloc);
    expect(s.balanceStatus, BalanceStatus.loaded);
    expect(s.wallet, _wallet);
    expect(s.ledgerStatus, LedgerStatus.loaded);
    expect(s.entries.map((e) => e.id), ['led_3', 'led_2', 'led_1']);
    expect(s.orderSources, {'ord_1': OrderSource.subscription});
    expect(orders.getCalls, ['ord_1']); // debit + refund of one order → one lookup
    await bloc.close();
  });

  test('ledger 404 → walletNotReady, balance still loaded', () async {
    wallet.listTransactionsException = const ApiException(
      errorCode: 'WALLET_NOT_FOUND',
      message: 'none',
      statusCode: 404,
    );
    final bloc = build()..add(const HistoryOpened());
    final s = await settle(bloc);
    expect(s.ledgerStatus, LedgerStatus.walletNotReady);
    expect(s.balanceStatus, BalanceStatus.loaded);
    await bloc.close();
  });

  test('ledger failure → failed; RetryLedger → loaded (balance untouched)', () async {
    wallet.listTransactionsException = _boom;
    final bloc = build()..add(const HistoryOpened());
    expect((await settle(bloc)).ledgerStatus, LedgerStatus.failed);
    wallet.listTransactionsException = null;
    bloc.add(const RetryLedger());
    final s = await settle(bloc);
    expect(s.ledgerStatus, LedgerStatus.loaded);
    expect(wallet.getWalletCallCount, 1);
    await bloc.close();
  });

  test('balance failure → failed; RetryBalance → loaded', () async {
    wallet.getWalletException = _boom;
    final bloc = build()..add(const HistoryOpened());
    var s = await settle(bloc);
    expect((s.balanceStatus, s.ledgerStatus), (BalanceStatus.failed, LedgerStatus.loaded));
    wallet.getWalletException = null;
    bloc.add(const RetryBalance());
    s = await settle(bloc);
    expect(s.balanceStatus, BalanceStatus.loaded);
    await bloc.close();
  });

  test('FilterChanged resets the cursor, sends the types, keeps the balance', () async {
    final bloc = build()..add(const HistoryOpened());
    await settle(bloc);
    bloc.add(const FilterChanged(TransactionFilter.topUps));
    final s = await settle(bloc);
    expect(wallet.listTransactionsCalls.last.types, ['RECHARGE']);
    expect(wallet.listTransactionsCalls.last.cursor, isNull);
    expect(s.entries.map((e) => e.id), ['led_1']);
    expect(s.nextCursor, isNull);
    expect(wallet.getWalletCallCount, 1);
    await bloc.close();
  });

  test('paging appends; a duplicate request in flight is dropped', () async {
    wallet.transactionsGate = Completer<void>();
    final bloc = build()..add(const HistoryOpened());
    await settle(bloc);
    bloc
      ..add(const NextPageRequested())
      ..add(const NextPageRequested());
    await settle(bloc);
    wallet.transactionsGate!.complete();
    final s = await settle(bloc);
    expect(wallet.listTransactionsCalls.where((c) => c.cursor == 'c2'), hasLength(1));
    expect(s.entries.last.id, 'led_0');
    expect(s.nextCursor, isNull);
    await bloc.close();
  });

  test('a filter change during an in-flight page discards the stale page', () async {
    wallet.transactionsGate = Completer<void>();
    final bloc = build()..add(const HistoryOpened());
    await settle(bloc);
    bloc.add(const NextPageRequested());
    await settle(bloc);
    bloc.add(const FilterChanged(TransactionFilter.topUps));
    await settle(bloc);
    wallet.transactionsGate!.complete();
    final s = await settle(bloc);
    expect(s.entries.map((e) => e.id), ['led_1']);
    await bloc.close();
  });

  test('a failed order lookup is cached as null and not retried on refresh', () async {
    orders.getException = _boom;
    final bloc = build()..add(const HistoryOpened());
    var s = await settle(bloc);
    expect(s.orderSources.containsKey('ord_1'), isTrue);
    expect(s.orderSources['ord_1'], isNull);
    bloc.add(HistoryRefreshed());
    s = await settle(bloc);
    expect(orders.getCalls, ['ord_1']);
    await bloc.close();
  });

  test('a failed refresh keeps the entries and bumps refreshFailedCount', () async {
    final bloc = build()..add(const HistoryOpened());
    await settle(bloc);
    wallet.listTransactionsException = _boom;
    final refresh = HistoryRefreshed();
    bloc.add(refresh);
    await refresh.completer.future;
    final s = await settle(bloc);
    expect(s.refreshFailedCount, 1);
    expect(s.ledgerStatus, LedgerStatus.loaded);
    expect(s.entries, hasLength(3));
    await bloc.close();
  });

  test('page failure keeps entries and sets paging failed', () async {
    wallet.transactionsPageException = _boom;
    final bloc = build()..add(const HistoryOpened());
    await settle(bloc);
    bloc.add(const NextPageRequested());
    final s = await settle(bloc);
    expect(s.pagingStatus, LedgerPagingStatus.failed);
    expect(s.entries, hasLength(3));
    await bloc.close();
  });
}
