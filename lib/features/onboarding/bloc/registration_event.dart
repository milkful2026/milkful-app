import 'package:equatable/equatable.dart';

import '../models/registration_draft.dart';

sealed class RegistrationEvent extends Equatable {
  const RegistrationEvent();

  @override
  List<Object?> get props => [];
}

/// FR-10: loaded once at app start / onboarding entry, before any other
/// event — resumes mid-flow instead of restarting from scratch.
class DraftRestored extends RegistrationEvent {
  const DraftRestored(this.draft);

  final RegistrationDraft? draft;

  @override
  List<Object?> get props => [draft];
}

/// FR-4.
class NameSubmitted extends RegistrationEvent {
  const NameSubmitted(this.name);

  final String name;

  @override
  List<Object?> get props => [name];
}

/// FR-5/6: manual-entry address; submitting it triggers the serviceability
/// check automatically (this bloc, not the UI, owns that sequencing).
class AddressSubmitted extends RegistrationEvent {
  const AddressSubmitted(this.address);

  final AddressDraft address;

  @override
  List<Object?> get props => [address];
}

/// FR-6: "Retry" after a serviceability check error (not a not-serviceable
/// result — that has its own "Try another address" path back to the
/// address step, not a retry).
class ServiceabilityRetryRequested extends RegistrationEvent {
  const ServiceabilityRetryRequested();
}

/// FR-7.
class SlotSelected extends RegistrationEvent {
  const SlotSelected(this.slotId);

  final String slotId;

  @override
  List<Object?> get props => [slotId];
}

/// FR-8.
class ConsentUpdated extends RegistrationEvent {
  const ConsentUpdated({
    required this.termsAccepted,
    required this.privacyAccepted,
    required this.pushConsent,
  });

  final bool termsAccepted;
  final bool privacyAccepted;
  final bool pushConsent;

  @override
  List<Object?> get props => [termsAccepted, privacyAccepted, pushConsent];
}

/// FR-8/9: final submit.
class RegistrationSubmitted extends RegistrationEvent {
  const RegistrationSubmitted();
}
