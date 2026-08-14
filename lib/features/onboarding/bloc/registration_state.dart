import 'package:equatable/equatable.dart';

import '../data/registration_repository.dart';
import '../models/registration_draft.dart';

enum RegistrationPhase {
  name,
  address,
  checkingServiceability,
  serviceable,
  notServiceable,
  serviceabilityCheckFailed,
  loadingSlots,
  slot,
  consent,
  submitting,
  success,
  submitFailed,
}

class RegistrationState extends Equatable {
  const RegistrationState({
    required this.draft,
    required this.phase,
    this.errorMessage,
    this.availableSlots = const [],
    this.result,
  });

  factory RegistrationState.initial() => const RegistrationState(
        draft: RegistrationDraft(),
        phase: RegistrationPhase.name,
      );

  final RegistrationDraft draft;
  final RegistrationPhase phase;
  final String? errorMessage;
  final List<DeliverySlot> availableSlots;
  final RegistrationResult? result;

  RegistrationState copyWith({
    RegistrationDraft? draft,
    RegistrationPhase? phase,
    String? errorMessage,
    List<DeliverySlot>? availableSlots,
    RegistrationResult? result,
  }) =>
      RegistrationState(
        draft: draft ?? this.draft,
        phase: phase ?? this.phase,
        errorMessage: errorMessage,
        availableSlots: availableSlots ?? this.availableSlots,
        result: result ?? this.result,
      );

  @override
  List<Object?> get props => [draft, phase, errorMessage, availableSlots, result];
}
