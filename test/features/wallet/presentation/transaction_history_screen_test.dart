import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/core/theme/app_theme.dart';
import 'package:milkful_app/features/orders/data/order_repository.dart';
import 'package:milkful_app/features/orders/models/order_summary.dart';
import 'package:milkful_app/features/wallet/data/wallet_repository.dart';
import 'package:milkful_app/features/wallet/models/ledger_entry.dart';
import 'package:milkful_app/features/wallet/models/wallet_status.dart';
import 'package:milkful_app/features/wallet/models/wallet_view.dart';
import 'package:milkful_app/features/wallet/presentation/transaction_history_screen.dart';

import '../../../fakes/fake_order_repository.dart';
import '../../../fakes/fake_wallet_repository.dart';

DateTime _clock() => DateTime.utc(2026, 10, 2, 4, 30); // 10:00 IST

WalletView _wallet({WalletStatus status = WalletStatus.active}) => WalletView(
  walletId: 'wal_1',
  status: status,
  balancePaise: 662146,
  currency: 'INR',
  rechargeMinPaise: 10000,
  rechargeMaxPaise: 10000000,
);

LedgerEntry _entry(String id, String type, int amount, int balance, {String ref = '', DateTime? at}) =>
    LedgerEntry(
      id: id,
      type: LedgerType(type),
      amountPaise: amount,
      balanceAfterPaise: balance,
      ref: ref,
      description: '',
      createdAt: at ?? DateTime.utc(2026, 8, 6, 1, 59, 15),
    );

void main() {
  late FakeWalletRepository wallet;
  late FakeOrderRepository orders;
  late List<String> visited;

  setUp(() {
    wallet = FakeWalletRepository(getWalletResult: _wallet());
    wallet.ledgerPages['|'] = LedgerPage(
      items: [
        _entry('led_3', 'ORDER_DEBIT', -36700, 662146, ref: 'order:ord_1'),
        _entry('led_2', 'REFUND', 4500, 698846, ref: 'refund:ord_1:rf_1'),
        _entry('led_1', 'RECHARGE', 10000, 694346, ref: 'razorpay_payment:p1'),
      ],
    );
    orders = FakeOrderRepository(
      byId: {
        'ord_1': testOrder('ord_1', deliveryDate: DateTime(2026, 8, 6), source: OrderSource.subscription),
      },
    );
    visited = [];
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Widget stub(GoRouterState s) {
      visited.add(s.uri.toString());
      return Scaffold(body: Text('stub ${s.uri}'));
    }

    final router = GoRouter(
      initialLocation: '/wallet/transactions',
      routes: [
        GoRoute(
          path: '/wallet/transactions',
          builder: (_, _) => TransactionHistoryScreen(clock: _clock),
        ),
        GoRoute(path: '/wallet', builder: (_, s) => stub(s)),
        GoRoute(path: '/orders/:id', builder: (_, s) => stub(s)),
      ],
    );
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<WalletRepository>.value(value: wallet),
          RepositoryProvider<OrderRepository>.value(value: orders),
        ],
        // The real theme: its FilledButton has an infinite minimum width.
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the mock layout with signed amounts and closing balances', (tester) async {
    await pump(tester);
    for (final text in [
      'Transaction History',
      'Current Balance',
      '₹6621.46',
      'August',
      'Paid for Order',
      '− ₹367',
      'Refund for Order',
      '+ ₹45',
      'Wallet Top-up',
      'Closing balance: ₹6621.46',
      'Subscription',
      'Thu, 6th Aug 26, 07:29:15 AM',
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    expect(find.byIcon(Icons.search), findsNothing);
    expect(find.textContaining('-₹'), findsNothing);
  });

  testWidgets('filter: Top-ups sends types=RECHARGE, shows a chip, delete resets', (tester) async {
    wallet.ledgerPages['RECHARGE|'] = LedgerPage(
      items: [_entry('led_1', 'RECHARGE', 10000, 694346, ref: 'razorpay_payment:p1')],
    );
    await pump(tester);
    await tester.tap(find.byKey(const Key('txn.filter')));
    await tester.pumpAndSettle();
    expect(find.text('Show'), findsOneWidget);
    await tester.tap(find.text('Top-ups'));
    await tester.pumpAndSettle();

    expect(wallet.listTransactionsCalls.last.types, ['RECHARGE']);
    expect(find.widgetWithText(InputChip, 'Top-ups'), findsOneWidget);
    expect(find.text('Paid for Order'), findsNothing);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(wallet.listTransactionsCalls.last.types, isNull);
    expect(find.text('Paid for Order'), findsOneWidget);
  });

  testWidgets('filtered empty state offers Show all transactions', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('txn.filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refunds & credits'));
    await tester.pumpAndSettle();
    expect(find.text('No refunds or credits yet'), findsOneWidget);
    await tester.tap(find.text('Show all transactions'));
    await tester.pumpAndSettle();
    expect(find.text('Paid for Order'), findsOneWidget);
  });

  testWidgets('empty passbook (all loaded) shows No transactions yet', (tester) async {
    wallet.ledgerPages['|'] = const LedgerPage(items: []);
    await pump(tester);
    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('Top up your wallet to get started.'), findsOneWidget);
  });

  testWidgets('wallet being set up: message, Back to Wallet, no filter icon', (tester) async {
    wallet.listTransactionsException = const ApiException(
      errorCode: 'WALLET_NOT_FOUND',
      message: 'none',
      statusCode: 404,
    );
    await pump(tester);
    expect(find.text('Your wallet is being set up.'), findsOneWidget);
    expect(find.byKey(const Key('txn.filter')), findsNothing);
    await tester.tap(find.text('Back to Wallet'));
    await tester.pumpAndSettle();
    expect(visited.last, '/wallet');
  });

  testWidgets('ledger failure never shows the empty state', (tester) async {
    wallet.listTransactionsException = const ApiException(
      errorCode: 'X',
      message: 'down',
      statusCode: 503,
    );
    await pump(tester);
    expect(find.text("Couldn't load your transactions."), findsOneWidget);
    expect(find.text('No transactions yet'), findsNothing);
  });

  testWidgets('order debit and order refund rows open the order; top-ups do not', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Paid for Order'));
    await tester.pumpAndSettle();
    expect(visited.last, '/orders/ord_1');

    GoRouter.of(tester.element(find.textContaining('stub'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refund for Order'));
    await tester.pumpAndSettle();
    expect(visited.last, '/orders/ord_1');

    GoRouter.of(tester.element(find.textContaining('stub'))).pop();
    await tester.pumpAndSettle();
    final before = visited.length;
    await tester.tap(find.text('Wallet Top-up'));
    await tester.pumpAndSettle();
    expect(visited.length, before);
  });

  testWidgets('ADD MONEY goes to the Wallet screen', (tester) async {
    await pump(tester);
    await tester.tap(find.text('ADD MONEY'));
    await tester.pumpAndSettle();
    expect(visited.last, '/wallet');
  });

  testWidgets('ADD MONEY is disabled while the wallet is not ACTIVE', (tester) async {
    wallet.getWalletResult = _wallet(status: WalletStatus.creating);
    await pump(tester);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'ADD MONEY'));
    expect(button.onPressed, isNull);
  });

  testWidgets('a previous-year month header includes the year', (tester) async {
    wallet.ledgerPages['|'] = LedgerPage(
      items: [_entry('led_9', 'RECHARGE', 10000, 10000, at: DateTime.utc(2025, 12, 20, 6))],
    );
    await pump(tester);
    expect(find.text('December 2025'), findsOneWidget);
  });
}
