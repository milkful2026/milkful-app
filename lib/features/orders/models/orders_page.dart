import 'order_summary.dart';

/// One keyset page of `GET /orders/me` — newest *created* first;
/// [nextCursor] is null on the last page.
class OrdersPage {
  const OrdersPage({required this.items, this.nextCursor});

  final List<OrderSummary> items;
  final String? nextCursor;

  factory OrdersPage.fromJson(Map<String, dynamic> json) => OrdersPage(
    items: [
      for (final item in (json['items'] as List? ?? const []))
        OrderSummary.fromJson(item as Map<String, dynamic>),
    ],
    nextCursor: json['nextCursor'] as String?,
  );
}
