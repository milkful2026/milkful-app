import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/cart/models/frequency.dart';
import 'package:milkful_app/features/catalog/models/product.dart';
import 'package:milkful_app/features/orders/bloc/order_detail_cubit.dart';
import 'package:milkful_app/features/orders/bloc/scheduled_delivery_cubit.dart';
import 'package:milkful_app/features/orders/models/order_entry.dart';
import 'package:milkful_app/features/orders/models/order_summary.dart';
import 'package:milkful_app/features/orders/models/orders_page.dart';
import 'package:milkful_app/features/subscriptions/models/schedule.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_status.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_view.dart';

import '../../../fakes/fake_cart_repository.dart';
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
    late FakeCartRepository cart;

    setUp(() {
      orders = FakeOrderRepository(
        byId: {
          'ord_1': testOrder('ord_1', deliveryDate: _d(1)),
          'ord_2': testOrder(
            'ord_2',
            deliveryDate: _d(1),
            items: const [
              OrderItem(productId: 'cow-milk', quantity: 2),
              OrderItem(productId: 'curd', quantity: 1),
            ],
          ),
        },
      );
      catalog = FakeCatalogRepository(
        productsById: {
          'cow-milk': _milk,
          'curd': const Product(
            id: 'curd',
            categoryId: 'milk',
            name: 'Fresh Curd',
            description: '',
            unit: '500g',
            price: 40,
            stockState: StockState.inStock,
          ),
        },
      );
      cart = FakeCartRepository();
    });

    OrderDetailCubit build(String id) => OrderDetailCubit(
      orderRepository: orders,
      catalogRepository: catalog,
      cartRepository: cart,
      orderId: id,
    );

    Future<OrderDetailCubit> loaded(String id) async {
      final cubit = build(id);
      await cubit.load();
      expect(cubit.state, isA<OrderDetailLoaded>());
      return cubit;
    }

    const conflict = ApiException(errorCode: 'OUT_OF_STOCK', message: 'gone', statusCode: 409);

    test('reorder: every line added as a one-time item, each with its own key', () async {
      final cubit = await loaded('ord_2');
      final result = (await cubit.reorder())!;
      expect((result.added, result.total), (2, 2));
      expect(result.failedNames, isEmpty);
      expect(result.message, 'Added 2 items to cart');
      expect(result.showViewCart, isTrue);
      expect(cart.requests.map((r) => (r.productId, r.quantity)), [('cow-milk', 2), ('curd', 1)]);
      for (final r in cart.requests) {
        expect(r.frequency, Frequency.oneTime);
        expect(r.startDate, isNull);
        expect(r.slotId, isNull);
      }
      expect(cart.requests[0].idempotencyKey, isNot(cart.requests[1].idempotencyKey));
      expect((cubit.state as OrderDetailLoaded).reordering, isFalse);
      await cubit.close();
    });

    test('reorder: one line → singular copy', () async {
      final cubit = await loaded('ord_1');
      expect((await cubit.reorder())!.message, 'Added 1 item to cart');
      await cubit.close();
    });

    test('reorder: a partial failure names the failed product', () async {
      cart.addItemExceptionsByProduct['curd'] = conflict;
      final cubit = await loaded('ord_2');
      final result = (await cubit.reorder())!;
      expect(result.failedNames, ['Fresh Curd']);
      expect(result.message, "Added 1 of 2 items to cart. Couldn't add Fresh Curd.");
      expect(result.showViewCart, isTrue);
      await cubit.close();
    });

    test('reorder: an unresolved product fails as "Item"; a non-API error still counts', () async {
      catalog.productsById.remove('curd');
      cart.addItemExceptionsByProduct['cow-milk'] = TimeoutException('slow');
      cart.addItemExceptionsByProduct['curd'] = conflict;
      final cubit = await loaded('ord_2');
      final result = (await cubit.reorder())!;
      expect(cart.requests, hasLength(2)); // the second line is still attempted
      expect(result.failedNames, ['Cow Milk', 'Item']);
      expect(result.added, 0);
      expect(result.message, "Couldn't add items to cart. Try again.");
      expect(result.showViewCart, isFalse);
      await cubit.close();
    });

    test('reorder: sequential, and a second call while in flight is a no-op', () async {
      cart.addItemGate = Completer<void>();
      final cubit = await loaded('ord_2');
      final first = cubit.reorder();
      await Future<void>.delayed(Duration.zero);
      expect(cart.requests, hasLength(1)); // not fanned out in parallel
      expect((cubit.state as OrderDetailLoaded).reordering, isTrue);
      expect(await cubit.reorder(), isNull);
      cart.addItemGate!.complete();
      expect((await first)!.added, 2);
      expect(cart.requests, hasLength(2));
      expect((cubit.state as OrderDetailLoaded).reordering, isFalse);
      await cubit.close();
    });

    test('reorder: a refresh mid-reorder keeps the button disabled until it ends', () async {
      cart.addItemGate = Completer<void>();
      final cubit = await loaded('ord_2');
      final pending = cubit.reorder();
      await Future<void>.delayed(Duration.zero);
      expect(await cubit.refresh(), isTrue);
      expect((cubit.state as OrderDetailLoaded).reordering, isTrue);
      cart.addItemGate!.complete();
      await pending;
      expect((cubit.state as OrderDetailLoaded).reordering, isFalse);
      await cubit.close();
    });

    test('reorder: nothing to do unless loaded', () async {
      final cubit = build('ord_missing');
      await cubit.load();
      expect(await cubit.reorder(), isNull);
      expect(cart.requests, isEmpty);
      await cubit.close();
    });

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

    test('a failed refresh keeps the loaded order and returns false', () async {
      final cubit = build('ord_1');
      await cubit.load();
      orders.getException = const ApiException(
        errorCode: 'SERVICE_UNAVAILABLE',
        message: 'down',
        statusCode: 503,
      );
      expect(await cubit.refresh(), isFalse);
      expect((cubit.state as OrderDetailLoaded).order.orderId, 'ord_1');
      orders.getException = null;
      expect(await cubit.refresh(), isTrue);
      await cubit.close();
    });

    test('a refresh that finds the order gone → not found', () async {
      final cubit = build('ord_1');
      await cubit.load();
      orders.byId = {};
      expect(await cubit.refresh(), isFalse);
      expect(cubit.state, isA<OrderDetailNotFound>());
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

    test('Retry after a failed refresh fetches instead of reusing the initial entry', () async {
      final cubit = build(initial: entry);
      await cubit.load();
      subs.getException = const ApiException(
        errorCode: 'SERVICE_UNAVAILABLE',
        message: 'down',
        statusCode: 503,
      );
      await cubit.refresh();
      expect(cubit.state, isA<ScheduledDeliveryError>());

      subs.getException = null;
      subs.subscriptions = [_sub(next: _d(3))]; // the date moved meanwhile
      await cubit.load(); // Retry
      final s = cubit.state as ScheduledDeliveryLoaded;
      expect(s.entry.date, _d(3));
      expect(s.change, isA<DateChanged>()); // compared with the d(2) last shown
      expect(subs.getCalls, ['sub_1', 'sub_1']);
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

    test('deep-link fetch failure → error; load again → loaded', () async {
      subs.getException = const ApiException(
        errorCode: 'SERVICE_UNAVAILABLE',
        message: 'down',
        statusCode: 503,
      );
      final cubit = build();
      await cubit.load();
      expect(cubit.state, isA<ScheduledDeliveryError>());
      subs.getException = null;
      await cubit.load();
      expect(cubit.state, isA<ScheduledDeliveryLoaded>());
      await cubit.close();
    });

    test('an unknown subscription (404) → error, not gone', () async {
      subs.subscriptions = [];
      final cubit = build();
      await cubit.load();
      expect(cubit.state, isA<ScheduledDeliveryError>());
      await cubit.close();
    });

    test('refresh failure → error', () async {
      final cubit = build(initial: entry);
      await cubit.load();
      subs.getException = const ApiException(errorCode: 'X', message: 'down');
      await cubit.refresh();
      expect(cubit.state, isA<ScheduledDeliveryError>());
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
