import '../../../core/network/api_client.dart';

/// MA-120 FR-7's wallet-balance-≥-₹500 gate. **No real implementation
/// exists** — Wallet Service (MA-100) isn't built (not even spec'd, see
/// the MA-23 impl plan §2). [ProductConfigBloc] depends on this
/// abstraction only, so wiring a real implementation later (once MA-100
/// exists and its actual contract is known) is a contained change (one new
/// file + swapping [StubWalletBalanceRepository] for it in `main.dart`),
/// not a rewrite.
abstract class WalletBalanceRepository {
  /// Balance in rupees (whole units — the ₹500 threshold has no paise
  /// granularity in MA-120 FR-7).
  Future<int> getBalance();
}

/// Wired in `main.dart` until a real implementation exists. Always fails —
/// there is no endpoint to call — so FR-7's gate fails closed (Subscribe
/// Now stays disabled, "Couldn't check your wallet balance" shown) rather
/// than silently allowing a subscription confirm with an unverified
/// balance. Deliberately not named `Dio...`: this makes no network call at
/// all, unlike [DioCartRepository]/[DioPricingRepository], which call
/// contracts that are at least fully specified even though unimplemented —
/// there is no such contract for Wallet Service to code against yet.
class StubWalletBalanceRepository implements WalletBalanceRepository {
  const StubWalletBalanceRepository();

  @override
  Future<int> getBalance() async {
    throw const ApiException(
      errorCode: 'WALLET_CHECK_UNAVAILABLE',
      message: "Couldn't check your wallet balance — pull to retry",
    );
  }
}
