import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

import '../../../fakes/fake_catalog_repository.dart';
import '../../../fakes/fake_order_repository.dart';
import '../../../fakes/fake_subscription_repository.dart';

DateTime _clock() => DateTime.utc(2026, 10, 1, 4, 30); // 10:00 IST
final _today = DateTime(2026, 10, 1);
DateTime _d(int offset) => _today.add(Duration(days: offset));

Product _p(String id, String name, double price) => Product(
  id: id,
  categoryId: 'c',
  name: name,
  description: '',
  unit: '500ml',
  price: price,
  stockState: StockState.inStock,
);

void main() {
  late FakeOrderRepository orders;
  late FakeSubscriptionRepository subs;
  late FakeCatalogRepository catalog;
  late List<String> visited;

  setUp(() {
    orders = FakeOrderRepository();
    subs = FakeSubscriptionRepository();
    catalog = FakeCatalogRepository(
      productsById: {
        'spinach': _p('spinach', 'Organic Spinach', 25),
        'eggs': _p('eggs', 'Farm Fresh Eggs', 80),
        'cow-milk': _p('cow-milk', 'Pure Cow Milk', 65),
      },
    );
    visited = [];
  });

  Future<GoRouter> pump(WidgetTester tester, String location, {Object? extra}) async {
    // Tall enough that every card of the detail screens is built.
    tester.view.physicalSize = const Size(1080, 3200);
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
        GoRoute(path: '/subscriptions', builder: (_, s) => stub(s)),
        GoRoute(
          path: '/orders/scheduled/:id',
          builder: (_, s) => ScheduledDeliveryScreen(
            subscriptionId: s.pathParameters['id']!,
            entry: s.extra is ScheduledEntry ? s.extra as ScheduledEntry : null,
            clock: _clock,
          ),
        ),
        GoRoute(
          path: '/orders/:id',
          builder: (_, s) => OrderDetailScreen(orderId: s.pathParameters['id']!),
        ),
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
    router.push(location, extra: extra);
    await tester.pumpAndSettle();
    return router;
  }

  group('OrderDetailScreen', () {
    testWidgets('confirmed checkout order: truthful sections only', (tester) async {
      orders.byId['ord_3f9a2c1b77'] = testOrder(
        'ord_3f9a2c1b77',
        deliveryDate: DateTime(2026, 10, 3),
        amountPaise: 15500,
        createdAt: DateTime.utc(2026, 10, 1, 10),
        items: const [
          OrderItem(productId: 'spinach', quantity: 2),
          OrderItem(productId: 'eggs', quantity: 1),
        ],
      );
      await pump(tester, '/orders/ord_3f9a2c1b77');

      expect(find.text('Order Details'), findsOneWidget);
      expect(find.text('#3F9A2C1B'), findsOneWidget);
      expect(find.text('1 Oct 2026'), findsOneWidget);
      expect(find.text('Order Placed'), findsOneWidget);
      expect(find.text('Organic Spinach'), findsOneWidget);
      expect(find.text('2 × 500ml'), findsOneWidget);
      expect(find.text('Grand Total'), findsOneWidget);
      expect(find.text('₹155.00'), findsOneWidget);
      expect(find.text('Delivery date'), findsOneWidget);
      expect(find.text('Sat, 3 Oct 2026'), findsOneWidget);
      expect(find.text('Milkful Wallet'), findsOneWidget);
      for (final absent in ['Delivered', 'Download Invoice', 'Reorder Items', 'Leave Feedback']) {
        expect(find.textContaining(absent), findsNothing, reason: absent);
      }
    });

    testWidgets('cancelled at the cut-off: not charged, copy says so', (tester) async {
      orders.byId['ord_c'] = testOrder(
        'ord_c',
        deliveryDate: _d(1),
        status: OrderStatus.cancelled,
        failureReason: 'CUTOFF_PASSED',
      );
      await pump(tester, '/orders/ord_c');
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.textContaining("You weren't charged."), findsOneWidget);
      expect(find.text('Not charged'), findsOneWidget);
    });

    testWidgets('under review (SWEEP_EXHAUSTED): never claims not charged', (tester) async {
      orders.byId['ord_r'] = testOrder(
        'ord_r',
        deliveryDate: _d(1),
        status: OrderStatus.needsAttention,
        failureReason: 'SWEEP_EXHAUSTED',
      );
      await pump(tester, '/orders/ord_r');
      expect(find.text('Under Review'), findsOneWidget);
      expect(find.textContaining("won't be charged twice"), findsOneWidget);
      expect(find.text('Charge under review'), findsOneWidget);
      expect(find.textContaining("You weren't charged"), findsNothing);
    });

    testWidgets('under review (CUTOFF_PASSED): proven not charged', (tester) async {
      orders.byId['ord_n'] = testOrder(
        'ord_n',
        deliveryDate: _d(1),
        status: OrderStatus.needsAttention,
        failureReason: 'CUTOFF_PASSED',
      );
      await pump(tester, '/orders/ord_n');
      expect(find.text('Under Review'), findsOneWidget);
      expect(find.textContaining("You weren't charged."), findsOneWidget);
      expect(find.text('Not charged'), findsOneWidget);
      expect(find.text('Charge under review'), findsNothing);
    });

    testWidgets('payment failed before pricing: amount shows —', (tester) async {
      orders.byId['ord_p'] = testOrder(
        'ord_p',
        deliveryDate: _d(1),
        status: OrderStatus.paymentFailed,
        failureReason: 'DELIVERY_ADDRESS_UNKNOWN',
        amountPaise: 0,
      );
      await pump(tester, '/orders/ord_p');
      expect(find.text('Payment Failed'), findsOneWidget);
      expect(find.textContaining('delivery address'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('404 → Order not found; Back to My Orders pops', (tester) async {
      await pump(tester, '/orders/ord_missing');
      expect(find.text('Order not found'), findsOneWidget);
      await tester.tap(find.text('Back to My Orders'));
      await tester.pumpAndSettle();
      expect(find.text('stub /start'), findsOneWidget);
    });

    testWidgets('long-press copies the full order id', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      orders.byId['ord_3f9a2c1b77'] = testOrder('ord_3f9a2c1b77', deliveryDate: _d(1));
      await pump(tester, '/orders/ord_3f9a2c1b77');
      await tester.longPress(find.byKey(const Key('orderDetail.orderId')));
      await tester.pumpAndSettle();
      final setData = calls.where((c) => c.method == 'Clipboard.setData').toList();
      expect(setData, hasLength(1), reason: 'platform calls: ${calls.map((c) => c.method)}');
      expect((setData.single.arguments as Map)['text'], 'ord_3f9a2c1b77');
      expect(find.text('Order ID copied'), findsOneWidget);
    });
  });

  group('ScheduledDeliveryScreen', () {
    final entry = ScheduledEntry(
      subscriptionId: 'sub_1',
      productId: 'cow-milk',
      quantity: 2,
      date: _d(2),
    );

    SubscriptionView sub(DateTime next) => SubscriptionView(
      id: 'sub_1',
      productId: 'cow-milk',
      quantity: 2,
      schedule: const Schedule(type: ScheduleType.daily),
      status: SubscriptionStatus.active,
      nextDeliveryDate: next,
    );

    testWidgets('shows the estimate and links to Manage subscription', (tester) async {
      await pump(tester, '/orders/scheduled/sub_1', extra: entry);
      expect(find.text('SCHEDULED DELIVERY'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.text('Estimated Total'), findsOneWidget);
      expect(find.text('≈ ₹130.00'), findsOneWidget);
      expect(find.textContaining('confirmed the evening before'), findsOneWidget);
      await tester.tap(find.text('Manage subscription'));
      await tester.pumpAndSettle();
      expect(visited.last, '/subscriptions');
    });

    testWidgets('refresh after it became an order offers View order', (tester) async {
      subs.subscriptions = [sub(_d(3))];
      orders.pages = {
        null: OrdersPage(
          items: [testOrder('ord_9', deliveryDate: _d(2), subscriptionId: 'sub_1')],
        ),
      };
      orders.byId['ord_9'] = testOrder('ord_9', deliveryDate: _d(2), subscriptionId: 'sub_1');
      await pump(tester, '/orders/scheduled/sub_1', extra: entry);

      await tester.fling(find.byType(ListView), const Offset(0, 1500), 1000);
      await tester.pumpAndSettle();
      expect(find.text('This delivery is now an order.'), findsOneWidget);
      await tester.tap(find.text('View order'));
      await tester.pumpAndSettle();
      expect(find.text('Order Placed'), findsOneWidget); // now on /orders/ord_9
    });

    testWidgets('refresh after a skip elsewhere says the next delivery changed', (tester) async {
      subs.subscriptions = [sub(_d(4))];
      await pump(tester, '/orders/scheduled/sub_1', extra: entry);
      await tester.fling(find.byType(ListView), const Offset(0, 1500), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Your next delivery has changed.'), findsOneWidget);
      expect(find.text('This delivery is now an order.'), findsNothing);
    });
  });
}
