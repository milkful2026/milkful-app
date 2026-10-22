import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../models/order_summary.dart';
import '../models/orders_page.dart';

/// MA-132 FR-3 / MA-136 FR-10 — Order Service's read APIs, plus the
/// customer cancel (MA-154). Throws [ApiException] for every non-2xx outcome.
abstract class OrderRepository {
  /// `GET /orders/me` — newest created first, keyset-paginated.
  Future<OrdersPage> listMine({String? cursor, int limit = 50});

  /// `GET /orders/{id}` — `404 ORDER_NOT_FOUND` for an unknown order or
  /// another user's (existence is never leaked).
  Future<OrderSummary> getById(String orderId);

  /// MA-154 `POST /orders/{id}/cancel` — the cancelled order. A repeat is a
  /// replay (200). `409 CUTOFF_PASSED` / `ORDER_NOT_CANCELLABLE` otherwise.
  Future<OrderSummary> cancel(String orderId, {CancelReason? reason});
}

class DioOrderRepository implements OrderRepository {
  DioOrderRepository(this._client);

  final ApiClient _client;

  @override
  Future<OrdersPage> listMine({String? cursor, int limit = 50}) async {
    final data = await _client.request(
      'GET',
      '${AppConfig.orderBaseUrl}/orders/me',
      queryParameters: {'limit': limit, 'cursor': ?cursor},
    );
    return OrdersPage.fromJson(data);
  }

  @override
  Future<OrderSummary> getById(String orderId) async {
    final data = await _client.request(
      'GET',
      '${AppConfig.orderBaseUrl}/orders/${Uri.encodeComponent(orderId)}',
    );
    return OrderSummary.fromJson(data);
  }

  @override
  Future<OrderSummary> cancel(String orderId, {CancelReason? reason}) async {
    final data = await _client.request(
      'POST',
      '${AppConfig.orderBaseUrl}/orders/${Uri.encodeComponent(orderId)}/cancel',
      body: {'reason': ?reason?.wire},
    );
    return OrderSummary.fromJson(data);
  }
}
