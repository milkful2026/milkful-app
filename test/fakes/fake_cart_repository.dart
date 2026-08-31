import 'package:milkful_app/features/cart/data/cart_repository.dart';
import 'package:milkful_app/features/cart/models/cart_line_item.dart';
import 'package:milkful_app/features/cart/models/cart_view.dart';
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

class FakeUpdateItemRequest {
  FakeUpdateItemRequest({required this.items, required this.ifVersion});

  final List<CartLineItem> items;
  final int ifVersion;
}

class FakeCartRepository implements CartRepository {
  FakeCartRepository({
    this.addItemException,
    this.getCartResult,
    this.getCartException,
    this.updateItemResult,
    this.updateItemException,
    this.removeItemException,
  });

  Object? addItemException;
  CartView? getCartResult;
  Object? getCartException;
  CartView? updateItemResult;
  Object? updateItemException;
  Object? removeItemException;

  final List<FakeAddItemRequest> requests = [];
  final List<FakeUpdateItemRequest> updateItemRequests = [];
  final List<String> removeItemRequests = [];
  int getCartCallCount = 0;

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

  @override
  Future<CartView> getCart() async {
    getCartCallCount++;
    if (getCartException != null) throw getCartException!;
    return getCartResult ?? const CartView(items: [], cartVersion: 0);
  }

  @override
  Future<CartView> updateItem({
    required List<CartLineItem> items,
    required int ifVersion,
  }) async {
    updateItemRequests.add(FakeUpdateItemRequest(items: items, ifVersion: ifVersion));
    if (updateItemException != null) throw updateItemException!;
    return updateItemResult ?? CartView(items: items, cartVersion: ifVersion + 1);
  }

  @override
  Future<void> removeItem({required String id}) async {
    removeItemRequests.add(id);
    if (removeItemException != null) throw removeItemException!;
  }
}
