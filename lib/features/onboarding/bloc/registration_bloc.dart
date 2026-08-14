import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/draft_storage.dart';
import '../data/registration_repository.dart';
import '../models/registration_draft.dart';
import 'registration_event.dart';
import 'registration_state.dart';

class RegistrationBloc extends Bloc<RegistrationEvent, RegistrationState> {
  RegistrationBloc({
    required RegistrationRepository repository,
    required DraftStorage draftStorage,
  })  : _repository = repository,
        _draftStorage = draftStorage,
        super(RegistrationState.initial()) {
    on<DraftRestored>(_onDraftRestored);
    on<NameSubmitted>(_onNameSubmitted);
    on<AddressSubmitted>(_onAddressSubmitted);
    on<ServiceabilityRetryRequested>(_onServiceabilityRetry);
    on<SlotSelected>(_onSlotSelected);
    on<ConsentUpdated>(_onConsentUpdated);
    on<RegistrationSubmitted>(_onRegistrationSubmitted);
  }

  final RegistrationRepository _repository;
  final DraftStorage _draftStorage;

  Future<void> _persist(RegistrationDraft draft) => _draftStorage.save(draft);

  void _onDraftRestored(DraftRestored event, Emitter<RegistrationState> emit) {
    final draft = event.draft;
    if (draft == null) {
      emit(RegistrationState.initial());
      return;
    }
    // FR-10: resume at the first step with missing required data, not a
    // literal saved "screen index" — simpler and self-healing if a field
    // was cleared between sessions.
    final RegistrationPhase phase;
    if (draft.name == null || draft.name!.isEmpty) {
      phase = RegistrationPhase.name;
    } else if (draft.address == null) {
      phase = RegistrationPhase.address;
    } else if (draft.slotId == null) {
      phase = RegistrationPhase.slot;
    } else {
      phase = RegistrationPhase.consent;
    }
    emit(RegistrationState(draft: draft, phase: phase));
  }

  Future<void> _onNameSubmitted(NameSubmitted event, Emitter<RegistrationState> emit) async {
    final draft = state.draft.copyWith(name: event.name);
    await _persist(draft);
    emit(state.copyWith(draft: draft, phase: RegistrationPhase.address));
  }

  Future<void> _onAddressSubmitted(
    AddressSubmitted event,
    Emitter<RegistrationState> emit,
  ) async {
    final draft = state.draft.copyWith(address: event.address);
    await _persist(draft);
    emit(state.copyWith(draft: draft, phase: RegistrationPhase.checkingServiceability));
    await _checkServiceability(emit);
  }

  Future<void> _onServiceabilityRetry(
    ServiceabilityRetryRequested event,
    Emitter<RegistrationState> emit,
  ) async {
    emit(state.copyWith(phase: RegistrationPhase.checkingServiceability));
    await _checkServiceability(emit);
  }

  Future<void> _checkServiceability(Emitter<RegistrationState> emit) async {
    final address = state.draft.address;
    if (address == null) return;
    try {
      final result = await _repository.checkServiceability(
        pincode: address.pincode,
        lat: address.lat,
        lng: address.lng,
      );
      if (!result.serviceable || result.zoneId == null) {
        emit(
          state.copyWith(
            phase: RegistrationPhase.notServiceable,
            errorMessage: result.message ?? "Sorry, we don't deliver here yet",
          ),
        );
        return;
      }
      final draft = state.draft.copyWith(zoneId: result.zoneId);
      await _persist(draft);
      emit(state.copyWith(draft: draft, phase: RegistrationPhase.loadingSlots));
      await _loadSlots(result.zoneId!, emit);
    } on ApiException catch (e) {
      emit(state.copyWith(phase: RegistrationPhase.serviceabilityCheckFailed, errorMessage: e.message));
    }
  }

  Future<void> _loadSlots(String zoneId, Emitter<RegistrationState> emit) async {
    try {
      final slots = await _repository.getDeliverySlots(zoneId);
      emit(state.copyWith(phase: RegistrationPhase.slot, availableSlots: slots));
    } on ApiException catch (e) {
      emit(state.copyWith(phase: RegistrationPhase.serviceabilityCheckFailed, errorMessage: e.message));
    }
  }

  Future<void> _onSlotSelected(SlotSelected event, Emitter<RegistrationState> emit) async {
    final draft = state.draft.copyWith(slotId: event.slotId);
    await _persist(draft);
    emit(state.copyWith(draft: draft, phase: RegistrationPhase.consent));
  }

  Future<void> _onConsentUpdated(ConsentUpdated event, Emitter<RegistrationState> emit) async {
    final draft = state.draft.copyWith(
      termsAccepted: event.termsAccepted,
      privacyAccepted: event.privacyAccepted,
      pushConsent: event.pushConsent,
    );
    await _persist(draft);
    emit(state.copyWith(draft: draft));
  }

  Future<void> _onRegistrationSubmitted(
    RegistrationSubmitted event,
    Emitter<RegistrationState> emit,
  ) async {
    if (!state.draft.termsAccepted || !state.draft.privacyAccepted) return;
    emit(state.copyWith(phase: RegistrationPhase.submitting));
    try {
      final result = await _repository.register(state.draft);
      await _draftStorage.clear();
      emit(state.copyWith(phase: RegistrationPhase.success, result: result));
    } on ApiException catch (e) {
      emit(state.copyWith(phase: RegistrationPhase.submitFailed, errorMessage: e.message));
    }
  }
}
