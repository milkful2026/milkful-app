/// Mirrors Payment Service's `PaymentStatus` enum (MA-126 §4) exactly.
enum PaymentStatus {
  created,
  confirming,
  confirmed,
  failed;

  static PaymentStatus fromWire(String value) => switch (value) {
    'CREATED' => PaymentStatus.created,
    'CONFIRMING' => PaymentStatus.confirming,
    'CONFIRMED' => PaymentStatus.confirmed,
    'FAILED' => PaymentStatus.failed,
    _ => throw ArgumentError('Unknown payment status: $value'),
  };
}
