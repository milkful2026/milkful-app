import 'package:equatable/equatable.dart';

import 'frequency.dart';

/// MA-96/MA-121's `LineItem`, as serialized by `serialize_line_item`
/// (`services/cart/src/handlers/dto.py`) — field names match the wire
/// shape exactly.
class CartLineItem extends Equatable {
  const CartLineItem({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.frequency,
    required this.addedAt,
    this.startDate,
  });

  final String id;
  final String productId;
  final int quantity;
  final Frequency frequency;
  final String? startDate;
  final String addedAt;

  factory CartLineItem.fromJson(Map<String, dynamic> json) => CartLineItem(
    id: json['id'] as String,
    productId: json['productId'] as String,
    quantity: json['quantity'] as int,
    frequency: Frequency.fromWire(json['frequency'] as String),
    startDate: json['startDate'] as String?,
    addedAt: json['addedAt'] as String,
  );

  /// Used by `CartRepository.updateItem` — `PUT /cart` (`ReplaceCartItemDto`
  /// in `services/cart/src/handlers/dto.py`) takes the full item list back,
  /// not a per-item patch.
  Map<String, dynamic> toJson() => {
    'id': id,
    'productId': productId,
    'quantity': quantity,
    'frequency': frequency.wireValue,
    'startDate': ?startDate,
  };

  CartLineItem copyWith({int? quantity}) =>
      CartLineItem(
        id: id,
        productId: productId,
        quantity: quantity ?? this.quantity,
        frequency: frequency,
        startDate: startDate,
        addedAt: addedAt,
      );

  @override
  List<Object?> get props => [id, productId, quantity, frequency, startDate, addedAt];
}
