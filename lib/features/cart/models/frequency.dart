/// MA-120 FR-2. Wire values match MA-96/MA-121 §7's `frequency` column and
/// MA-101/MA-122 FR-1's request shape exactly.
enum Frequency {
  oneTime,
  daily,
  alternateDays;

  String get wireValue => switch (this) {
    Frequency.oneTime => 'ONE_TIME',
    Frequency.daily => 'DAILY',
    Frequency.alternateDays => 'ALTERNATE_DAYS',
  };

  bool get isSubscription => this != Frequency.oneTime;

  /// No unrecognized-value fallback (unlike [StockState]'s safe default) —
  /// a frequency this app doesn't know about on a request/response it
  /// itself controls the shape of is a real bug, not a forward-compat
  /// scenario worth silently absorbing.
  static Frequency fromWire(String value) => switch (value) {
    'ONE_TIME' => Frequency.oneTime,
    'DAILY' => Frequency.daily,
    'ALTERNATE_DAYS' => Frequency.alternateDays,
    _ => throw ArgumentError('Unknown frequency: $value'),
  };
}
