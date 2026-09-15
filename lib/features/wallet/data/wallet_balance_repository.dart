/// MA-120 FR-7's wallet-balance-≥-₹500 gate. Moved here from
/// `features/cart/data/` now that a real Wallet Service exists (MA-24) —
/// this is wallet-domain, not cart-domain. [ProductConfigBloc] depends on
/// this abstraction only, so which implementation backs it (previously
/// [StubWalletBalanceRepository], now [DioWalletBalanceRepository]) is an
/// implementation detail of `main.dart`'s wiring.
abstract class WalletBalanceRepository {
  /// Balance in rupees (whole units — the ₹500 threshold has no paise
  /// granularity in MA-120 FR-7).
  Future<int> getBalance();
}
