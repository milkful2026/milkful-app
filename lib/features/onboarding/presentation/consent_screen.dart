import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/registration_bloc.dart';
import '../bloc/registration_event.dart';
import '../bloc/registration_state.dart';

/// FR-8. Legal doc links simplified to plain-text copy (WebView deferred —
/// no real legal-doc URLs exist to link to yet either, per the plan's
/// scope note).
class ConsentScreen extends StatelessWidget {
  const ConsentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Consent')),
      body: BlocConsumer<RegistrationBloc, RegistrationState>(
        listener: (context, state) {
          if (state.phase == RegistrationPhase.success) {
            context.go('/success');
          }
        },
        builder: (context, state) {
          final draft = state.draft;
          final canSubmit = draft.termsAccepted && draft.privacyAccepted;
          final submitting = state.phase == RegistrationPhase.submitting;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckboxListTile(
                    key: const Key('consent-terms'),
                    value: draft.termsAccepted,
                    title: const Text('I agree to the Terms & Conditions'),
                    onChanged: (checked) => context.read<RegistrationBloc>().add(
                          ConsentUpdated(
                            termsAccepted: checked ?? false,
                            privacyAccepted: draft.privacyAccepted,
                            pushConsent: draft.pushConsent,
                          ),
                        ),
                  ),
                  CheckboxListTile(
                    key: const Key('consent-privacy'),
                    value: draft.privacyAccepted,
                    title: const Text('I agree to the Privacy Policy'),
                    onChanged: (checked) => context.read<RegistrationBloc>().add(
                          ConsentUpdated(
                            termsAccepted: draft.termsAccepted,
                            privacyAccepted: checked ?? false,
                            pushConsent: draft.pushConsent,
                          ),
                        ),
                  ),
                  CheckboxListTile(
                    key: const Key('consent-push'),
                    value: draft.pushConsent,
                    title: const Text('Send me order updates via push notifications'),
                    onChanged: (checked) => context.read<RegistrationBloc>().add(
                          ConsentUpdated(
                            termsAccepted: draft.termsAccepted,
                            privacyAccepted: draft.privacyAccepted,
                            pushConsent: checked ?? false,
                          ),
                        ),
                  ),
                  if (state.phase == RegistrationPhase.submitFailed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        state.errorMessage ?? 'Something went wrong',
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: !canSubmit || submitting
                          ? null
                          : () => context
                              .read<RegistrationBloc>()
                              .add(const RegistrationSubmitted()),
                      child: submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Complete registration'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
