import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/subscriptions/data/subscription_repository.dart';
import 'package:milkful_app/features/subscriptions/models/schedule.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_status.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_view.dart';

/// Configurable list/create/action results, matching
/// `FakeWalletRepository`'s established shape.
class FakeSubscriptionRepository implements SubscriptionRepository {
  FakeSubscriptionRepository({
    List<SubscriptionView>? subscriptions,
    this.listException,
    this.createResult,
    this.createException,
    this.actionException,
    this.editEffectiveFrom,
  }) : subscriptions = subscriptions ?? [];

  List<SubscriptionView> subscriptions;
  ApiException? listException;

  SubscriptionView? createResult;
  ApiException? createException;

  /// Applies to pause/resume/stop/skip/edit alike — tests needing a
  /// specific action to fail set this right before that call.
  ApiException? actionException;
  DateTime? editEffectiveFrom;

  final List<String> pauseCalls = [];
  final List<String> resumeCalls = [];
  final List<String> stopCalls = [];
  final List<String> skipCalls = [];
  final List<String> editCalls = [];
  Map<String, dynamic>? lastCreateRequest;

  @override
  Future<List<SubscriptionView>> list() async {
    if (listException != null) throw listException!;
    return subscriptions;
  }

  @override
  Future<SubscriptionView> create({
    required String productId,
    required int quantity,
    required Schedule schedule,
    required DateTime startDate,
    required String slotId,
    required String idempotencyKey,
  }) async {
    lastCreateRequest = {
      'productId': productId,
      'quantity': quantity,
      'schedule': schedule,
      'startDate': startDate,
      'slotId': slotId,
      'idempotencyKey': idempotencyKey,
    };
    if (createException != null) throw createException!;
    return createResult ??
        SubscriptionView(
          id: 'sub-1',
          productId: productId,
          quantity: quantity,
          schedule: schedule,
          status: SubscriptionStatus.active,
        );
  }

  @override
  Future<void> pause(String id, {DateTime? from, DateTime? until}) async {
    pauseCalls.add(id);
    if (actionException != null) throw actionException!;
  }

  @override
  Future<void> resume(String id) async {
    resumeCalls.add(id);
    if (actionException != null) throw actionException!;
  }

  @override
  Future<void> stop(String id) async {
    stopCalls.add(id);
    if (actionException != null) throw actionException!;
  }

  @override
  Future<void> skip(String id, DateTime date) async {
    skipCalls.add(id);
    if (actionException != null) throw actionException!;
  }

  @override
  Future<DateTime?> edit(String id, {int? quantity, Schedule? schedule}) async {
    editCalls.add(id);
    if (actionException != null) throw actionException!;
    return editEffectiveFrom;
  }
}
