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
      'NameSubmitted stores the name and advances to the address step',
      build: build,
      act: (bloc) => bloc.add(const NameSubmitted('Priya Sharma')),
      expect: () => [
        isA<RegistrationState>()
            .having((s) => s.draft.name, 'name', 'Priya Sharma')
            .having((s) => s.phase, 'phase', RegistrationPhase.address),
      ],
      verify: (_) => expect(draftStorage.saved?.name, 'Priya Sharma'),
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'AddressSubmitted for a serviceable address loads slots and lands on the slot step',
      build: () {
        repository.serviceabilityResult = const ServiceabilityResult(
          serviceable: true,
          zoneId: 'blr-central',
          zoneName: 'Bangalore Central',
        );
        repository.slots = const [
          DeliverySlot(id: 'morning-6-8', label: 'Morning 6-8 AM', available: true),
        ];
        return build();
      },
      act: (bloc) => bloc.add(const AddressSubmitted(_address)),
      expect: () => [
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.checkingServiceability),
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.loadingSlots)
            .having((s) => s.draft.zoneId, 'zoneId', 'blr-central'),
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.slot)
            .having((s) => s.availableSlots.length, 'slot count', 1),
      ],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'AddressSubmitted for a non-serviceable address lands on notServiceable, not slot',
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
            .having((s) => s.phase, 'phase', RegistrationPhase.loadingSlots),
        isA<RegistrationState>().having((s) => s.phase, 'phase', RegistrationPhase.slot),
      ],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'SlotSelected stores the slot and advances to consent',
      build: build,
      act: (bloc) => bloc.add(const SlotSelected('morning-6-8')),
      expect: () => [
        isA<RegistrationState>()
            .having((s) => s.draft.slotId, 'slotId', 'morning-6-8')
            .having((s) => s.phase, 'phase', RegistrationPhase.consent),
      ],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'RegistrationSubmitted without both mandatory consents is a no-op',
      build: build,
      seed: () => RegistrationState.initial().copyWith(
        draft: const RegistrationDraft(termsAccepted: true, privacyAccepted: false),
        phase: RegistrationPhase.consent,
      ),
      act: (bloc) => bloc.add(const RegistrationSubmitted()),
      expect: () => <RegistrationState>[],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'RegistrationSubmitted with both mandatory consents submits and clears the draft',
      build: build,
      seed: () => RegistrationState.initial().copyWith(
        draft: const RegistrationDraft(
          name: 'Priya Sharma',
          address: _address,
          slotId: 'morning-6-8',
          termsAccepted: true,
          privacyAccepted: true,
        ),
        phase: RegistrationPhase.consent,
      ),
      act: (bloc) => bloc.add(const RegistrationSubmitted()),
      expect: () => [
        isA<RegistrationState>().having((s) => s.phase, 'phase', RegistrationPhase.submitting),
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
      'RegistrationSubmitted failure lands on submitFailed with the backend message',
      build: () {
        repository.registerException = const ApiException(
          errorCode: 'NOT_SERVICEABLE',
          message: 'Address is not serviceable',
        );
        return build();
      },
      seed: () => RegistrationState.initial().copyWith(
        draft: const RegistrationDraft(
          name: 'Priya Sharma',
          address: _address,
          slotId: 'morning-6-8',
          termsAccepted: true,
          privacyAccepted: true,
        ),
        phase: RegistrationPhase.consent,
      ),
      act: (bloc) => bloc.add(const RegistrationSubmitted()),
      expect: () => [
        isA<RegistrationState>().having((s) => s.phase, 'phase', RegistrationPhase.submitting),
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.submitFailed)
            .having((s) => s.errorMessage, 'message', 'Address is not serviceable'),
      ],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'DraftRestored with no saved draft starts fresh at the name step',
      build: build,
      act: (bloc) => bloc.add(const DraftRestored(null)),
      expect: () => [
        isA<RegistrationState>().having((s) => s.phase, 'phase', RegistrationPhase.name),
      ],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'DraftRestored with a partial draft (name only) resumes at the address step',
      build: build,
      act: (bloc) => bloc.add(
        const DraftRestored(RegistrationDraft(name: 'Priya Sharma')),
      ),
      expect: () => [
        isA<RegistrationState>().having((s) => s.phase, 'phase', RegistrationPhase.address),
      ],
    );
  });
}
