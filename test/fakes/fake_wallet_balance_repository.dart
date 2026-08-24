import 'package:milkful_app/features/cart/data/wallet_balance_repository.dart';

class FakeWalletBalanceRepository implements WalletBalanceRepository {
  FakeWalletBalanceRepository({this.balance = 0, this.getBalanceException});

  int balance;
  Object? getBalanceException;
  int callCount = 0;

  @override
  Future<int> getBalance() async {
    callCount++;
    if (getBalanceException != null) throw getBalanceException!;
    return balance;
  }
}
