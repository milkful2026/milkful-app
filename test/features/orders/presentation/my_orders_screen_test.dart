import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/catalog/data/catalog_repository.dart';
import 'package:milkful_app/features/catalog/models/product.dart';
import 'package:milkful_app/features/orders/data/order_repository.dart';
import 'package:milkful_app/features/orders/models/order_summary.dart';
import 'package:milkful_app/features/orders/models/orders_page.dart';
import 'package:milkful_app/features/orders/presentation/my_orders_screen.dart';
import 'package:milkful_app/features/subscriptions/data/subscription_repository.dart';
import 'package:milkful_app/features/subscriptions/models/schedule.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_status.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_view.dart';

import '../../../fakes/fake_catalog_repository.dart';
import '../../../fakes/fake_order_repository.dart';
import '../../../fakes/fake_subscription_repository.dart';

// 2026-10-01 10:00 IST (a Thursday).
DateTime _clock() => DateTime.utc(2026, 10, 1, 4, 30);
final _today = DateTime(2026, 10, 1);
DateTime _d(int offset) => _today.add(Duration(days: offset));

const _boom = ApiException(errorCode: 'SERVICE_UNAVAILABLE', message: 'down', statusCode: 503);

Product _p(String id, String name, double price) => Product(
  id: id,
  categoryId: 'c',
  name: name,
  description: '',
  unit: '500ml',
  price: price,
  stockState: StockState.inStock,
);

final _products = {
  'cow-milk': _p('cow-milk', 'Pure Cow Milk', 65),
  'eggs': _p('eggs', 'Farm Fresh Eggs', 120),
  'curd': _p('curd', 'Organic Curd', 45),
};

