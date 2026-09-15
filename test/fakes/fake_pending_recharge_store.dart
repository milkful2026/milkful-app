import 'package:milkful_app/features/wallet/data/pending_recharge_store.dart';
import 'package:milkful_app/features/wallet/models/pending_recharge.dart';

class FakePendingRechargeStore implements PendingRechargeStore {
  FakePendingRechargeStore({PendingRecharge? initial}) : value = initial;

  PendingRecharge? value;
  int clearCallCount = 0;
  final List<PendingRecharge> writes = [];

  @override
  Future<PendingRecharge?> read() async => value;

  @override
  Future<void> write(PendingRecharge value) async {
    writes.add(value);
    this.value = value;
  }

  @override
  Future<void> clear() async {
    clearCallCount++;
    value = null;
  }
}

class FakePaymentMethodStore implements PaymentMethodStore {
  FakePaymentMethodStore({this.value});

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String wireValue) async {
    value = wireValue;
  }
}
