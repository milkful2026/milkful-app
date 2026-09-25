import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../models/checkout_result.dart';

/// MA-136/MA-137 — Order Service's `POST /orders/checkout`. Throws
/// [ApiException] for every non-2xx outcome; the caller maps it with
/// `CheckoutFailure.fromApiException`.
abstract class CheckoutRepository {
  /// [idempotencyKey] is minted and persisted by the caller before the
  /// first attempt and reused for every retry of the same Confirm — the
  /// server resumes a checkout by it and never charges twice.
  Future<CheckoutResult> checkout({
    required int cartVersion,
    required int expectedPayNowPaise,
    required String idempotencyKey,
  });
}

class DioCheckoutRepository implements CheckoutRepository {
  DioCheckoutRepository(this._client);

  final ApiClient _client;

  @override
  Future<CheckoutResult> checkout({
    required int cartVersion,
    required int expectedPayNowPaise,
    required String idempotencyKey,
  }) async {
    final data = await _client.request(
      'POST',
      '${AppConfig.orderBaseUrl}/orders/checkout',
      headers: {'Idempotency-Key': idempotencyKey},
      body: {'cartVersion': cartVersion, 'expectedPayNowPaise': expectedPayNowPaise},
    );
    return CheckoutResult.fromJson(data);
  }
}