void main() {
  late FakeOrderRepository orders;
  late FakeSubscriptionRepository subs;
  late FakeCatalogRepository catalog;
  late List<String> pushed;

  setUp(() {
    orders = FakeOrderRepository();
    subs = FakeSubscriptionRepository();
    catalog = FakeCatalogRepository(productsById: _products);
    pushed = [];
  });

  Future<void> pump(WidgetTester tester) async {
    Widget stub(GoRouterState s) {
      pushed.add(s.uri.toString());
      return Scaffold(body: Text('stub ${s.uri}'));
    }

    final router = GoRouter(
      initialLocation: '/orders',
      routes: [
        GoRoute(path: '/orders', builder: (_, _) => MyOrdersScreen(clock: _clock)),
        GoRoute(path: '/orders/scheduled/:id', builder: (_, s) => stub(s)),
        GoRoute(path: '/orders/:id', builder: (_, s) => stub(s)),
        GoRoute(path: '/catalog', builder: (_, s) => stub(s)),
      ],
    );
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<OrderRepository>.value(value: orders),
          RepositoryProvider<SubscriptionRepository>.value(value: subs),
          RepositoryProvider<CatalogRepository>.value(value: catalog),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("today's delivery: item cards, order total once, chips", (tester) async {
    orders.pages = {
      null: OrdersPage(
        items: [
          testOrder(
            'multi',
            deliveryDate: _d(0),
            amountPaise: 15500,
            items: const [
              OrderItem(productId: 'cow-milk', quantity: 1),
              OrderItem(productId: 'curd', quantity: 1),
            ],
          ),
          testOrder(
            'eggs',
            deliveryDate: _d(0),
            status: OrderStatus.cancelled,
            amountPaise: 12000,
            items: const [OrderItem(productId: 'eggs', quantity: 1)],
          ),
        ],
      ),
    };
    await pump(tester);

    expect(find.text("Today's Delivery"), findsOneWidget);
    expect(find.text('3 Items'), findsOneWidget);
    expect(find.text('Order total ₹155'), findsOneWidget);
    expect(find.text('Order Placed'), findsNWidgets(2));
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('₹120'), findsOneWidget); // single-item order shows its amount
    expect(find.text('Pure Cow Milk'), findsOneWidget);
    expect(find.byKey(const Key('orders.today.card.multi.1')), findsOneWidget);
  });

  testWidgets('upcoming merges a scheduled subscription with a marked estimate', (tester) async {
    orders.pages = {
      null: OrdersPage(items: [testOrder('tmr', deliveryDate: _d(1), amountPaise: 45000)]),
    };
    subs.subscriptions = [
      SubscriptionView(
        id: 'sub_1',
        productId: 'cow-milk',
        quantity: 2,
        schedule: const Schedule(type: ScheduleType.daily),
        status: SubscriptionStatus.active,
        nextDeliveryDate: _d(2),
      ),
    ];
    await pump(tester);

    expect(find.text('Tomorrow, 2 Oct'), findsOneWidget);
    expect(find.text('₹450 Total'), findsOneWidget);
    expect(find.text('Sat, 3 Oct'), findsOneWidget);
    expect(find.text('Pure Cow Milk (Subscription)'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('≈ ₹130 est.'), findsOneWidget);
    expect(find.text('≈ ₹130 Total'), findsOneWidget);
  });

  testWidgets('a past confirmed order never says Delivered', (tester) async {
    orders.pages = {
      null: OrdersPage(items: [testOrder('old', deliveryDate: _d(-1))]),
    };
    await pump(tester);
    await tester.tap(find.text('Past Orders'));
    await tester.pumpAndSettle();
    expect(find.text('Yesterday, 30 Sep'), findsOneWidget);
    expect(find.textContaining('Delivered'), findsNothing);
  });

  testWidgets('tapping rows pushes the order and scheduled detail routes', (tester) async {
    orders.pages = {
      null: OrdersPage(items: [testOrder('ord_1', deliveryDate: _d(1))]),
    };
    subs.subscriptions = [
      SubscriptionView(
        id: 'sub_1',
        productId: 'cow-milk',
        quantity: 1,
        schedule: const Schedule(type: ScheduleType.daily),
        status: SubscriptionStatus.active,
        nextDeliveryDate: _d(3),
      ),
    ];
    await pump(tester);
    await tester.tap(find.byKey(const Key('orders.row.ord_1')));
    await tester.pumpAndSettle();
    expect(pushed.last, '/orders/ord_1');

    GoRouter.of(tester.element(find.textContaining('stub'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('orders.row.scheduled.sub_1')));
    await tester.pumpAndSettle();
    expect(pushed.last, '/orders/scheduled/sub_1');
  });

  testWidgets('empty states when every source loaded; Browse products → /catalog', (tester) async {
    await pump(tester);
    expect(find.text('No deliveries today'), findsOneWidget);
    expect(find.text('No upcoming deliveries'), findsOneWidget);
    await tester.tap(find.text('Browse products'));
    await tester.pumpAndSettle();
    expect(pushed.last, '/catalog');
  });

  testWidgets('Past Orders empty state', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Past Orders'));
    await tester.pumpAndSettle();
    expect(find.text('No past orders yet'), findsOneWidget);
  });

  testWidgets('orders failure: banner and "couldn\'t load" texts, never empty states', (
    tester,
  ) async {
    orders.listException = _boom;
    await pump(tester);
    expect(find.text("Some orders couldn't be loaded."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text("Couldn't load today's deliveries."), findsOneWidget);
    expect(find.text('No deliveries today'), findsNothing);
    expect(find.text("Couldn't load upcoming orders."), findsOneWidget);
    await tester.tap(find.text('Past Orders'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load past orders."), findsOneWidget);
    expect(find.text('No past orders yet'), findsNothing);
  });

  testWidgets('both sources failed → full-screen error with Retry', (tester) async {
    orders.listException = _boom;
    subs.listException = _boom;
    await pump(tester);
    expect(find.text("Couldn't load your orders."), findsOneWidget);
    orders.listException = null;
    subs.listException = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text("Today's Delivery"), findsOneWidget);
  });

  testWidgets('opening Past Orders with few days loaded fetches the next page', (tester) async {
    orders.pages = {
      null: OrdersPage(items: [testOrder('p1', deliveryDate: _d(-1))], nextCursor: 'c2'),
      'c2': OrdersPage(items: [testOrder('p2', deliveryDate: _d(-8))]),
    };
    await pump(tester);
    await tester.tap(find.text('Past Orders'));
    await tester.pumpAndSettle();
    expect(orders.listCursors, contains('c2'));
    expect(find.byKey(Key('orders.group.2026-09-23')), findsOneWidget);
  });

  testWidgets('a FAILED order is struck through and left out of the day total', (tester) async {
    orders.pages = {
      null: OrdersPage(
        items: [
          testOrder('ok', deliveryDate: _d(1), amountPaise: 45000),
          testOrder('bad', deliveryDate: _d(1), status: OrderStatus.failed, amountPaise: 12000),
        ],
      ),
    };
    await pump(tester);

    expect(find.text('₹450 Total'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    final amount = tester.widget<Text>(
      find.descendant(of: find.byKey(const Key('orders.row.bad')), matching: find.text('₹120')),
    );
    expect(amount.style?.decoration, TextDecoration.lineThrough);
  });
}
