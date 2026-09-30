import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/catalog/models/product.dart';
import 'package:milkful_app/features/orders/bloc/order_detail_cubit.dart';
import 'package:milkful_app/features/orders/bloc/scheduled_delivery_cubit.dart';
import 'package:milkful_app/features/orders/models/order_entry.dart';
import 'package:milkful_app/features/orders/models/order_summary.dart';
import 'package:milkful_app/features/orders/models/orders_page.dart';
import 'package:milkful_app/features/subscriptions/models/schedule.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_status.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_view.dart';

import '../../../fakes/fake_catalog_repository.dart';
import '../../../fakes/fake_order_repository.dart';
import '../../../fakes/fake_subscription_repository.dart';

DateTime _clock() => DateTime.utc(2026, 10, 1, 4, 30); // 10:00 IST
final _today = DateTime(2026, 10, 1);
DateTime _d(int offset) => _today.add(Duration(days: offset));

const _milk = Product(
  id: 'cow-milk',
  categoryId: 'milk',
  name: 'Cow Milk',
  description: '',
  unit: '1L',
  price: 65,
  stockState: StockState.inStock,
);

SubscriptionView _sub({SubscriptionStatus status = SubscriptionStatus.active, DateTime? next}) =>
    SubscriptionView(
      id: 'sub_1',
      productId: 'cow-milk',
      quantity: 2,
      schedule: const Schedule(type: ScheduleType.daily),
      status: status,
      nextDeliveryDate: next,
    );

void main() {
  group('OrderDetailCubit', () {
    late FakeOrderRepository orders;
    late FakeCatalogRepository catalog;

    setUp(() {
      orders = FakeOrderRepository(byId: {'ord_1': testOrder('ord_1', deliveryDate: _d(1))});
      catalog = FakeCatalogRepository(productsById: {'cow-milk': _milk});
    });

    OrderDetailCubit build(String id) =>
        OrderDetailCubit(orderRepository: orders, catalogRepository: catalog, orderId: id);

    test('loads the order and its products', () async {
      final cubit = build('ord_1');
      await cubit.load();
      final s = cubit.state as OrderDetailLoaded;
      expect(s.order.orderId, 'ord_1');
      expect(s.products['cow-milk'], _milk);
      await cubit.close();
    });

    test('404 → not found', () async {
      final cubit = build('ord_missing');
      await cubit.load();
      expect(cubit.state, isA<OrderDetailNotFound>());
      await cubit.close();
    });

    test('500 → error; load again → loaded', () async {
      orders.getException = const ApiException(
        errorCode: 'SERVICE_UNAVAILABLE',
        message: 'down',
        statusCode: 503,
      );
      final cubit = build('ord_1');
      await cubit.load();
      expect(cubit.state, isA<OrderDetailError>());
      orders.getException = null;
      await cubit.load();
      expect(cubit.state, isA<OrderDetailLoaded>());
      await cubit.close();
    });

    test('a failed product lookup still loads, with a null product', () async {
      catalog.getProductException = Exception('catalog down');
      final cubit = build('ord_1');
      await cubit.load();
      final s = cubit.state as OrderDetailLoaded;
      expect(s.products.containsKey('cow-milk'), isTrue);
      expect(s.products['cow-milk'], isNull);
      await cubit.close();
    });
  });

  group('ScheduledDeliveryCubit', () {
    late FakeSubscriptionRepository subs;
    late FakeOrderRepository orders;
    late FakeCatalogRepository catalog;

    setUp(() {
      subs = FakeSubscriptionRepository(subscriptions: [_sub(next: _d(2))]);
      orders = FakeOrderRepository();
      catalog = FakeCatalogRepository(productsById: {'cow-milk': _milk});
    });

    ScheduledDeliveryCubit build({ScheduledEntry? initial}) => ScheduledDeliveryCubit(
      subscriptionRepository: subs,
      orderRepository: orders,
      catalogRepository: catalog,
      subscriptionId: 'sub_1',
      initial: initial,
      clock: _clock,
    );

    final entry = ScheduledEntry(
      subscriptionId: 'sub_1',
      productId: 'cow-milk',
      quantity: 2,
      date: _d(2),
    );

    test('with an initial entry: loaded with no subscription call', () async {
      final cubit = build(initial: entry);
      await cubit.load();
      final s = cubit.state as ScheduledDeliveryLoaded;
      expect(s.entry, entry);
      expect(s.product, _milk);
      expect(subs.getCalls, isEmpty);
      await cubit.close();
    });

    test('without an entry: fetched by id, no change flag, no orders lookup', () async {
      final cubit = build();
      await cubit.load();
      final s = cubit.state as ScheduledDeliveryLoaded;
      expect(s.entry.date, _d(2));
      expect(s.change, isA<NoChange>());
      expect(subs.getCalls, ['sub_1']);
      expect(orders.listCursors, isEmpty);
      await cubit.close();
    });

    test('STOPPED or no next delivery → gone; PAUSED with a future date → loaded', () async {
      subs.subscriptions = [_sub(status: SubscriptionStatus.stopped, next: _d(2))];
      var cubit = build();
      await cubit.load();
      expect(cubit.state, isA<ScheduledDeliveryGone>());
      await cubit.close();

      subs.subscriptions = [_sub()];
      cubit = build();
      await cubit.load();
      expect(cubit.state, isA<ScheduledDeliveryGone>());
      await cubit.close();

      subs.subscriptions = [_sub(status: SubscriptionStatus.paused, next: _d(3))];
      cubit = build();
      await cubit.load();
      expect(cubit.state, isA<ScheduledDeliveryLoaded>());
      await cubit.close();
    });

    test('refresh: date moved and an order exists for the shown date → becameOrder', () async {
      final cubit = build(initial: entry);
      await cubit.load();
      subs.subscriptions = [_sub(next: _d(3))];
      orders.pages = {
        null: OrdersPage(
          items: [
            testOrder(
              'ord_9',
              deliveryDate: _d(2),
              subscriptionId: 'sub_1',
              source: OrderSource.subscription,
            ),
          ],
        ),
      };
      await cubit.refresh();
      final s = cubit.state as ScheduledDeliveryLoaded;
      expect(s.entry.date, _d(3));
      expect(s.change, const BecameOrder('ord_9'));
      await cubit.close();
    });

    test('refresh: date moved with no such order → dateChanged, never becameOrder', () async {
      final cubit = build(initial: entry);
      await cubit.load();
      subs.subscriptions = [_sub(next: _d(4))];
      await cubit.refresh();
      expect((cubit.state as ScheduledDeliveryLoaded).change, isA<DateChanged>());
      await cubit.close();
    });

    test('refresh: the orders lookup fails → dateChanged', () async {
      final cubit = build(initial: entry);
      await cubit.load();
      subs.subscriptions = [_sub(next: _d(4))];
      orders.listException = Exception('order service down');
      await cubit.refresh();
      expect((cubit.state as ScheduledDeliveryLoaded).change, isA<DateChanged>());
      await cubit.close();
    });
  });
}
