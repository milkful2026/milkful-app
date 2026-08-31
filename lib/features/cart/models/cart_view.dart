import 'package:equatable/equatable.dart';

import 'cart_line_item.dart';
import 'quote.dart';

/// `GET /cart`'s response shape (`serialize_cart_view`) and `PUT /cart`'s
/// (`serialize_cart`) — the latter never carries a `quote` key at all
/// (Cart Service's own documented split: writes don't return pricing, only
/// `GET /cart` does), so [quote] is `null` both when the key is absent and
/// when it's explicitly `null` (an empty cart, per `get_cart_handler.py`).
class CartView extends Equatable {
  const CartView({required this.items, required this.cartVersion, this.quote});

  final List<CartLineItem> items;
  final int cartVersion;
  final Quote? quote;

  factory CartView.fromJson(Map<String, dynamic> json) {
    final quoteJson = json['quote'] as Map<String, dynamic>?;
    return CartView(
      items: (json['items'] as List<dynamic>)
          .map((item) => CartLineItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      cartVersion: json['cartVersion'] as int,
      quote: quoteJson != null ? Quote.fromJson(quoteJson) : null,
    );
  }

  @override
  List<Object?> get props => [items, cartVersion, quote];
}
