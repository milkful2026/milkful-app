import 'package:equatable/equatable.dart';

import '../data/registration_repository.dart';
import '../models/registration_draft.dart';

enum RegistrationPhase {
  address,
  checkingServiceability,
  notServiceable,
  serviceabilityCheckFailed,

  /// Serviceability confirmed — the Home screen shows its inline "What
  /// should we call you?" prompt (name and the old dedicated slot/consent
  /// steps were folded in here; consent is implicit via the Welcome
  /// screen's own footer text, and slot selection moved to Home's own
  /// calendar picker, usable independently of registration completing).
  awaitingName,
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
        phase: RegistrationPhase.address,
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
