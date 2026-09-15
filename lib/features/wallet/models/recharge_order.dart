import 'package:equatable/equatable.dart';

/// `POST /payments`'s response shape (MA-126 FR-1) — the Razorpay order
/// the app opens its checkout sheet against.
class RechargeOrder extends Equatable {
  const RechargeOrder({
    required this.paymentId,
    required this.razorpayOrderId,
    required this.razorpayKeyId,
    required this.amountPaise,
    required this.currency,
  });

  final String paymentId;
  final String razorpayOrderId;
  final String razorpayKeyId;
  final int amountPaise;
  final String currency;

  factory RechargeOrder.fromJson(Map<String, dynamic> json) => RechargeOrder(
    paymentId: json['paymentId'] as String,
    razorpayOrderId: json['razorpayOrderId'] as String,
    razorpayKeyId: json['razorpayKeyId'] as String,
    amountPaise: json['amountPaise'] as int,
    currency: json['currency'] as String,
  );

  @override
  List<Object?> get props => [paymentId, razorpayOrderId, razorpayKeyId, amountPaise, currency];
}
