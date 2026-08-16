import 'package:equatable/equatable.dart';

/// Mirrors MA-116 FR-1's `stockState` values (`IN_STOCK` | `OUT_OF_STOCK` |
/// `AVAILABLE_FROM`) — see MA-115 FR-3.
enum StockState { inStock, outOfStock, availableFrom }

StockState _stockStateFromJson(String value) => switch (value) {
      'OUT_OF_STOCK' => StockState.outOfStock,
      'AVAILABLE_FROM' => StockState.availableFrom,
      _ => StockState.inStock,
    };

/// MA-115 §7. Shared by category-browse (`GET /products`) and search
/// (`GET /search`) results — MA-117 FR-1 states both return the same shape,
/// so this one model deserializes either.
class Product extends Equatable {
  const Product({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.unit,
    required this.price,
    required this.stockState,
    this.imageUrl,
    this.tag,
    this.subscriptionEligible = false,
    this.availableFrom,
  });

  final String id;
  final String categoryId;
  final String name;
  final String description;
  final String unit;
  final double price;
  final String? imageUrl;
  final String? tag;
  final bool subscriptionEligible;
  final StockState stockState;
  final DateTime? availableFrom;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        categoryId: json['categoryId'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        unit: json['unit'] as String,
        price: (json['price'] as num).toDouble(),
        imageUrl: json['imageUrl'] as String?,
        tag: json['tag'] as String?,
        subscriptionEligible: json['subscriptionEligible'] as bool? ?? false,
        stockState: _stockStateFromJson(json['stockState'] as String? ?? 'IN_STOCK'),
        availableFrom: json['availableFrom'] == null
            ? null
            : DateTime.parse(json['availableFrom'] as String),
      );

  @override
  List<Object?> get props => [
        id,
        categoryId,
        name,
        description,
        unit,
        price,
        imageUrl,
        tag,
        subscriptionEligible,
        stockState,
        availableFrom,
      ];
}
