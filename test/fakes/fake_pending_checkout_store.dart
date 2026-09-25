import 'package:milkful_app/features/checkout/data/pending_checkout_store.dart';

class FakePendingCheckoutStore implements PendingCheckoutStore {
  FakePendingCheckoutStore({Map<String, String>? initial}) : keys = {...?initial};

  final Map<String, String> keys;
  final List<String> writes = [];
  int clearCallCount = 0;

  @override
  Future<String?> read(String userId) async => keys[userId];

  @override
  Future<void> write(String userId, String key) async {
    writes.add(key);
    keys[userId] = key;
  }

  @override
  Future<void> clear(String userId) async {
    clearCallCount++;
    keys.remove(userId);
  }
}
