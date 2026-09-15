import 'wallet_balance_repository.dart';
import 'wallet_repository.dart';

/// Preserves MA-120 FR-7's `getBalance() -> Future<int>` whole-rupee
/// contract on top of the real, paise-precise [WalletRepository] — zero
/// change to [ProductConfigBloc]. A [WalletRepository.getWallet] failure
/// propagates as the same [ApiException] the old stub always threw, so
/// MA-120's "couldn't check balance" failure path still works unchanged.
class DioWalletBalanceRepository implements WalletBalanceRepository {
  DioWalletBalanceRepository(this._walletRepository);

  final WalletRepository _walletRepository;

  @override
  Future<int> getBalance() async {
    final wallet = await _walletRepository.getWallet();
    return wallet.balancePaise ~/ 100;
  }
}
