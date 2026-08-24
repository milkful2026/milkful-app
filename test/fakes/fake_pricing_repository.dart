import 'package:milkful_app/features/cart/data/pricing_repository.dart';
import 'package:milkful_app/features/cart/models/frequency.dart';
import 'package:milkful_app/features/cart/models/quote.dart';

class FakeQuoteRequest {
  FakeQuoteRequest({
    required this.productId,
    required this.quantity,
    required this.frequency,
    required this.deliveryState,
    required this.offerCode,
  });

  final String productId;
  final int quantity;
  final Frequency frequency;
  final String? deliveryState;
  final String? offerCode;
}

class FakePricingRepository implements PricingRepository {
  FakePricingRepository({this.quoteException, this.result});

  Object? quoteException;
  Quote? result;

  /// Per-call artificial delay before resolving — lets tests simulate an
  /// earlier, slower request racing a later, faster one (exercises
  /// ProductConfigBloc's `restartable()` handling).
  Duration? delay;

  final List<FakeQuoteRequest> requests = [];

  @override
  Future<Quote> quote({
    required String productId,
    required int quantity,
    required Frequency frequency,
    required String? deliveryState,
    String? offerCode,
  }) async {
    requests.add(
      FakeQuoteRequest(
        productId: productId,
        quantity: quantity,
        frequency: frequency,
        deliveryState: deliveryState,
        offerCode: offerCode,
      ),
    );
    if (delay != null) await Future<void>.delayed(delay!);
    if (quoteException != null) throw quoteException!;
    return result ??
        const Quote(
          basePrice: 0,
          taxAmount: 0,
          taxRate: 0,
          deliveryFee: 0,
          netPayable: 0,
        );
  }
}
