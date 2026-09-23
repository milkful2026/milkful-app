/// MA-131 §6. Wire values match Subscription Service's `SubscriptionStatus`
/// StrEnum exactly. `CREATING`-style transitional states don't exist on
/// this backend — a subscription is `ACTIVE` the instant `create()`
/// returns (MA-131 FR-1).
enum SubscriptionStatus {
  active,
  paused,
  stopped;

  static SubscriptionStatus fromWire(String value) => switch (value) {
    'ACTIVE' => SubscriptionStatus.active,
    'PAUSED' => SubscriptionStatus.paused,
    'STOPPED' => SubscriptionStatus.stopped,
    _ => throw ArgumentError('Unknown subscription status: $value'),
  };

  String get label => switch (this) {
    SubscriptionStatus.active => 'Active',
    SubscriptionStatus.paused => 'Paused',
    SubscriptionStatus.stopped => 'Stopped',
  };
}
