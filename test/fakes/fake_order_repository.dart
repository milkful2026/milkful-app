import 'dart:async';

import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/orders/data/order_repository.dart';
import 'package:milkful_app/features/orders/models/order_summary.dart';
import 'package:milkful_app/features/orders/models/orders_page.dart';

/// Pages keyed by cursor (`null` = first page). Configure `*Exception`
/// fields to simulate failures; `pageGate` holds a later page's response
/// open (and `firstPageGate` the first page's) so a test can race them.
class FakeOrderRepository implements OrderRepository {
  FakeOrderRepository({Map<String?, OrdersPage>? pages, Map<String, OrderSummary>? byId})
    : pages = pages ?? {null: const OrdersPage(items: [])},
      byId = byId ?? {};

  Map<String?, OrdersPage> pages;
  Map<String, OrderSummary> byId;
  Object? listException;

  /// Failure only for a non-null cursor (later pages).
  Object? pageException;
  Object? getException;
  Completer<void>? pageGate;
  Completer<void>? firstPageGate;
  Completer<void>? getGate;

  final List<String?> listCursors = [];
  final List<String> getCalls = [];

  /// MA-155 — `cancel` returns [cancelResult] (or throws [cancelException]);
  /// [cancelGate] holds it open so a test can see the in-flight state.
  OrderSummary? cancelResult;
  Object? cancelException;
  Completer<void>? cancelGate;
  final List<(String, CancelReason?)> cancelCalls = [];

  @override
  Future<OrdersPage> listMine({String? cursor, int limit = 50}) async {
    listCursors.add(cursor);
    if (cursor == null && firstPageGate != null) await firstPageGate!.future;
    if (cursor == null && listException != null) throw listException!;
    if (cursor != null) {
      if (pageGate != null) await pageGate!.future;
      if (pageException != null) throw pageException!;
    }
    return pages[cursor] ?? const OrdersPage(items: []);
  }

  @override
  Future<OrderSummary> getById(String orderId) async {
    getCalls.add(orderId);
    if (getGate != null) await getGate!.future;
    if (getException != null) throw getException!;
    final order = byId[orderId];
    if (order == null) {
      throw const ApiException(
        errorCode: 'ORDER_NOT_FOUND',
        message: 'No such order',
        statusCode: 404,
      );
    }
    return order;
  }

  @override
  Future<OrderSummary> cancel(String orderId, {CancelReason? reason}) async {
    cancelCalls.add((orderId, reason));
    if (cancelGate != null) await cancelGate!.future;
    if (cancelException != null) throw cancelException!;
    final result = cancelResult;
    if (result == null) throw StateError('FakeOrderRepository.cancelResult not set');
    // Later reads see the cancelled order, as they would from the server.
    byId[orderId] = result;
    return result;
  }
}

OrderSummary testOrder(
  String id, {
  required DateTime deliveryDate,
  OrderStatus status = OrderStatus.confirmed,
  int amountPaise = 6500,
  List<OrderItem> items = const [OrderItem(productId: 'cow-milk', quantity: 1)],
  OrderSource source = OrderSource.checkout,
  String? subscriptionId,
  String? failureReason,
  DateTime? createdAt,
  DateTime? cancellableUntil,
  CancelReason? cancelReason,
  RefundState? refundState,
}) => OrderSummary(
  orderId: id,
  source: source,
  items: items,
  amountPaise: amountPaise,
  deliveryDate: deliveryDate,
  status: status,
  subscriptionId: subscriptionId,
  failureReason: failureReason,
  createdAt: createdAt,
  cancellableUntil: cancellableUntil,
  cancelReason: cancelReason,
  refundState: refundState,
);
