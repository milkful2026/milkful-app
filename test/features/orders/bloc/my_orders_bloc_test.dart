import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/catalog/models/product.dart';
import 'package:milkful_app/features/orders/bloc/my_orders_bloc.dart';
import 'package:milkful_app/features/orders/bloc/my_orders_event.dart';
import 'package:milkful_app/features/orders/bloc/my_orders_state.dart';
import 'package:milkful_app/features/orders/models/order_summary.dart';
import 'package:milkful_app/features/orders/models/orders_page.dart';
import 'package:milkful_app/features/subscriptions/models/schedule.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_status.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_view.dart';

import '../../../fakes/fake_catalog_repository.dart';
import '../../../fakes/fake_order_repository.dart';
import '../../../fakes/fake_subscription_repository.dart';

// 2026-10-01 10:00 IST.
DateTime _clock() => DateTime.utc(2026, 10, 1, 4, 30);
final _today = DateTime(2026, 10, 1);
DateTime _d(int offset) => _today.add(Duration(days: offset));

const _boom = ApiException(errorCode: 'SERVICE_UNAVAILABLE', message: 'down', statusCode: 503);

const _milk = Product(
  id: 'cow-milk',
  categoryId: 'milk',
  name: 'Cow Milk',
  description: '',
  unit: '1L',
  price: 65,
  stockState: StockState.inStock,
);

final _sub = SubscriptionView(
  id: 'sub_1',
  productId: 'cow-milk',
  quantity: 1,
  schedule: const Schedule(type: ScheduleType.daily),
  status: SubscriptionStatus.active,
  nextDeliveryDate: _d(2),
);

