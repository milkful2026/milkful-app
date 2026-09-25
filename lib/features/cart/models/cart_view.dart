import 'package:equatable/equatable.dart';

import 'cart_line_item.dart';
import 'quote.dart';

/// `GET /cart`'s response shape (`serialize_cart_view`) and `PUT /cart`'s
/// (`serialize_cart`) — the latter never carries a `quote` key at all
/// (Cart Service's own documented split: writes don't return pricing, only
/// `GET /cart` does), so [quote] is `null` both when the key is absent and
/// when it's explicitly `null` (an empty cart, per `get_cart_handler.py`).
class CartView extends Equatable {
  const CartView({
    required this.items,
    required this.cartVersion,
    this.quote,
    this.payNowQuote,
    this.perDeliveryQuote,
  });

  final List<CartLineItem> items;
  final int cartVersion;
  final Quote? quote;

  /// MA-135 FR-2 — the review screen's split: one-time lines only (what
  /// Confirm Order charges now) and one delivery of every subscription
  /// line (charged later, per delivery). Each is null when its partition
  /// is empty, and both are null from a Cart Service that predates them.
  final Quote? payNowQuote;
  final Quote? perDeliveryQuote;

  factory CartView.fromJson(Map<String, dynamic> json) {
    final quoteJson = json['quote'] as Map<String, dynamic>?;
    final payNowJson = json['payNowQuote'] as Map<String, dynamic>?;
    final perDeliveryJson = json['perDeliveryQuote'] as Map<String, dynamic>?;
    return CartView(
      items: (json['items'] as List<dynamic>)
          .map((item) => CartLineItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      cartVersion: json['cartVersion'] as int,
      quote: quoteJson != null ? Quote.fromJson(quoteJson) : null,
      payNowQuote: payNowJson != null ? Quote.fromJson(payNowJson) : null,
      perDeliveryQuote: perDeliveryJson != null ? Quote.fromJson(perDeliveryJson) : null,
    );
  }

  @override
  List<Object?> get props => [items, cartVersion, quote, payNowQuote, perDeliveryQuote];
}
