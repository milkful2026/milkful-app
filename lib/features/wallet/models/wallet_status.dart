/// Mirrors Wallet Service's `WalletStatus` enum (MA-127 §4) exactly.
enum WalletStatus {
  active,
  creating,
  failed;

  static WalletStatus fromWire(String value) => switch (value) {
    'ACTIVE' => WalletStatus.active,
    'CREATING' => WalletStatus.creating,
    'FAILED' => WalletStatus.failed,
    _ => throw ArgumentError('Unknown wallet status: $value'),
  };
}
