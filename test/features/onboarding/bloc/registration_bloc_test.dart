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
      'auto-submits registration with implicit consent and no separate '
      'name/slot step, then clears the draft',
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
            .having((s) => s.phase, 'phase', RegistrationPhase.submitting)
            .having((s) => s.draft.zoneId, 'zoneId', 'blr-central'),
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.success)
            .having((s) => s.result?.userId, 'userId', 'user-1')
            .having((s) => s.draft.termsAccepted, 'termsAccepted', isTrue)
            .having((s) => s.draft.privacyAccepted, 'privacyAccepted', isTrue),
      ],
      verify: (_) {
        expect(repository.lastRegistered?.name, isNotNull);
        expect(draftStorage.saved, isNull);
      },
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
            .having((s) => s.phase, 'phase', RegistrationPhase.submitting)
            .having((s) => s.draft.zoneId, 'zoneId', 'z1'),
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.success),
      ],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'a registration submit failure lands on submitFailed with the backend message',
      build: () {
        repository.serviceabilityResult = const ServiceabilityResult(
          serviceable: true,
          zoneId: 'blr-central',
        );
        repository.registerException = const ApiException(
          errorCode: 'NOT_SERVICEABLE',
          message: 'Address is not serviceable',
        );
        return build();
      },
      act: (bloc) => bloc.add(const AddressSubmitted(_address)),
      expect: () => [
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.checkingServiceability),
        isA<RegistrationState>().having((s) => s.phase, 'phase', RegistrationPhase.submitting),
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.submitFailed)
            .having((s) => s.errorMessage, 'message', 'Address is not serviceable'),
      ],
    );

    blocTest<RegistrationBloc, RegistrationState>(
      'RegistrationRetryRequested resubmits after submitFailed without asking for anything',
      build: build,
      seed: () => RegistrationState.initial().copyWith(
        draft: const RegistrationDraft(address: _address, zoneId: 'blr-central'),
        phase: RegistrationPhase.submitFailed,
        errorMessage: 'Address is not serviceable',
      ),
      act: (bloc) => bloc.add(const RegistrationRetryRequested()),
      expect: () => [
        isA<RegistrationState>().having((s) => s.phase, 'phase', RegistrationPhase.submitting),
        isA<RegistrationState>()
            .having((s) => s.phase, 'phase', RegistrationPhase.success)
            .having((s) => s.result?.userId, 'userId', 'user-1'),
      ],
      verify: (_) {
        expect(draftStorage.saved, isNull);
      },
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
      'interrupted before completing) finishes submitting it automatically',
      build: build,
      act: (bloc) => bloc.add(
        const DraftRestored(RegistrationDraft(address: _address, zoneId: 'blr-central')),
      ),
      expect: () => [
        isA<RegistrationState>().having((s) => s.phase, 'phase', RegistrationPhase.submitting),
        isA<RegistrationState>().having((s) => s.phase, 'phase', RegistrationPhase.success),
      ],
    );
  });
}
