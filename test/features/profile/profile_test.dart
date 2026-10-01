import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/auth/data/profile_repository.dart';
import 'package:milkful_app/features/auth/models/user_profile.dart';
import 'package:milkful_app/features/profile/bloc/profile_header_cubit.dart';
import 'package:milkful_app/features/profile/presentation/mobile_format.dart';
import 'package:milkful_app/features/profile/presentation/profile_screen.dart';

import '../../fakes/fake_profile_repository.dart';

const _profile = UserProfile(
  userId: 'user-1',
  name: 'Alex Thompson',
  mobile: '9876543210',
  accountType: 'B2C',
  defaultAddressId: 'addr-1',
);

void main() {
  group('formatIndianMobile', () {
    test('formats a 10-digit number with or without the country code', () {
      expect(formatIndianMobile('9876543210'), '+91 98765 43210');
      expect(formatIndianMobile('+919876543210'), '+91 98765 43210');
      expect(formatIndianMobile('919876543210'), '+91 98765 43210');
    });

    test('anything else is shown as stored; empty is hidden', () {
      expect(formatIndianMobile('12345'), '12345');
      expect(formatIndianMobile(''), isNull);
      expect(formatIndianMobile(null), isNull);
    });

    test('initials', () {
      expect(initialsOf('Alex Thompson'), 'AT');
      expect(initialsOf('priya'), 'P');
      expect(initialsOf('  '), '');
    });
  });

  group('ProfileHeaderCubit', () {
    test('loaded; error; load again → loaded', () async {
      final repo = FakeProfileRepository(profile: _profile);
      final cubit = ProfileHeaderCubit(repo);
      await cubit.load();
      expect(cubit.state, const ProfileHeaderLoaded(_profile));

      repo.getMeException = const ApiException(errorCode: 'X', message: 'down');
      await cubit.load();
      expect(cubit.state, isA<ProfileHeaderError>());

      repo.getMeException = null;
      await cubit.load();
      expect(cubit.state, isA<ProfileHeaderLoaded>());
      await cubit.close();
    });
  });

  group('ProfileScreen', () {
    late FakeProfileRepository repo;
    late List<String> visited;

    setUp(() {
      repo = FakeProfileRepository(profile: _profile);
      visited = [];
    });

    Future<void> pump(WidgetTester tester) async {
      Widget stub(GoRouterState s) {
        visited.add(s.uri.toString());
        return Scaffold(body: Text('stub ${s.uri}'));
      }

      final router = GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          for (final path in [
            '/orders',
            '/subscriptions',
            '/wallet/transactions',
            '/home',
            '/wallet',
          ])
            GoRoute(path: path, builder: (_, s) => stub(s)),
        ],
      );
      await tester.pumpWidget(
        RepositoryProvider<ProfileRepository>.value(
          value: repo,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders the header and only the working rows', (tester) async {
      await pump(tester);
      for (final text in [
        'Profile',
        'Alex Thompson',
        '+91 98765 43210',
        'My Subscription',
        'Manage',
        'My Orders',
        'FINANCIALS',
        'Transactions',
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      for (final absent in [
        'Refer & Earn',
        'Offer Zone',
        'Account & Preferences',
      ]) {
        expect(find.text(absent), findsNothing, reason: absent);
      }
    });

    testWidgets('rows navigate', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('profile.row.orders')));
      await tester.pumpAndSettle();
      expect(visited.last, '/orders');

      GoRouter.of(tester.element(find.textContaining('stub'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile.row.transactions')));
      await tester.pumpAndSettle();
      expect(visited.last, '/wallet/transactions');

      GoRouter.of(tester.element(find.textContaining('stub'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile.row.subscription')));
      await tester.pumpAndSettle();
      expect(visited.last, '/subscriptions');
    });

    testWidgets('a header failure never blocks the rows', (tester) async {
      repo.getMeException = const ApiException(errorCode: 'X', message: 'down');
      await pump(tester);
      expect(find.text("Couldn't load your profile"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('My Orders'));
      await tester.pumpAndSettle();
      expect(visited.last, '/orders');
    });

    testWidgets('its own bottom bar: Home, Schedule, Wallet navigate', (
      tester,
    ) async {
      for (final (label, path) in [
        ('Home', '/home'),
        ('Schedule', '/subscriptions'),
        ('Wallet', '/wallet'),
      ]) {
        await pump(tester);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(visited.last, path, reason: label);
      }
    });
  });
}
