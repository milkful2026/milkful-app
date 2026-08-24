import 'package:equatable/equatable.dart';

/// MA-101/MA-122 FR-1's `POST /pricing/quote` response shape, as merged
/// (including that spec's own PR #9 review fix: [monthlyEstimate] is
/// tax/delivery/discount-inclusive, computed from the same per-delivery
/// [netPayable] this model already carries — never unit price alone).
class Quote extends Equatable {
  const Quote({
    required this.basePrice,
    required this.taxAmount,
    required this.taxRate,
    required this.deliveryFee,
    required this.netPayable,
    this.monthlyEstimate,
    this.discountAmount,
    this.appliedOfferId,
  });

  final double basePrice;
  final double taxAmount;
  final double taxRate;
  final double deliveryFee;
  final double netPayable;

  /// Present only for a subscription-frequency quote (MA-101 FR-1).
  final double? monthlyEstimate;

  final double? discountAmount;
  final String? appliedOfferId;

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
    basePrice: (json['basePrice'] as num).toDouble(),
    taxAmount: (json['taxAmount'] as num).toDouble(),
    taxRate: (json['taxRate'] as num).toDouble(),
    deliveryFee: (json['deliveryFee'] as num).toDouble(),
    netPayable: (json['netPayable'] as num).toDouble(),
    monthlyEstimate: (json['monthlyEstimate'] as num?)?.toDouble(),
    discountAmount: (json['discountAmount'] as num?)?.toDouble(),
    appliedOfferId: json['appliedOfferId'] as String?,
  );

  @override
  List<Object?> get props => [
    basePrice,
    taxAmount,
    taxRate,
    deliveryFee,
    netPayable,
    monthlyEstimate,
    discountAmount,
    appliedOfferId,
  ];
}
