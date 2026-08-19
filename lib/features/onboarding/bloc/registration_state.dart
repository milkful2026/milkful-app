import 'package:equatable/equatable.dart';

import '../data/registration_repository.dart';
import '../models/registration_draft.dart';

enum RegistrationPhase {
  address,
  checkingServiceability,
  notServiceable,
  serviceabilityCheckFailed,

  /// Serviceability confirmed — registration submits automatically from
  /// here (no dedicated name/slot/consent steps: consent is implicit via
  /// the Welcome screen's own footer text, slot selection moved to Home's
  /// own calendar picker usable independently of registration completing,
  /// and name is no longer collected from the user at all — see
  /// RegistrationBloc's own doc comment on `_submitRegistration`).
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
