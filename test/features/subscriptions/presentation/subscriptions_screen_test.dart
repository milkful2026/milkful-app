import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/features/auth/data/profile_repository.dart';
import 'package:milkful_app/features/auth/models/user_profile.dart';
import 'package:milkful_app/features/catalog/data/catalog_repository.dart';
import 'package:milkful_app/features/catalog/models/product.dart';
import 'package:milkful_app/features/onboarding/data/registration_repository.dart';
import 'package:milkful_app/features/subscriptions/data/subscription_repository.dart';
import 'package:milkful_app/features/subscriptions/models/schedule.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_status.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_view.dart';
import 'package:milkful_app/features/subscriptions/presentation/subscriptions_screen.dart';

import '../../../fakes/fake_catalog_repository.dart';
import '../../../fakes/fake_profile_repository.dart';
import '../../../fakes/fake_registration_repository.dart';
import '../../../fakes/fake_subscription_repository.dart';

const _dailySchedule = Schedule(type: ScheduleType.daily);

const _cowMilk = Product(
  id: 'cow-milk',
  categoryId: 'milk',
  name: 'Cow Milk',
  description: 'Farm-fresh',
  unit: '1L Bottle',
  price: 68,
  stockState: StockState.inStock,
  subscriptionEligible: true,
);

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
  late FakeSubscriptionRepository repository;
  late FakeCatalogRepository catalogRepository;
  late FakeProfileRepository profileRepository;
  late FakeRegistrationRepository registrationRepository;

  setUp(() {
    repository = FakeSubscriptionRepository();
    catalogRepository = FakeCatalogRepository(
      productsById: {'cow-milk': _cowMilk},
      searchResults: [_cowMilk],
    );
    profileRepository = FakeProfileRepository(
      profile: const UserProfile(
        userId: 'user-1',
        name: 'Priya Sharma',
        mobile: '+919876543210',
        accountType: 'B2C',
        defaultAddressId: 'addr-1',
        defaultAddressZoneId: 'zone-1',
      ),
    );
    registrationRepository = FakeRegistrationRepository(
      slots: const [DeliverySlot(id: 'morning-6-8', label: 'Morning 6-8 AM')],
    );
  });

  Future<void> pumpSubscriptions(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/subscriptions',
      routes: [
        GoRoute(path: '/subscriptions', builder: (context, state) => const SubscriptionsScreen()),
        GoRoute(path: '/home', builder: (context, state) => const Placeholder()),
        GoRoute(path: '/wallet', builder: (context, state) => const Placeholder()),
        GoRoute(path: '/catalog', builder: (context, state) => const Placeholder()),
      ],
    );
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<SubscriptionRepository>.value(value: repository),
          RepositoryProvider<CatalogRepository>.value(value: catalogRepository),
          RepositoryProvider<ProfileRepository>.value(value: profileRepository),
          RepositoryProvider<RegistrationRepository>.value(value: registrationRepository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Subscriptions screen renders the mocked layout', (tester) async {
    repository.subscriptions = [_sub('sub-1')];

    await pumpSubscriptions(tester);

    expect(find.byKey(const Key('subscriptions-title')), findsOneWidget);
    expect(find.text('1 Active'), findsOneWidget);
    expect(find.byKey(const Key('subscription-card-sub-1')), findsOneWidget);
    expect(find.text('Cow Milk'), findsOneWidget);
    expect(find.text('Quantity: 1 Unit'), findsOneWidget);
    expect(find.text('Delivers Daily'), findsOneWidget);
  });

  testWidgets('No subscriptions shows the empty state', (tester) async {
    await pumpSubscriptions(tester);

    expect(find.byKey(const Key('subscriptions-empty-state')), findsOneWidget);
    // Vacation Mode and the promo CTA still render — MA-133 §9.
    expect(find.byKey(const Key('subscriptions-vacation-toggle')), findsOneWidget);
    expect(find.byKey(const Key('subscriptions-new-product-cta')), findsOneWidget);
  });

  testWidgets('Vacation Mode pauses every active subscription', (tester) async {
    repository.subscriptions = [_sub('sub-1'), _sub('sub-2')];

    await pumpSubscriptions(tester);
    await tester.tap(find.byKey(const Key('subscriptions-vacation-toggle')));
    await tester.pumpAndSettle();

    expect(repository.pauseCalls.toSet(), {'sub-1', 'sub-2'});
  });

  testWidgets(
    'Vacation Mode toggle-off resumes every indefinitely-paused subscription, '
    'even freshly loaded with no prior toggle-on this session',
    (tester) async {
      // Server already reports vacationModeOn == true (both PAUSED, no
      // pauseUntil) — this screen was just opened fresh, nothing was
      // toggled in this session.
      repository.subscriptions = [
        _sub('sub-1', status: SubscriptionStatus.paused),
        _sub('sub-2', status: SubscriptionStatus.paused),
      ];

      await pumpSubscriptions(tester);
      final toggle = tester.widget<Switch>(find.byKey(const Key('subscriptions-vacation-toggle')));
      expect(toggle.value, isTrue, reason: 'server-computed vacationModeOn should already read ON');

      await tester.tap(find.byKey(const Key('subscriptions-vacation-toggle')));
      await tester.pumpAndSettle();

      expect(
        repository.resumeCalls.toSet(),
        {'sub-1', 'sub-2'},
        reason: 'toggle-off must resume the full server-computed aggregate, not a '
            'client-side-tracked subset — this is the exact gap MA-133 FR-3 fixes',
      );
    },
  );

  testWidgets(
    // MA-133 FR-7 — the only reachable path to a WEEKLY/CUSTOM_DAYS
    // subscription, since ProductConfigScreen's own frequency selector
    // (FR-6) only ever produces DAILY/ALTERNATE_DAYS.
    'Custom schedule creates a subscription with the picked product/days/slot '
    'and refreshes the list',
    (tester) async {
      await pumpSubscriptions(tester);

      await tester.tap(find.byKey(const Key('subscriptions-custom-schedule-cta')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('custom-schedule-product-cow-milk')), findsOneWidget);
      await tester.tap(find.byKey(const Key('custom-schedule-product-cow-milk')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('custom-schedule-form')), findsOneWidget);
      // Two days selected -> CUSTOM_DAYS (a single day would read as WEEKLY
      // instead — see custom_schedule_sheet.dart's own comment).
      await tester.tap(find.byKey(const Key('custom-schedule-day-2'))); // Tue
      await tester.tap(find.byKey(const Key('custom-schedule-day-4'))); // Thu
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('custom-schedule-slot-morning-6-8')), findsOneWidget);

      final submitButton = tester.widget<FilledButton>(
        find.byKey(const Key('custom-schedule-submit')),
      );
      expect(submitButton.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('custom-schedule-submit')));
      await tester.pumpAndSettle();

      expect(repository.lastCreateRequest, isNotNull);
      expect(repository.lastCreateRequest!['productId'], 'cow-milk');
      expect(repository.lastCreateRequest!['slotId'], 'morning-6-8');
      final schedule = repository.lastCreateRequest!['schedule'] as Schedule;
      expect(schedule.type, ScheduleType.customDays);
      expect(schedule.daysOfWeek, [2, 4]);
      // The sheet closes and the list refreshes on success.
      expect(find.byKey(const Key('custom-schedule-sheet')), findsNothing);
    },
  );

  testWidgets(
    'Custom schedule: a single selected day creates a WEEKLY subscription',
    (tester) async {
      await pumpSubscriptions(tester);

      await tester.tap(find.byKey(const Key('subscriptions-custom-schedule-cta')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-schedule-product-cow-milk')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-schedule-day-3'))); // Wed
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-schedule-submit')));
      await tester.pumpAndSettle();

      final schedule = repository.lastCreateRequest!['schedule'] as Schedule;
      expect(schedule.type, ScheduleType.weekly);
      expect(schedule.daysOfWeek, [3]);
    },
  );

  testWidgets(
    'Custom schedule: Create is disabled until a day and a slot are both picked',
    (tester) async {
      await pumpSubscriptions(tester);

      await tester.tap(find.byKey(const Key('subscriptions-custom-schedule-cta')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('custom-schedule-product-cow-milk')));
      await tester.pumpAndSettle();

      final submitButton = tester.widget<FilledButton>(
        find.byKey(const Key('custom-schedule-submit')),
      );
      expect(submitButton.onPressed, isNull, reason: 'no day selected yet');
    },
  );
}
