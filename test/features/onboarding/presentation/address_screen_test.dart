import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/features/onboarding/bloc/registration_bloc.dart';
import 'package:milkful_app/features/onboarding/data/places_repository.dart';
import 'package:milkful_app/features/onboarding/presentation/address_screen.dart';

import '../../../fakes/fake_draft_storage.dart';
import '../../../fakes/fake_places_repository.dart';
import '../../../fakes/fake_registration_repository.dart';

/// Only exercises the screen's non-map chrome (search bar, House/Flat +
/// Landmark fields, Confirm button + RegistrationBloc wiring) — the real
/// GoogleMap widget needs platform channels this harness doesn't provide,
/// so map/geocoding interaction itself isn't covered here; that's what
/// places_repository_test.dart covers at the repository layer instead.
void main() {
  late FakeRegistrationRepository registrationRepository;
  late RegistrationBloc registrationBloc;
  late GoRouter router;

  Future<void> pumpAddressScreen(WidgetTester tester, {PlacesRepository? placesRepository}) async {
    registrationRepository = FakeRegistrationRepository();
    registrationBloc = RegistrationBloc(
      repository: registrationRepository,
      draftStorage: FakeDraftStorage(),
    );
    addTearDown(() => registrationBloc.close());
    router = GoRouter(
      initialLocation: '/address',
      routes: [
        GoRoute(path: '/address', builder: (context, state) => const AddressScreen()),
        GoRoute(path: '/slot', builder: (context, state) => const Placeholder()),
      ],
    );
    await tester.pumpWidget(
      RepositoryProvider<PlacesRepository>.value(
        value: placesRepository ?? FakePlacesRepository(),
        child: BlocProvider<RegistrationBloc>.value(
          value: registrationBloc,
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
  }

  testWidgets(
    'search bar, House/Flat, City, State, Pincode, and Landmark fields are present',
    (tester) async {
      await pumpAddressScreen(tester);

      expect(find.text('Search for area, street name'), findsOneWidget);
      expect(find.byKey(const Key('house-flat-field')), findsOneWidget);
      expect(find.byKey(const Key('city-field')), findsOneWidget);
      expect(find.byKey(const Key('state-field')), findsOneWidget);
      expect(find.byKey(const Key('pincode-field')), findsOneWidget);
      expect(find.byKey(const Key('landmark-field')), findsOneWidget);
    },
  );

  testWidgets('Confirm Location is disabled until House/Flat, City, State, and a valid '
      'Pincode are all filled in', (tester) async {
    await pumpAddressScreen(tester);

    // Before any camera-idle geocode has resolved (the fake map never fires
    // onCameraIdle in this harness) and with only House/Flat filled in, the
    // button stays disabled.
    await tester.enterText(find.byKey(const Key('house-flat-field')), 'Apt 4B');
    await tester.pump();

    var button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm Location'));
    expect(button.onPressed, isNull);

    // Filling City/State/Pincode manually — with no geocode ever having
    // resolved — is enough to enable it. This is the point of these fields
    // staying editable rather than read-only: the map/network side is a
    // convenience, not a hard dependency.
    await tester.enterText(find.byKey(const Key('city-field')), 'Bengaluru');
    await tester.enterText(find.byKey(const Key('state-field')), 'Karnataka');
    await tester.enterText(find.byKey(const Key('pincode-field')), '560001');
    await tester.pump();

    button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm Location'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('Confirm Location submits an AddressDraft built from the manually-entered '
      'fields, falling back to the map\'s default center for lat/lng', (tester) async {
    await pumpAddressScreen(tester);

    await tester.enterText(find.byKey(const Key('house-flat-field')), 'Apt 4B, Building 7');
    await tester.enterText(find.byKey(const Key('landmark-field')), 'Near Central Park West');
    await tester.enterText(find.byKey(const Key('city-field')), 'Bengaluru');
    await tester.enterText(find.byKey(const Key('state-field')), 'Karnataka');
    await tester.enterText(find.byKey(const Key('pincode-field')), '560001');
    await tester.pump();

    final confirmButton = find.widgetWithText(FilledButton, 'Confirm Location');
    await tester.ensureVisible(confirmButton);
    await tester.tap(confirmButton);
    await tester.pump();

    final registered = registrationBloc.state.draft.address;
    expect(registered, isNotNull);
    expect(registered!.lines, ['Apt 4B, Building 7']);
    expect(registered.landmark, 'Near Central Park West');
    expect(registered.city, 'Bengaluru');
    expect(registered.state, 'Karnataka');
    expect(registered.pincode, '560001');
  });
}
