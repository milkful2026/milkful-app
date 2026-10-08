import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/cart/data/cart_repository.dart';
import 'package:milkful_app/features/catalog/data/catalog_repository.dart';
import 'package:milkful_app/features/catalog/models/product.dart';
import 'package:milkful_app/features/orders/data/order_repository.dart';
import 'package:milkful_app/features/orders/models/order_entry.dart';
import 'package:milkful_app/features/orders/models/order_summary.dart';
import 'package:milkful_app/features/orders/models/orders_page.dart';
import 'package:milkful_app/features/orders/presentation/order_detail_screen.dart';
import 'package:milkful_app/features/orders/presentation/scheduled_delivery_screen.dart';
import 'package:milkful_app/features/subscriptions/data/subscription_repository.dart';
import 'package:milkful_app/features/subscriptions/models/schedule.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_status.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_view.dart';

import '../../../fakes/fake_cart_repository.dart';
import '../../../fakes/fake_catalog_repository.dart';
import '../../../fakes/fake_order_repository.dart';
import '../../../fakes/fake_subscription_repository.dart';

/// MA-155 — the cancel flows on Order Detail and Scheduled Delivery.
/// Delivery is 3 Oct, so the cut-off is 20:00 IST on 2 Oct (14:30 UTC).
final _delivery = DateTime(2026, 10, 3);
final _cutoff = DateTime.utc(2026, 10, 2, 14, 30);
final _beforeCutoff = DateTime.utc(2026, 10, 1, 4, 30); // 10:00 IST on 1 Oct
final _afterCutoff = _cutoff.add(const Duration(minutes: 1));

const _closedLine = 'Cancellation closed at 8 PM the day before delivery.';

Product _p(String id, String name, double price) => Product(
  id: id,
  categoryId: 'c',
  name: name,
  description: '',
  unit: '1L',
  price: price,
  stockState: StockState.inStock,
);

OrderSummary _confirmed({DateTime? cancellableUntil, int amountPaise = 15500}) => testOrder(
  'ord_1',
  deliveryDate: _delivery,
  amountPaise: amountPaise,
  cancellableUntil: cancellableUntil,
);

OrderSummary _cancelled(RefundState refund) => testOrder(
  'ord_1',
  deliveryDate: _delivery,
  amountPaise: 15500,
  status: OrderStatus.cancelled,
  failureReason: 'CUSTOMER_CANCELLED',
  refundState: refund,
  cancelReason: CancelReason.notHome,
);

