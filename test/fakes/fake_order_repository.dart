import 'dart:async';

import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/orders/data/order_repository.dart';
import 'package:milkful_app/features/orders/models/order_summary.dart';
import 'package:milkful_app/features/orders/models/orders_page.dart';

/// Pages keyed by cursor (`null` = first page). Configure `*Exception`
/// fields to simulate failures; `pageGate` holds a page response open so a
/// test can race it against a refresh.
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

  final List<String?> listCursors = [];
  final List<String> getCalls = [];

  @override
  Future<OrdersPage> listMine({String? cursor, int limit = 50}) async {
    listCursors.add(cursor);
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
);
