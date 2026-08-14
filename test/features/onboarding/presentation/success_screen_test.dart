import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/features/onboarding/bloc/registration_bloc.dart';
import 'package:milkful_app/features/onboarding/bloc/registration_event.dart';
import 'package:milkful_app/features/onboarding/bloc/registration_state.dart';
import 'package:milkful_app/features/onboarding/data/registration_repository.dart';
import 'package:milkful_app/features/onboarding/models/registration_draft.dart';
import 'package:milkful_app/features/onboarding/presentation/success_screen.dart';

import '../../../fakes/fake_draft_storage.dart';
import '../../../fakes/fake_registration_repository.dart';

const _address = AddressDraft(
  lines: ['12 MG Road'],
  city: 'Bangalore',
  state: 'Karnataka',
  pincode: '560001',
  lat: 12.9716,
  lng: 77.5946,
);

void main() {
  Future<void> pumpSuccess(WidgetTester tester, String walletStatus) async {
    final repository = FakeRegistrationRepository(
      registerResult: RegistrationResult(
        userId: 'user-1',
        walletId: 'wallet-1',
        walletStatus: walletStatus,
        defaultAddressId: 'addr-1',
      ),
    );
    final bloc = RegistrationBloc(repository: repository, draftStorage: FakeDraftStorage());
    addTearDown(() => bloc.close());

    // Drive through real events (DraftRestored to jump straight to a
    // consent-ready draft, then submit) rather than reaching for
    // Bloc.emit, matching this suite's established convention — awaiting
    // the bloc's own stream keeps the two dispatches deterministically
    // ordered instead of racing.
    bloc.add(
      const DraftRestored(
        RegistrationDraft(
          name: 'Priya Sharma',
          address: _address,
          zoneId: 'blr-central',
          slotId: 'morning-6-8',
          termsAccepted: true,
          privacyAccepted: true,
        ),
      ),
    );
    await bloc.stream.firstWhere((s) => s.phase == RegistrationPhase.consent);
    bloc.add(const RegistrationSubmitted());
    await bloc.stream.firstWhere((s) => s.phase == RegistrationPhase.success);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<RegistrationBloc>.value(value: bloc, child: const SuccessScreen()),
      ),
    );
  }

  testWidgets('PENDING wallet status shows the "being set up" message', (tester) async {
    await pumpSuccess(tester, 'PENDING');

    expect(find.text('Your Milkful Wallet is being set up.'), findsOneWidget);
    expect(find.text('Your Milkful Wallet is ready.'), findsNothing);
  });

  testWidgets(
    'FAILED wallet status shows a distinct warning, never the "ready" message',
    (tester) async {
      await pumpSuccess(tester, 'FAILED');

      expect(find.text('Your Milkful Wallet is ready.'), findsNothing);
      expect(
        find.text('Wallet setup incomplete — contact support if this persists.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('ACTIVE wallet status shows the "ready" message', (tester) async {
    await pumpSuccess(tester, 'ACTIVE');

    expect(find.text('Your Milkful Wallet is ready.'), findsOneWidget);
  });
}
