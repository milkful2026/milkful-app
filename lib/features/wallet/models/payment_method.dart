/// The mock's two Payment Methods options (MA-125 FR-4). Net-banking
/// remains reachable inside Razorpay's own sheet but is not a top-level
/// choice here (MA-125 §3).
enum PaymentMethod {
  upi,
  card;

  String get wireValue => switch (this) {
    PaymentMethod.upi => 'UPI',
    PaymentMethod.card => 'CARD',
  };

  static PaymentMethod fromWire(String value) => switch (value) {
    'UPI' => PaymentMethod.upi,
    'CARD' => PaymentMethod.card,
    _ => throw ArgumentError('Unknown payment method: $value'),
  };
}
