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
    on<AddressSubmitted>(_onAddressSubmitted);
    on<ServiceabilityRetryRequested>(_onServiceabilityRetry);
    on<NameSubmitted>(_onNameSubmitted);
    on<DeliverySlotsRequested>(_onDeliverySlotsRequested);
  }

  final RegistrationRepository _repository;
  final DraftStorage _draftStorage;

  Future<void> _persist(RegistrationDraft draft) => _draftStorage.save(draft);

  // FR-10: resume at the first step with missing required data, not a
  // literal saved "screen index" — simpler and self-healing if a field was
  // cleared between sessions. Emits exactly one *settled* phase (never
  // `checkingServiceability`) so callers awaiting the bloc's stream for a
  // routing decision don't have to filter out transients.
  Future<void> _onDraftRestored(DraftRestored event, Emitter<RegistrationState> emit) async {
    final draft = event.draft;
    if (draft == null || draft.address == null) {
      emit(RegistrationState(draft: draft ?? const RegistrationDraft(), phase: RegistrationPhase.address));
      return;
    }
    if (draft.zoneId == null) {
      // Serviceability was never confirmed for this address — restart there.
      emit(RegistrationState(draft: draft, phase: RegistrationPhase.address));
      return;
    }
    // Address + a confirmed zone but the draft still exists on disk means
    // registration itself never completed (a real success clears it) —
    // resume at the Home screen's inline name prompt.
    emit(RegistrationState(draft: draft, phase: RegistrationPhase.awaitingName));
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
      emit(state.copyWith(draft: draft, phase: RegistrationPhase.awaitingName));
    } on ApiException catch (e) {
      emit(state.copyWith(phase: RegistrationPhase.serviceabilityCheckFailed, errorMessage: e.message));
    } catch (_) {
      // Malformed/unexpected responses (e.g. a bad fromJson cast) must
      // still resolve the pending checking-serviceability spinner state.
      emit(
        state.copyWith(
          phase: RegistrationPhase.serviceabilityCheckFailed,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  /// Terms & Privacy consent is implicit (Welcome screen's own "by
  /// continuing you agree..." footer) — always marked accepted here rather
  /// than gated behind a dedicated consent step. No `preferredSlotId` is
  /// sent either; delivery-slot preference is chosen later, independently,
  /// from Home's own calendar picker (see [DeliverySlotsRequested]) —
  /// registration's own contract already treats that field as optional.
  Future<void> _onNameSubmitted(NameSubmitted event, Emitter<RegistrationState> emit) async {
    final draft = state.draft.copyWith(
      name: event.name,
      termsAccepted: true,
      privacyAccepted: true,
    );
    emit(state.copyWith(draft: draft, phase: RegistrationPhase.submitting));
    try {
      final result = await _repository.register(draft);
      await _draftStorage.clear();
      emit(state.copyWith(draft: draft, phase: RegistrationPhase.success, result: result));
    } on ApiException catch (e) {
      emit(state.copyWith(draft: draft, phase: RegistrationPhase.submitFailed, errorMessage: e.message));
    } catch (_) {
      emit(
        state.copyWith(
          draft: draft,
          phase: RegistrationPhase.submitFailed,
          errorMessage: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  /// Best-effort — Home's own calendar picker shows an empty/error state
  /// on failure rather than this bloc surfacing a dedicated error phase,
  /// since a slot-load failure shouldn't block anything else on Home.
  Future<void> _onDeliverySlotsRequested(
    DeliverySlotsRequested event,
    Emitter<RegistrationState> emit,
  ) async {
    try {
      final slots = await _repository.getDeliverySlots(event.zoneId);
      emit(state.copyWith(availableSlots: slots));
    } catch (_) {
      emit(state.copyWith(availableSlots: const []));
    }
  }
}
