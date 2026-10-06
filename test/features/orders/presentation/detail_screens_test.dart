import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../../fakes/fake_cart_repository.dart';
import '../../../fakes/fake_catalog_repository.dart';
import '../../../fakes/fake_order_repository.dart';
import '../../../fakes/fake_subscription_repository.dart';

DateTime _clock() => DateTime.utc(2026, 10, 1, 4, 30); // 10:00 IST
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

/// MA-152 FR-2 — records `mailto:` launches instead of opening a mail app.
class _FakeUrlLauncher extends Fake with MockPlatformInterfaceMixin implements UrlLauncherPlatform {
  bool canLaunchResult = true;
  final List<String> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => canLaunchResult;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

void main() {
  late FakeOrderRepository orders;
  late FakeSubscriptionRepository subs;
  late FakeCatalogRepository catalog;
  late FakeCartRepository cart;
  late _FakeUrlLauncher launcher;
  late List<String> visited;

  setUp(() {
    cart = FakeCartRepository();
    launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
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

  /// [deepLink] opens [location] with nothing beneath it (a deep link or
  /// app restart), instead of pushing it over `/start`.
  Future<GoRouter> pump(
    WidgetTester tester,
    String location, {
    Object? extra,
    bool deepLink = false,
  }) async {
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
        GoRoute(path: '/orders', builder: (_, s) => stub(s)),
        GoRoute(path: '/cart', builder: (_, s) => stub(s)),
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
          RepositoryProvider<CartRepository>.value(value: cart),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    if (deepLink) {
      router.go(location, extra: extra);
    } else {
      router.push(location, extra: extra);
    }
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
      for (final absent in ['Delivered', 'Download Invoice', 'Leave Feedback']) {
        expect(find.textContaining(absent), findsNothing, reason: absent);
      }
    });

    /// A loaded two-line order (spinach x2, eggs x1) — MA-152's fixture.
    Future<void> pumpTwoLineOrder(WidgetTester tester) async {
      orders.byId['ord_3f9a2c1b77'] = testOrder(
        'ord_3f9a2c1b77',
        deliveryDate: DateTime(2026, 10, 3),
        items: const [
          OrderItem(productId: 'spinach', quantity: 2),
          OrderItem(productId: 'eggs', quantity: 1),
        ],
      );
      await pump(tester, '/orders/ord_3f9a2c1b77');
    }

    FilledButton reorderButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byKey(const Key('orderDetail.reorder')));

    testWidgets('MA-152: Reorder — busy while in flight, then "View Cart" opens the cart', (
      tester,
    ) async {
      cart.addItemGate = Completer<void>();
      await pumpTwoLineOrder(tester);
      expect(find.text('Reorder Items'), findsOneWidget);

      await tester.tap(find.byKey(const Key('orderDetail.reorder')));
      await tester.pump();
      expect(reorderButton(tester).onPressed, isNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('orderDetail.reorder')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      final support = tester.widget<OutlinedButton>(find.byKey(const Key('orderDetail.support')));
      expect(support.onPressed, isNotNull);

      cart.addItemGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Added 2 items to cart'), findsOneWidget);
      expect(reorderButton(tester).onPressed, isNotNull);
      await tester.tap(find.text('View Cart'));
      await tester.pumpAndSettle();
      expect(find.text('stub /cart'), findsOneWidget);
    });

    testWidgets('MA-152: Reorder — a partial failure names the product, still offers the cart', (
      tester,
    ) async {
      cart.addItemExceptionsByProduct['eggs'] = _boom;
      await pumpTwoLineOrder(tester);
      await tester.tap(find.byKey(const Key('orderDetail.reorder')));
      await tester.pumpAndSettle();
      expect(
        find.text("Added 1 of 2 items to cart. Couldn't add Farm Fresh Eggs."),
        findsOneWidget,
      );
      expect(find.text('View Cart'), findsOneWidget);
    });

    testWidgets('MA-152: Reorder — a full failure has no "View Cart"', (tester) async {
      cart.addItemException = _boom;
      await pumpTwoLineOrder(tester);
      await tester.tap(find.byKey(const Key('orderDetail.reorder')));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't add items to cart. Try again."), findsOneWidget);
      expect(find.text('View Cart'), findsNothing);
    });

    testWidgets('MA-152: Support opens mailto with the display ID only', (tester) async {
      await pumpTwoLineOrder(tester);
      await tester.tap(find.byKey(const Key('orderDetail.support')));
      await tester.pumpAndSettle();
      expect(launcher.launched, ['mailto:support@milkful.app?subject=Order%203F9A2C1B']);
    });

    testWidgets('MA-152: Support with no mail app shows the address instead', (tester) async {
      launcher.canLaunchResult = false;
      await pumpTwoLineOrder(tester);
      await tester.tap(find.byKey(const Key('orderDetail.support')));
      await tester.pumpAndSettle();
      expect(launcher.launched, isEmpty);
      expect(find.text('No email app found. Contact us at support@milkful.app.'), findsOneWidget);
    });

    testWidgets('MA-152: no actions unless the order loaded', (tester) async {
      orders.getException = _boom;
      await pump(tester, '/orders/ord_x');
      expect(find.text("Couldn't load this order."), findsOneWidget);
      expect(find.byKey(const Key('orderDetail.reorder')), findsNothing);
      expect(find.byKey(const Key('orderDetail.support')), findsNothing);
    });

    testWidgets('MA-152: no actions on a not-found order', (tester) async {
      await pump(tester, '/orders/ord_missing');
      expect(find.text('Order not found'), findsOneWidget);
      expect(find.byKey(const Key('orderDetail.reorder')), findsNothing);
      expect(find.byKey(const Key('orderDetail.support')), findsNothing);
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

    testWidgets('deep-linked 404: Back to My Orders goes to /orders', (tester) async {
      await pump(tester, '/orders/ord_missing', deepLink: true);
      expect(find.text('Order not found'), findsOneWidget);
      await tester.tap(find.text('Back to My Orders'));
      await tester.pumpAndSettle();
      expect(find.text('stub /orders'), findsOneWidget);
    });

    testWidgets('a failed refresh keeps the order and shows a SnackBar', (tester) async {
      orders.byId = {'ord_1': testOrder('ord_1', deliveryDate: _d(1))};
      await pump(tester, '/orders/ord_1');
      expect(find.text('Grand Total'), findsOneWidget);
      orders.getException = _boom;
      await tester.fling(find.byType(ListView), const Offset(0, 1500), 1000);
      await tester.pumpAndSettle();
      expect(find.text("Couldn't refresh. Try again."), findsOneWidget);
      expect(find.text('Grand Total'), findsOneWidget);
      expect(find.text("Couldn't load this order."), findsNothing);
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

    testWidgets('deep-linked and no longer scheduled: Back to My Orders goes to /orders', (
      tester,
    ) async {
      subs.subscriptions = [
        SubscriptionView(
          id: 'sub_1',
          productId: 'cow-milk',
          quantity: 2,
          schedule: const Schedule(type: ScheduleType.daily),
          status: SubscriptionStatus.stopped,
        ),
      ];
      await pump(tester, '/orders/scheduled/sub_1', deepLink: true);
      expect(find.text('This delivery is no longer scheduled.'), findsOneWidget);
      await tester.tap(find.text('Back to My Orders'));
      await tester.pumpAndSettle();
      expect(find.text('stub /orders'), findsOneWidget);
    });

    testWidgets('a failed fetch shows Retry, and Retry loads it', (tester) async {
      subs.subscriptions = [sub(_d(2))];
      subs.getException = const ApiException(errorCode: 'X', message: 'down', statusCode: 503);
      await pump(tester, '/orders/scheduled/sub_1'); // no extra: fetched by id
      expect(find.text("Couldn't load this delivery."), findsOneWidget);
      subs.getException = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('SCHEDULED DELIVERY'), findsOneWidget);
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
