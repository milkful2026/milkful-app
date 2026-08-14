import 'package:milkful_app/core/storage/draft_storage.dart';
import 'package:milkful_app/features/onboarding/models/registration_draft.dart';

class FakeDraftStorage implements DraftStorage {
  RegistrationDraft? saved;

  @override
  Future<void> save(RegistrationDraft draft) async => saved = draft;

  @override
  Future<RegistrationDraft?> load() async => saved;

  @override
  Future<void> clear() async => saved = null;
}
