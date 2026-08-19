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

/// The Home screen's inline "What should we call you?" prompt, shown once
/// serviceability is confirmed — this is now also the final-submit
/// trigger: Terms & Privacy consent is implicit (the Welcome screen's own
/// "by continuing you agree..." footer), so there's no separate consent
/// step gating this the way there used to be. Submitting a name calls
/// `POST /users/register` directly.
class NameSubmitted extends RegistrationEvent {
  const NameSubmitted(this.name);

  final String name;

  @override
  List<Object?> get props => [name];
}

/// Fetches delivery slots for the Home screen's own calendar-style slot
/// picker — independent of registration completing; a returning user with
/// a known zone can dispatch this any time, not just mid-onboarding.
class DeliverySlotsRequested extends RegistrationEvent {
  const DeliverySlotsRequested(this.zoneId);

  final String zoneId;

  @override
  List<Object?> get props => [zoneId];
}