void main() {
  late FakeOrderRepository orders;
  late FakeSubscriptionRepository subs;
  late DateTime now;
  late List<String> visited;

  setUp(() {
    orders = FakeOrderRepository();
    subs = FakeSubscriptionRepository();
    now = _beforeCutoff;
    visited = [];
  });

  /// Pushes [location] over `/start` and returns what the pushed screen
  /// closes with.
  Future<Future<Object?>> pump(WidgetTester tester, String location, {Object? extra}) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Widget stub(GoRouterState s) {
      visited.add(s.uri.toString());
      return Scaffold(body: Text('stub ${s.uri}'));
    }

    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(path: '/start', builder: (_, s) => stub(s)),
        GoRoute(path: '/catalog', builder: (_, s) => stub(s)),
        GoRoute(path: '/orders', builder: (_, s) => stub(s)),
        GoRoute(
          path: '/orders/scheduled/:id',
          builder: (_, s) => ScheduledDeliveryScreen(
            subscriptionId: s.pathParameters['id']!,
            entry: s.extra is ScheduledEntry ? s.extra as ScheduledEntry : null,
            clock: () => now,
          ),
        ),
        GoRoute(
          path: '/orders/:id',
          builder: (_, s) => OrderDetailScreen(orderId: s.pathParameters['id']!, clock: () => now),
        ),
      ],
    );
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<OrderRepository>.value(value: orders),
          RepositoryProvider<SubscriptionRepository>.value(value: subs),
          RepositoryProvider<CatalogRepository>.value(
            value: FakeCatalogRepository(
              productsById: {'cow-milk': _p('cow-milk', 'Pure Cow Milk', 65)},
            ),
          ),
          RepositoryProvider<CartRepository>.value(value: FakeCartRepository()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final closed = router.push<Object?>(location, extra: extra);
    await tester.pumpAndSettle();
    return closed;
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('orderDetail.cancel')));
    await tester.pumpAndSettle();
  }

  Text grandTotal(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('orderDetail.grandTotal')));

  group('Order Detail: Cancel order', () {
    testWidgets('cancel a paid order', (tester) async {
      orders.byId['ord_1'] = _confirmed(cancellableUntil: _cutoff);
      orders.cancelResult = _cancelled(RefundState.refunded);
      final closed = await pump(tester, '/orders/ord_1');

      expect(find.text('Free cancellation until 8:00 PM, Fri 2 Oct'), findsOneWidget);
      await openSheet(tester);
      expect(find.text('Cancel this order?'), findsOneWidget);
      expect(
        find.text("You'll get a full refund of ₹155.00 to your Milkful Wallet."),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('cancelOrder.reason.NOT_HOME')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('cancelOrder.confirm')));
      await tester.pumpAndSettle();

      expect(orders.cancelCalls, [('ord_1', CancelReason.notHome)]);
      expect(find.byKey(const Key('cancelOrder.sheet')), findsNothing);
      expect(find.text('Order cancelled. ₹155.00 refunded to your Wallet.'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(
        find.text('You cancelled this order. ₹155.00 was refunded to your Wallet.'),
        findsOneWidget,
      );
      expect(find.text('Refunded to Wallet'), findsOneWidget);
      expect(grandTotal(tester).style?.decoration, isNot(TextDecoration.lineThrough));
      expect(find.byKey(const Key('orderDetail.cancel')), findsNothing);
      expect(find.text(_closedLine), findsNothing);

      // Back hands `true` to My Orders, so it reloads.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(await closed, isTrue);
    });

    testWidgets('Shop for tomorrow goes to the catalog', (tester) async {
      orders.byId['ord_1'] = _confirmed(cancellableUntil: _cutoff);
      orders.cancelResult = _cancelled(RefundState.refunded);
      await pump(tester, '/orders/ord_1');
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('cancelOrder.confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shop for tomorrow'));
      await tester.pumpAndSettle();
      expect(visited.last, '/catalog');
    });

    testWidgets('keep order: the sheet closes and nothing is sent', (tester) async {
      orders.byId['ord_1'] = _confirmed(cancellableUntil: _cutoff);
      final closed = await pump(tester, '/orders/ord_1');
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('cancelOrder.keep')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cancelOrder.sheet')), findsNothing);
      expect(orders.cancelCalls, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(await closed, isNull); // nothing changed: no reload
    });

    testWidgets('refund pending', (tester) async {
      orders.byId['ord_1'] = _confirmed(cancellableUntil: _cutoff);
      orders.cancelResult = _cancelled(RefundState.pending);
      await pump(tester, '/orders/ord_1');
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('cancelOrder.confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Order cancelled. Your refund is on its way.'), findsOneWidget);
      expect(find.text('You cancelled this order. Your refund is in progress.'), findsOneWidget);
      expect(find.text('Refund in progress'), findsOneWidget);
      expect(find.textContaining('refunded'), findsNothing);
    });

    testWidgets('cut-off passed on submit', (tester) async {
      orders.byId['ord_1'] = _confirmed(cancellableUntil: _cutoff);
      await pump(tester, '/orders/ord_1');
      await openSheet(tester);
      // The screen stayed open across 20:00 IST; the server refuses.
      now = _afterCutoff;
      orders.cancelException = const ApiException(
        errorCode: 'CUTOFF_PASSED',
        message: 'late',
        statusCode: 409,
      );
      orders.byId['ord_1'] = _confirmed(); // the reload: cancellableUntil null
      await tester.tap(find.byKey(const Key('cancelOrder.confirm')));
      await tester.pumpAndSettle();
      expect(
        find.text("It's past the 8 PM cut-off, so this order can't be cancelled now."),
        findsOneWidget,
      );
      expect(find.byKey(const Key('orderDetail.cancel')), findsNothing);
      expect(find.text(_closedLine), findsOneWidget);
    });

    testWidgets('not cancellable on submit', (tester) async {
      orders.byId['ord_1'] = _confirmed(cancellableUntil: _cutoff);
      await pump(tester, '/orders/ord_1');
      await openSheet(tester);
      orders.cancelException = const ApiException(
        errorCode: 'ORDER_NOT_CANCELLABLE',
        message: 'no',
        statusCode: 409,
      );
      await tester.tap(find.byKey(const Key('cancelOrder.confirm')));
      await tester.pumpAndSettle();
      expect(find.text("This order can't be cancelled anymore."), findsOneWidget);
      expect(find.byKey(const Key('cancelOrder.sheet')), findsNothing);
    });

    testWidgets('network error: the sheet stays with its reason', (tester) async {
      orders.byId['ord_1'] = _confirmed(cancellableUntil: _cutoff);
      orders.cancelException = const ApiException(
        errorCode: 'SERVICE_UNAVAILABLE',
        message: 'down',
        statusCode: 503,
      );
      await pump(tester, '/orders/ord_1');
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('cancelOrder.reason.NOT_HOME')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('cancelOrder.confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cancelOrder.sheet')), findsOneWidget);
      expect(find.text("Couldn't cancel. Try again."), findsOneWidget);
      final chip = tester.widget<ChoiceChip>(find.byKey(const Key('cancelOrder.reason.NOT_HOME')));
      expect(chip.selected, isTrue);
      final confirm = tester.widget<FilledButton>(find.byKey(const Key('cancelOrder.confirm')));
      expect(confirm.onPressed, isNotNull);
    });

    testWidgets('tapping the selected reason clears it', (tester) async {
      orders.byId['ord_1'] = _confirmed(cancellableUntil: _cutoff);
      orders.cancelResult = _cancelled(RefundState.refunded);
      await pump(tester, '/orders/ord_1');
      await openSheet(tester);
      await tester.tap(find.byKey(const Key('cancelOrder.reason.OTHER')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('cancelOrder.reason.OTHER')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('cancelOrder.confirm')));
      await tester.pumpAndSettle();
      expect(orders.cancelCalls, [('ord_1', null)]);
    });

    testWidgets('a ₹0 order says nothing was charged', (tester) async {
      orders.byId['ord_1'] = _confirmed(cancellableUntil: _cutoff, amountPaise: 0);
      await pump(tester, '/orders/ord_1');
      await openSheet(tester);
      expect(find.text('Nothing was charged for this order.'), findsOneWidget);
    });

    group('not offered', () {
      testWidgets('past the cut-off: the closed line', (tester) async {
        now = _afterCutoff;
        orders.byId['ord_1'] = _confirmed();
        await pump(tester, '/orders/ord_1');
        expect(find.byKey(const Key('orderDetail.cancel')), findsNothing);
        expect(find.text(_closedLine), findsOneWidget);
      });

      testWidgets('older backend before the cut-off: neither button nor line', (tester) async {
        orders.byId['ord_1'] = _confirmed(); // no cancellableUntil
        await pump(tester, '/orders/ord_1');
        expect(find.byKey(const Key('orderDetail.cancel')), findsNothing);
        expect(find.text(_closedLine), findsNothing);
      });

      for (final status in [OrderStatus.cancelled, OrderStatus.paymentFailed]) {
        testWidgets('${status.wire}: no cancel UI', (tester) async {
          now = _afterCutoff;
          orders.byId['ord_1'] = testOrder('ord_1', deliveryDate: _delivery, status: status);
          await pump(tester, '/orders/ord_1');
          expect(find.byKey(const Key('orderDetail.cancel')), findsNothing);
          expect(find.text(_closedLine), findsNothing);
        });
      }
    });
  });

  group('Scheduled Delivery: Cancel delivery', () {
    final entry = ScheduledEntry(
      subscriptionId: 'sub_1',
      productId: 'cow-milk',
      quantity: 2,
      date: _delivery,
    );

    SubscriptionView sub(DateTime next) => SubscriptionView(
      id: 'sub_1',
      productId: 'cow-milk',
      quantity: 2,
      schedule: const Schedule(type: ScheduleType.daily),
      status: SubscriptionStatus.active,
      nextDeliveryDate: next,
    );

    testWidgets('cancel a scheduled delivery', (tester) async {
      final closed = await pump(tester, '/orders/scheduled/sub_1', extra: entry);
      expect(find.text('Free cancellation until 8:00 PM, Fri 2 Oct'), findsOneWidget);
      await tester.tap(find.byKey(const Key('scheduled.cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this delivery?'), findsOneWidget);
      expect(find.textContaining('Your Pure Cow Milk delivery on Sat 3 Oct'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancelDelivery.confirm')));
      await tester.pumpAndSettle();

      expect(subs.skipCalls, ['sub_1']);
      expect(subs.skipDates, [_delivery]);
      expect(find.text('Delivery on Sat 3 Oct cancelled.'), findsOneWidget);
      expect(find.text('Shop for tomorrow'), findsOneWidget);
      expect(find.text('stub /start'), findsOneWidget); // closed
      expect(await closed, isTrue); // My Orders reloads
    });

    testWidgets('keep delivery: nothing is sent', (tester) async {
      await pump(tester, '/orders/scheduled/sub_1', extra: entry);
      await tester.tap(find.byKey(const Key('scheduled.cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep delivery'));
      await tester.pumpAndSettle();
      expect(subs.skipCalls, isEmpty);
      expect(find.byKey(const Key('cancelDelivery.dialog')), findsNothing);
    });

    testWidgets('past the cut-off: the closed line, no button', (tester) async {
      now = _afterCutoff;
      await pump(tester, '/orders/scheduled/sub_1', extra: entry);
      expect(find.byKey(const Key('scheduled.cancel')), findsNothing);
      expect(find.text(_closedLine), findsOneWidget);
    });

    testWidgets('already an order: says so and offers View order', (tester) async {
      subs.actionException = const ApiException(
        errorCode: 'CUTOFF_PASSED',
        message: 'processed',
        statusCode: 409,
      );
      subs.subscriptions = [sub(DateTime(2026, 10, 4))];
      final order = testOrder('ord_9', deliveryDate: _delivery, subscriptionId: 'sub_1');
      orders.pages = {null: OrdersPage(items: [order])};
      orders.byId['ord_9'] = order;
      final closed = await pump(tester, '/orders/scheduled/sub_1', extra: entry);
      Object? closedWith; // not awaited: a regression would hang, not fail
      closed.then((v) => closedWith = v);
      await tester.tap(find.byKey(const Key('scheduled.cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancelDelivery.confirm')));
      await tester.pumpAndSettle();

      expect(
        find.text('This delivery is already an order. Cancel it from the order instead.'),
        findsOneWidget,
      );
      expect(find.text('This delivery is now an order.'), findsNothing);
      expect(
        find.text("It's past the 8 PM cut-off, so this delivery can't be cancelled now."),
        findsNothing,
      );
      await tester.tap(find.text('View order'));
      await tester.pumpAndSettle();
      expect(find.text('Order Placed'), findsOneWidget); // now on /orders/ord_9

      // Back from the order also closes the scheduled screen with true, so
      // My Orders reloads (pushReplacement would leave `closed` pending).
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('stub /start'), findsOneWidget);
      expect(closedWith, isTrue);
    });

    testWidgets('View order, then cancel the order: My Orders still reloads', (tester) async {
      subs.actionException = const ApiException(
        errorCode: 'CUTOFF_PASSED',
        message: 'processed',
        statusCode: 409,
      );
      subs.subscriptions = [sub(DateTime(2026, 10, 4))];
      final order = testOrder(
        'ord_9',
        deliveryDate: _delivery,
        subscriptionId: 'sub_1',
        cancellableUntil: _cutoff,
      );
      orders.pages = {null: OrdersPage(items: [order])};
      orders.byId['ord_9'] = order;
      orders.cancelResult = _cancelled(RefundState.refunded);
      final closed = await pump(tester, '/orders/scheduled/sub_1', extra: entry);
      Object? closedWith; // not awaited: a regression would hang, not fail
      closed.then((v) => closedWith = v);
      await tester.tap(find.byKey(const Key('scheduled.cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancelDelivery.confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View order'));
      await tester.pumpAndSettle();

      await openSheet(tester);
      await tester.tap(find.byKey(const Key('cancelOrder.confirm')));
      await tester.pumpAndSettle();
      expect(orders.cancelCalls, hasLength(1));
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('stub /start'), findsOneWidget);
      expect(closedWith, isTrue);
    });

    testWidgets('a failed skip keeps the screen', (tester) async {
      subs.actionException = const ApiException(
        errorCode: 'SERVICE_UNAVAILABLE',
        message: 'down',
        statusCode: 503,
      );
      await pump(tester, '/orders/scheduled/sub_1', extra: entry);
      await tester.tap(find.byKey(const Key('scheduled.cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancelDelivery.confirm')));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't cancel. Try again."), findsOneWidget);
      expect(find.text('SCHEDULED DELIVERY'), findsOneWidget);
    });
  });
}
