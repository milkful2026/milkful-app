import 'package:milkful_app/features/cart/data/cart_repository.dart';
import 'package:milkful_app/features/cart/models/frequency.dart';

class FakeAddItemRequest {
  FakeAddItemRequest({
    required this.productId,
    required this.quantity,
    required this.frequency,
    required this.idempotencyKey,
    required this.startDate,
  });

  final String productId;
  final int quantity;
  final Frequency frequency;
  final String idempotencyKey;
  final DateTime? startDate;
}

class FakeCartRepository implements CartRepository {
  FakeCartRepository({this.addItemException});

  Object? addItemException;

  final List<FakeAddItemRequest> requests = [];

  @override
  Future<void> addItem({
    required String productId,
    required int quantity,
    required Frequency frequency,
    required String idempotencyKey,
    DateTime? startDate,
  }) async {
    requests.add(
      FakeAddItemRequest(
        productId: productId,
        quantity: quantity,
        frequency: frequency,
        idempotencyKey: idempotencyKey,
        startDate: startDate,
      ),
    );
    if (addItemException != null) throw addItemException!;
  }
}
