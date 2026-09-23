import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/catalog/models/product.dart';
import 'package:milkful_app/features/subscriptions/bloc/subscription_bloc.dart';
import 'package:milkful_app/features/subscriptions/bloc/subscription_event.dart';
import 'package:milkful_app/features/subscriptions/bloc/subscription_state.dart';
import 'package:milkful_app/features/subscriptions/models/schedule.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_status.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_view.dart';

import '../../../fakes/fake_catalog_repository.dart';
import '../../../fakes/fake_subscription_repository.dart';

const _dailySchedule = Schedule(type: ScheduleType.daily);

SubscriptionView _sub(
  String id, {
  SubscriptionStatus status = SubscriptionStatus.active,
  DateTime? pauseUntil,
}) => SubscriptionView(
  id: id,
  productId: 'cow-milk',
  quantity: 1,
  schedule: _dailySchedule,
  status: status,
  pauseUntil: pauseUntil,
  nextDeliveryDate: DateTime(2026, 9, 23),
);

void main() {
  group('SubscriptionBloc', () {
    late FakeSubscriptionRepository repository;
    late FakeCatalogRepository catalogRepository;

    setUp(() {
      repository = FakeSubscriptionRepository();
      catalogRepository = FakeCatalogRepository(
        productsById: {
          'cow-milk': const Product(
            id: 'cow-milk',
            categoryId: 'milk',
            name: 'Cow Milk',
            description: 'Farm-fresh',
            unit: '1L Bottle',
            price: 68,
            stockState: StockState.inStock,
          ),
        },
      );
    });

    SubscriptionBloc build() =>
        SubscriptionBloc(repository: repository, catalogRepository: catalogRepository);

    blocTest<SubscriptionBloc, SubscriptionsState>(
      'SubscriptionsStarted loads the list and resolves product names',
      build: () {
        repository.subscriptions = [_sub('sub-1')];
        return build();
      },
      act: (bloc) => bloc.add(const SubscriptionsStarted()),
      expect: () => [
        isA<SubscriptionsState>().having((s) => s.loadStatus, 'loadStatus', SubscriptionsLoadStatus.loading),
        isA<SubscriptionsState>()
            .having((s) => s.loadStatus, 'loadStatus', SubscriptionsLoadStatus.loaded)
            .having((s) => s.subscriptions.single.productName, 'productName', 'Cow Milk'),
      ],
    );

    blocTest<SubscriptionBloc, SubscriptionsState>(
      'a load failure surfaces loadStatus.failed with the error message',
      build: () {
        repository.listException = const ApiException(errorCode: 'NETWORK_ERROR', message: 'offline');
        return build();
      },
      act: (bloc) => bloc.add(const SubscriptionsStarted()),
      expect: () => [
        isA<SubscriptionsState>().having((s) => s.loadStatus, 'loadStatus', SubscriptionsLoadStatus.loading),
        isA<SubscriptionsState>()
            .having((s) => s.loadStatus, 'loadStatus', SubscriptionsLoadStatus.failed)
            .having((s) => s.loadErrorMessage, 'loadErrorMessage', 'offline'),
      ],
    );

    blocTest<SubscriptionBloc, SubscriptionsState>(
      'VacationModeToggled(true) pauses every currently-ACTIVE subscription concurrently, '
      'no from/until',
      build: () {
        repository.subscriptions = [_sub('sub-1'), _sub('sub-2')];
        return build();
      },
      act: (bloc) async {
        bloc.add(const SubscriptionsStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        // Simulate the server reflecting both as paused once the refresh
        // after the toggle re-fetches.
        repository.subscriptions = [
          _sub('sub-1', status: SubscriptionStatus.paused),
          _sub('sub-2', status: SubscriptionStatus.paused),
        ];
        bloc.add(const VacationModeToggled(true));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(repository.pauseCalls.toSet(), {'sub-1', 'sub-2'});
        expect(bloc.state.vacationModeOn, isTrue);
      },
    );

    blocTest<SubscriptionBloc, SubscriptionsState>(
      // MA-133 §9/FR-3's own regression test: toggle-off must resume every
      // PAUSED-with-no-pauseUntil subscription — including one seeded
      // directly into that state (a fresh session with no client-tracked
      // pause history, or one paused open-ended via its own detail sheet
      // rather than the toggle) — never scoped to a client-side-tracked
      // subset.
      'VacationModeToggled(false) resumes every currently-PAUSED-with-no-pauseUntil '
      'subscription, including one never toggled on this session',
      build: () {
        repository.subscriptions = [
          _sub('sub-1', status: SubscriptionStatus.paused),
          _sub('sub-2', status: SubscriptionStatus.paused, pauseUntil: DateTime(2026, 10, 1)),
        ];
        return build();
      },
      act: (bloc) async {
        bloc.add(const SubscriptionsStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(bloc.state.vacationModeOn, isFalse, reason: 'sub-2 has a pauseUntil, so not every subscription qualifies');
        repository.subscriptions = [
          _sub('sub-1', status: SubscriptionStatus.active),
          _sub('sub-2', status: SubscriptionStatus.paused, pauseUntil: DateTime(2026, 10, 1)),
        ];
        bloc.add(const VacationModeToggled(false));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        // Only sub-1 qualified (PAUSED, no pauseUntil) — sub-2's bounded
        // pause is untouched by the toggle.
        expect(repository.resumeCalls, ['sub-1']);
      },
    );

    blocTest<SubscriptionBloc, SubscriptionsState>(
      'VacationModeToggled with zero subscriptions is a no-op',
      build: build,
      act: (bloc) async {
        bloc.add(const SubscriptionsStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const VacationModeToggled(true));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(repository.pauseCalls, isEmpty);
        expect(bloc.state.vacationModeOn, isFalse);
      },
    );

    blocTest<SubscriptionBloc, SubscriptionsState>(
      'PauseRequested calls pause with the right id/dates and only updates that '
      "subscription's action status",
      build: () {
        repository.subscriptions = [_sub('sub-1'), _sub('sub-2')];
        return build();
      },
      act: (bloc) async {
        bloc.add(const SubscriptionsStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(PauseRequested('sub-1', from: DateTime(2026, 9, 25), until: DateTime(2026, 9, 30)));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(repository.pauseCalls, ['sub-1']);
        expect(bloc.state.statusFor('sub-1'), ActionStatus.idle);
        expect(bloc.state.statusFor('sub-2'), ActionStatus.idle);
      },
    );

    blocTest<SubscriptionBloc, SubscriptionsState>(
      'ResumeRequested calls resume with the right id',
      build: () {
        repository.subscriptions = [_sub('sub-1', status: SubscriptionStatus.paused)];
        return build();
      },
      act: (bloc) async {
        bloc.add(const SubscriptionsStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const ResumeRequested('sub-1'));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) => expect(repository.resumeCalls, ['sub-1']),
    );

    blocTest<SubscriptionBloc, SubscriptionsState>(
      'StopRequested calls stop with the right id',
      build: () {
        repository.subscriptions = [_sub('sub-1')];
        return build();
      },
      act: (bloc) async {
        bloc.add(const SubscriptionsStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const StopRequested('sub-1'));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) => expect(repository.stopCalls, ['sub-1']),
    );

    blocTest<SubscriptionBloc, SubscriptionsState>(
      'SkipRequested calls skip with the right id/date',
      build: () {
        repository.subscriptions = [_sub('sub-1')];
        return build();
      },
      act: (bloc) async {
        bloc.add(const SubscriptionsStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(SkipRequested('sub-1', DateTime(2026, 9, 23)));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) => expect(repository.skipCalls, ['sub-1']),
    );

    blocTest<SubscriptionBloc, SubscriptionsState>(
      'a CUTOFF_PASSED skip failure surfaces the specific "too late" message',
      build: () {
        repository.subscriptions = [_sub('sub-1')];
        repository.actionException = const ApiException(errorCode: 'CUTOFF_PASSED', message: 'Cut-off has passed');
        return build();
      },
      act: (bloc) async {
        bloc.add(const SubscriptionsStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(SkipRequested('sub-1', DateTime(2026, 9, 23)));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.lastActionMessage?.message, 'Too late to skip this delivery');
        expect(bloc.state.lastActionMessage?.isError, isTrue);
      },
    );

    blocTest<SubscriptionBloc, SubscriptionsState>(
      'EditRequested calls edit with the right id/quantity/schedule',
      build: () {
        repository.subscriptions = [_sub('sub-1')];
        return build();
      },
      act: (bloc) async {
        bloc.add(const SubscriptionsStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const EditRequested('sub-1', quantity: 2));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) => expect(repository.editCalls, ['sub-1']),
    );

    blocTest<SubscriptionBloc, SubscriptionsState>(
      'a repository failure on one action does not affect other subscriptions',
      build: () {
        repository.subscriptions = [_sub('sub-1'), _sub('sub-2')];
        repository.actionException = const ApiException(errorCode: 'NETWORK_ERROR', message: 'offline');
        return build();
      },
      act: (bloc) async {
        bloc.add(const SubscriptionsStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const PauseRequested('sub-1'));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.statusFor('sub-1'), ActionStatus.idle);
        expect(bloc.state.statusFor('sub-2'), ActionStatus.idle);
        expect(bloc.state.lastActionMessage?.subscriptionId, 'sub-1');
        // sub-2's data is untouched — still whatever list() last returned.
        expect(bloc.state.subscriptions.map((s) => s.id), ['sub-1', 'sub-2']);
      },
    );
  });
}
