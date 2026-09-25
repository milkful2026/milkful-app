import 'package:milkful_app/features/checkout/data/pending_checkout_store.dart';

class FakePendingCheckoutStore implements PendingCheckoutStore {
  FakePendingCheckoutStore({Map<String, PendingCheckout>? initial}) : pending = {...?initial};

  final Map<String, PendingCheckout> pending;
  final List<PendingCheckout> writes = [];
  int clearCallCount = 0;

  /// When true, [write] reports failure and stores nothing.
  bool failWrites = false;

  @override
  Future<PendingCheckout?> read(String userId) async => pending[userId];

  @override
  Future<bool> write(String userId, PendingCheckout value) async {
    if (failWrites) return false;
    writes.add(value);
    pending[userId] = value;
    return true;
  }

  @override
  Future<void> clear(String userId) async {
    clearCallCount++;
    pending.remove(userId);
  }
}
