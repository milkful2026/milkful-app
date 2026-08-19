import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/onboarding/bloc/registration_bloc.dart';
import 'package:milkful_app/features/onboarding/bloc/registration_event.dart';
import 'package:milkful_app/features/onboarding/bloc/registration_state.dart';
import 'package:milkful_app/features/onboarding/data/registration_repository.dart';
import 'package:milkful_app/features/onboarding/models/registration_draft.dart';

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
  group('RegistrationBloc', () {
    late FakeRegistrationRepository repository;
    late FakeDraftStorage draftStorage;

    setUp(() {
      repository = FakeRegistrationRepository();
      draftStorage = FakeDraftStorage();
    });

    RegistrationBloc build() =>
        RegistrationBloc(repository: repository, draftStorage: draftStorage);

    blocTest<RegistrationBloc, RegistrationState>(
      'AddressSubmitted for a serviceable address confirms the zone and '
      'lands on the Home screen\'s awaitingName step (no separate slot step)',
      build: () {
        repository.serviceabilityResult = const ServiceabilityResult(
          serviceable: true,
          zoneId: 'blr-central',
          zoneName: 'Bangalore Central',
        );
        return build();
      },
      act: (bloc) => bloc.add(const AddressSubmitted(_address)),
      expect: () => [
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.checkingServiceability),
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.awaitingName)
            .having((s) => s.draft.zoneId, 'zoneId', 'blr-central'),
      ],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'AddressSubmitted for a non-serviceable address lands on notServiceable',
      build: () {
        repository.serviceabilityResult = const ServiceabilityResult(
          serviceable: false,
          message: "Sorry, we don't deliver here yet",
        );
        return build();
      },
      act: (bloc) => bloc.add(const AddressSubmitted(_address)),
      expect: () => [
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.checkingServiceability),
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.notServiceable)
            .having((s) => s.errorMessage, 'message', "Sorry, we don't deliver here yet"),
      ],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'AddressSubmitted with a network failure lands on serviceabilityCheckFailed, retry recovers',
      build: () {
        repository.serviceabilityException = const ApiException(
          errorCode: 'EXTERNAL_SERVICE_UNAVAILABLE',
          message: 'Service unavailable',
        );
        return build();
      },
      act: (bloc) async {
        bloc.add(const AddressSubmitted(_address));
        await Future<void>.delayed(Duration.zero);
        repository.serviceabilityException = null;
        repository.serviceabilityResult =
            const ServiceabilityResult(serviceable: true, zoneId: 'z1');
        bloc.add(const ServiceabilityRetryRequested());
      },
      expect: () => [
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.checkingServiceability),
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.serviceabilityCheckFailed),
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.checkingServiceability),
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.awaitingName)
            .having((s) => s.draft.zoneId, 'zoneId', 'z1'),
      ],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'NameSubmitted registers with implicit consent (no dedicated consent '
      'step) and no preferredSlotId, then clears the draft',
      build: build,
      seed: () => RegistrationState.initial().copyWith(
        draft: const RegistrationDraft(address: _address, zoneId: 'blr-central'),
        phase: RegistrationPhase.awaitingName,
      ),
      act: (bloc) => bloc.add(const NameSubmitted('Priya Sharma')),
      expect: () => [
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.submitting)
            .having((s) => s.draft.name, 'name', 'Priya Sharma')
            .having((s) => s.draft.termsAccepted, 'termsAccepted', isTrue)
            .having((s) => s.draft.privacyAccepted, 'privacyAccepted', isTrue),
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.success)
            .having((s) => s.result?.userId, 'userId', 'user-1'),
      ],
      verify: (_) {
        expect(repository.lastRegistered?.name, 'Priya Sharma');
        expect(draftStorage.saved, isNull);
      },
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'NameSubmitted failure lands on submitFailed with the backend message',
      build: () {
        repository.registerException = const ApiException(
          errorCode: 'NOT_SERVICEABLE',
          message: 'Address is not serviceable',
        );
        return build();
      },
      seed: () => RegistrationState.initial().copyWith(
        draft: const RegistrationDraft(address: _address, zoneId: 'blr-central'),
        phase: RegistrationPhase.awaitingName,
      ),
      act: (bloc) => bloc.add(const NameSubmitted('Priya Sharma')),
      expect: () => [
        isA<RegistrationState>().having((s) => s.phase, 'phase', RegistrationPhase.submitting),
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.submitFailed)
            .having((s) => s.errorMessage, 'message', 'Address is not serviceable'),
      ],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'DeliverySlotsRequested loads slots for Home\'s calendar picker',
      build: () {
        repository.slots = const [
          DeliverySlot(id: 'morning-6-8', label: 'Morning 6-8 AM'),
        ];
        return build();
      },
      act: (bloc) => bloc.add(const DeliverySlotsRequested('blr-central')),
      expect: () => [
        isA<RegistrationState>().having((s) => s.availableSlots.length, 'slot count', 1),
      ],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'DeliverySlotsRequested failure leaves the picker with an empty list, not a crash',
      build: () {
        repository.slotsException = const ApiException(errorCode: 'BOOM', message: 'boom');
        return build();
      },
      act: (bloc) => bloc.add(const DeliverySlotsRequested('blr-central')),
      expect: () => [
        isA<RegistrationState>().having((s) => s.availableSlots, 'slots', isEmpty),
      ],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'DraftRestored with no saved draft starts fresh at the address step',
      build: build,
      act: (bloc) => bloc.add(const DraftRestored(null)),
      expect: () => [
        isA<RegistrationState>().having((s) => s.phase, 'phase', RegistrationPhase.address),
      ],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'DraftRestored with no address resumes at the address step',
      build: build,
      act: (bloc) => bloc.add(const DraftRestored(RegistrationDraft(mobile: '+919876543210'))),
      expect: () => [
        isA<RegistrationState>().having((s) => s.phase, 'phase', RegistrationPhase.address),
      ],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'DraftRestored with an address but no confirmed zone resumes at the '
      'address step rather than crashing on a null zoneId',
      build: build,
      act: (bloc) => bloc.add(const DraftRestored(RegistrationDraft(address: _address))),
      expect: () => [
        isA<RegistrationState>().having((s) => s.phase, 'phase', RegistrationPhase.address),
      ],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'DraftRestored with an address and a confirmed zone (registration '
      'interrupted before completing) resumes at awaitingName',
      build: build,
      act: (bloc) => bloc.add(
        const DraftRestored(RegistrationDraft(address: _address, zoneId: 'blr-central')),
      ),
      expect: () => [
        isA<RegistrationState>().having((s) => s.phase, 'phase', RegistrationPhase.awaitingName),
      ],
    );
  });
}