void main() {
  late FakeOrderRepository orders;
  late FakeSubscriptionRepository subs;
  late FakeCatalogRepository catalog;

  setUp(() {
    orders = FakeOrderRepository(
      pages: {
        null: OrdersPage(
          items: [
            testOrder('today', deliveryDate: _d(0)),
            testOrder('tomorrow', deliveryDate: _d(1)),
            testOrder('past', deliveryDate: _d(-1)),
          ],
          nextCursor: 'c2',
        ),
        'c2': OrdersPage(items: [testOrder('older', deliveryDate: _d(-5))]),
      },
    );
    subs = FakeSubscriptionRepository(subscriptions: [_sub]);
    catalog = FakeCatalogRepository(productsById: {'cow-milk': _milk});
  });

  MyOrdersBloc build() => MyOrdersBloc(
    orderRepository: orders,
    subscriptionRepository: subs,
    catalogRepository: catalog,
    clock: _clock,
  );

  Future<MyOrdersState> settle(MyOrdersBloc bloc) async {
    await Future<void>.delayed(Duration.zero);
    await pumpEventQueue();
    return bloc.state;
  }

  test('opened → both sources loaded, bucketed against IST today, scheduled merged', () async {
    final bloc = build()..add(const MyOrdersOpened());
    final s = await settle(bloc);
    expect(s.ordersStatus, SourceStatus.loaded);
    expect(s.subscriptionsStatus, SourceStatus.loaded);
    expect(s.today, _today);
    expect(s.buckets.today.single.orderId, 'today');
    expect(s.upcomingGroups.map((g) => g.date), [_d(1), _d(2)]);
    expect(s.pastGroups.single.date, _d(-1));
    expect(s.products['cow-milk'], _milk);
    await bloc.close();
  });

  test('orders fail, subscriptions load → partial; retry reloads orders only', () async {
    orders.listException = _boom;
    final bloc = build()..add(const MyOrdersOpened());
    var s = await settle(bloc);
    expect(s.ordersStatus, SourceStatus.failed);
    expect(s.subscriptionsStatus, SourceStatus.loaded);
    expect(s.scheduled, hasLength(1));

    orders.listException = null;
    bloc.add(const RetryFailedSources());
    s = await settle(bloc);
    expect(s.ordersStatus, SourceStatus.loaded);
    expect(orders.listCursors, [null, null]);
    expect(subs.listCalls, 1); // subscriptions had loaded, so not re-fetched
    await bloc.close();
  });

  test('both fail → bothFailed; retry → loaded', () async {
    orders.listException = _boom;
    subs.listException = _boom;
    final bloc = build()..add(const MyOrdersOpened());
    expect((await settle(bloc)).bothFailed, isTrue);
    orders.listException = null;
    subs.listException = null;
    bloc.add(const RetryFailedSources());
    final s = await settle(bloc);
    expect((s.ordersStatus, s.subscriptionsStatus), (SourceStatus.loaded, SourceStatus.loaded));
    await bloc.close();
  });

  test('product cache: one Catalog call per distinct product across refreshes', () async {
    final bloc = build()..add(const MyOrdersOpened());
    await settle(bloc);
    bloc.add(MyOrdersRefreshed());
    await settle(bloc);
    expect(catalog.requestedProductIds.where((id) => id == 'cow-milk'), hasLength(1));
    await bloc.close();
  });

  test('failed product lookup is cached as null, never fails the screen', () async {
    catalog.getProductException = _boom;
    final bloc = build()..add(const MyOrdersOpened());
    final s = await settle(bloc);
    expect(s.products.containsKey('cow-milk'), isTrue);
    expect(s.products['cow-milk'], isNull);
    expect(s.ordersStatus, SourceStatus.loaded);
    await bloc.close();
  });

  test('PastPageRequested appends the next page and clears the cursor', () async {
    final bloc = build()..add(const MyOrdersOpened());
    await settle(bloc);
    bloc.add(const PastPageRequested());
    final s = await settle(bloc);
    expect(s.orders.map((o) => o.orderId), contains('older'));
    expect(s.nextCursor, isNull);
    expect(s.pagingStatus, PagingStatus.idle);
    await bloc.close();
  });

  test('a second page request while one is in flight is dropped', () async {
    orders.pageGate = Completer<void>();
    final bloc = build()..add(const MyOrdersOpened());
    await settle(bloc);
    bloc
      ..add(const PastPageRequested())
      ..add(const PastPageRequested());
    await settle(bloc);
    orders.pageGate!.complete();
    await settle(bloc);
    expect(orders.listCursors.where((c) => c == 'c2'), hasLength(1));
    await bloc.close();
  });

  test('a page failure keeps the loaded orders and sets pagingStatus failed', () async {
    orders.pageException = _boom;
    final bloc = build()..add(const MyOrdersOpened());
    await settle(bloc);
    bloc.add(const PastPageRequested());
    final s = await settle(bloc);
    expect(s.pagingStatus, PagingStatus.failed);
    expect(s.orders, hasLength(3));
    expect(s.nextCursor, 'c2');
    await bloc.close();
  });

  test('a refresh during an in-flight page discards the stale page', () async {
    orders.pageGate = Completer<void>();
    final bloc = build()..add(const MyOrdersOpened());
    await settle(bloc);
    bloc.add(const PastPageRequested());
    await settle(bloc);
    bloc.add(MyOrdersRefreshed());
    await settle(bloc);
    orders.pageGate!.complete();
    final s = await settle(bloc);
    expect(s.orders.map((o) => o.orderId), isNot(contains('older')));
    await bloc.close();
  });

  test('a page request while a refresh is in flight is ignored', () async {
    final bloc = build()..add(const MyOrdersOpened());
    await settle(bloc);
    orders.firstPageGate = Completer<void>();
    orders.pages = {
      null: OrdersPage(items: [testOrder('fresh', deliveryDate: _d(-1))], nextCursor: 'c3'),
      'c2': OrdersPage(items: [testOrder('older', deliveryDate: _d(-5))]),
    };
    final refresh = MyOrdersRefreshed();
    bloc.add(refresh);
    await settle(bloc);
    bloc.add(const PastPageRequested()); // would use the old cursor c2
    await settle(bloc);
    orders.firstPageGate!.complete();
    await refresh.completer.future;
    final s = await settle(bloc);
    expect(orders.listCursors, isNot(contains('c2')));
    expect(s.orders.map((o) => o.orderId), ['fresh']);
    expect(s.nextCursor, 'c3');
    await bloc.close();
  });

  test('retrying failed orders sets them back to loading while in flight', () async {
    orders.listException = _boom;
    final bloc = build()..add(const MyOrdersOpened());
    await settle(bloc);
    orders.listException = null;
    orders.firstPageGate = Completer<void>();
    bloc.add(const RetryFailedSources());
    var s = await settle(bloc);
    expect(s.ordersStatus, SourceStatus.loading);
    orders.firstPageGate!.complete();
    s = await settle(bloc);
    expect(s.ordersStatus, SourceStatus.loaded);
    await bloc.close();
  });

  test('a failed refresh keeps the data and bumps refreshFailedCount', () async {
    final bloc = build()..add(const MyOrdersOpened());
    await settle(bloc);
    orders.listException = _boom;
    final refresh = MyOrdersRefreshed();
    bloc.add(refresh);
    await refresh.completer.future;
    final s = await settle(bloc);
    expect(s.refreshFailedCount, 1);
    expect(s.ordersStatus, SourceStatus.loaded);
    expect(s.orders, hasLength(3));
    await bloc.close();
  });

  test('duplicate order ids across pages are shown once', () async {
    orders.pages['c2'] = OrdersPage(items: [testOrder('past', deliveryDate: _d(-1))]);
    final bloc = build()..add(const MyOrdersOpened());
    await settle(bloc);
    bloc.add(const PastPageRequested());
    final s = await settle(bloc);
    expect(s.orders.where((o) => o.orderId == 'past'), hasLength(1));
    expect(s.orders.first.status, OrderStatus.confirmed);
    await bloc.close();
  });
}
