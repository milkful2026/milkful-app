import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../models/frequency.dart';
import '../models/quote.dart';

/// MA-101/MA-122 FR-1. Calls Pricing & Offer Service directly — this
/// screen's live price estimate is a separate caller from Cart Service's
/// own internal use of the same endpoint (MA-96/MA-121 §6), not routed
/// through Cart Service.
///
/// [deliveryState] is nullable to represent "not yet resolved" (see MA-23
/// impl plan §2.1/§4A). The null-check that fails a quote closed with
/// [deliveryStateUnknownErrorCode] lives in `ProductConfigBloc`, not here
/// — it's a UI-flow correctness rule ("don't ask for a price without a
/// state"), not an HTTP-client concern, so it must hold for every
/// implementation of this interface (including fakes in tests), not just
/// [DioPricingRepository].
abstract class PricingRepository {
  /// [offerCode] is always `null` from this screen today — no offer/coupon
  /// UX exists anywhere in this app (MA-120 §3 out of scope) — kept on the
  /// signature only so the request shape matches MA-101/MA-122's contract.
  Future<Quote> quote({
    required String productId,
    required int quantity,
    required Frequency frequency,
    required String? deliveryState,
    String? offerCode,
  });

  static const deliveryStateUnknownErrorCode = 'DELIVERY_STATE_UNKNOWN';
}

class DioPricingRepository implements PricingRepository {
  DioPricingRepository(this._client);

  final ApiClient _client;

  @override
  Future<Quote> quote({
    required String productId,
    required int quantity,
    required Frequency frequency,
    required String? deliveryState,
    String? offerCode,
  }) async {
    final data = await _client.request(
      'POST',
      '${AppConfig.pricingBaseUrl}/pricing/quote',
      body: {
        'items': [
          {
            'productId': productId,
            'quantity': quantity,
            'frequency': frequency.wireValue,
          },
        ],
        'deliveryState': deliveryState,
        'offerCode': ?offerCode,
      },
    );
    return Quote.fromJson(data);
  }
}
