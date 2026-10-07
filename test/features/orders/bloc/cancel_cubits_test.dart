import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/network/api_client.dart';
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

final _today = DateTime(2026, 10, 1);
DateTime _d(int offset) => _today.add(Duration(days: offset));

ApiException _api(String code) => ApiException(errorCode: code, message: code, statusCode: 409);

void main() {
  group('MA-155 OrderDetailCubit.cancel', () {
    late FakeOrderRepository orders;
    late OrderDetailCubit cubit;

    final confirmed = testOrder(
      'ord_1',
      deliveryDate: _d(2),
      amountPaise: 15500,
      cancellableUntil: DateTime.utc(2026, 10, 2, 14, 30),
    );
    final cancelled = testOrder(
      'ord_1',
      deliveryDate: _d(2),
      amountPaise: 15500,
      status: OrderStatus.cancelled,
      failureReason: 'CUSTOMER_CANCELLED',
      refundState: RefundState.refunded,
      cancelReason: CancelReason.notHome,
    );

    setUp(() async {
      orders = FakeOrderRepository(byId: {'ord_1': confirmed});
      cubit = OrderDetailCubit(
        orderRepository: orders,
        catalogRepository: FakeCatalogRepository(),
        cartRepository: FakeCartRepository(),
        orderId: 'ord_1',
      );
      await cubit.load();
    });

    tearDown(() => cubit.close());

    test('success: sends the reason, shows the returned order, marks the screen changed', () async {
      orders.cancelResult = cancelled;
      final outcome = await cubit.cancel(CancelReason.notHome);
      expect(outcome, CancelOutcome.cancelled);
      expect(orders.cancelCalls, [('ord_1', CancelReason.notHome)]);
      final state = cubit.state as OrderDetailLoaded;
      expect(state.order, cancelled);
      expect(state.cancelling, isFalse);
      expect(cubit.changed, isTrue);
      expect(orders.getCalls, ['ord_1']); // redrawn from the response, no extra GET
    });

    test('cancelling while in flight; a second cancel is a no-op', () async {
      orders.cancelResult = cancelled;
      orders.cancelGate = Completer<void>();
      final first = cubit.cancel(null);
      await Future<void>.delayed(Duration.zero);
      expect((cubit.state as OrderDetailLoaded).cancelling, isTrue);
      expect(await cubit.cancel(CancelReason.other), isNull);
      orders.cancelGate!.complete();
      expect(await first, CancelOutcome.cancelled);
      expect(orders.cancelCalls, [('ord_1', null)]);
    });

    test('CUTOFF_PASSED → cutoffPassed and the order reloaded', () async {
      orders.cancelException = _api('CUTOFF_PASSED');
      expect(await cubit.cancel(null), CancelOutcome.cutoffPassed);
      expect(orders.getCalls, ['ord_1', 'ord_1']);
      expect((cubit.state as OrderDetailLoaded).cancelling, isFalse);
      expect(cubit.changed, isFalse);
    });

    test('ORDER_NOT_CANCELLABLE → notCancellable and the order reloaded', () async {
      orders.cancelException = _api('ORDER_NOT_CANCELLABLE');
      expect(await cubit.cancel(null), CancelOutcome.notCancellable);
      expect(orders.getCalls, ['ord_1', 'ord_1']);
    });

    test('a network or other error → failed, state unchanged', () async {
      orders.cancelException = const ApiException(
        errorCode: 'SERVICE_UNAVAILABLE',
        message: 'down',
        statusCode: 503,
      );
      expect(await cubit.cancel(CancelReason.notHome), CancelOutcome.failed);
      final state = cubit.state as OrderDetailLoaded;
      expect(state.order, confirmed);
      expect(state.cancelling, isFalse);
      orders.cancelException = StateError('socket closed');
      expect(await cubit.cancel(null), CancelOutcome.failed);
    });
  });

  group('MA-155 ScheduledDeliveryCubit.cancelDelivery', () {
    late FakeSubscriptionRepository subs;
    late FakeOrderRepository orders;

    final entry = ScheduledEntry(
      subscriptionId: 'sub_1',
      productId: 'cow-milk',
      quantity: 2,
      date: _d(2), // cut-off: 20:00 IST on 2 Oct = 14:30 UTC
    );

    SubscriptionView sub(DateTime next) => SubscriptionView(
      id: 'sub_1',
      productId: 'cow-milk',
      quantity: 2,
      schedule: const Schedule(type: ScheduleType.daily),
      status: SubscriptionStatus.active,
      nextDeliveryDate: next,
    );

    Future<ScheduledDeliveryCubit> loaded(DateTime now) async {
      final cubit = ScheduledDeliveryCubit(
        subscriptionRepository: subs,
        orderRepository: orders,
        catalogRepository: FakeCatalogRepository(),
        subscriptionId: 'sub_1',
        initial: entry,
        clock: () => now,
      );
      addTearDown(cubit.close);
      await cubit.load();
      return cubit;
    }

    setUp(() {
      subs = FakeSubscriptionRepository(subscriptions: [sub(_d(2))]);
      orders = FakeOrderRepository();
    });

    test('skips the shown date → cancelled', () async {
      final cubit = await loaded(DateTime.utc(2026, 10, 1, 4, 30));
      expect(await cubit.cancelDelivery(), SkipOutcome.cancelled);
      expect(subs.skipCalls, ['sub_1']);
      expect(subs.skipDates, [_d(2)]);
    });

    test('CUTOFF_PASSED before the cut-off → alreadyOrder, and it refreshes', () async {
      final cubit = await loaded(DateTime.utc(2026, 10, 2, 14, 29));
      subs.actionException = _api('CUTOFF_PASSED');
      subs.subscriptions = [sub(_d(3))];
      orders.pages = {
        null: OrdersPage(
          items: [testOrder('ord_9', deliveryDate: _d(2), subscriptionId: 'sub_1')],
        ),
      };
      expect(await cubit.cancelDelivery(), SkipOutcome.alreadyOrder);
      final state = cubit.state as ScheduledDeliveryLoaded;
      expect(state.change, const BecameOrder('ord_9'));
    });

    test('CUTOFF_PASSED at or after the cut-off → cutoffPassed', () async {
      final cubit = await loaded(DateTime.utc(2026, 10, 2, 14, 30));
      subs.actionException = _api('CUTOFF_PASSED');
      expect(await cubit.cancelDelivery(), SkipOutcome.cutoffPassed);
    });

    test('any other error → failed, no refresh', () async {
      final cubit = await loaded(DateTime.utc(2026, 10, 1, 4, 30));
      subs.actionException = _api('DATE_NOT_DUE');
      expect(await cubit.cancelDelivery(), SkipOutcome.failed);
      expect(subs.getCalls, isEmpty);
    });
  });
}
