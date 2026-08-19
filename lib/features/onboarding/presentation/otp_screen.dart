import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/draft_storage.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/presentation/otp_verification_view.dart';
import '../bloc/registration_bloc.dart';
import '../bloc/registration_event.dart';
import '../bloc/registration_state.dart';

/// FR-10: maps a resumed draft's settled phase to the screen that owns it.
/// `address`/`serviceabilityCheckFailed`/`notServiceable` all resolve to
/// `/address` since that screen already renders the right UI for each;
/// `awaitingName` means serviceability is already confirmed, so Home is
/// what shows the inline name prompt that finishes registration.
String _routeForPhase(RegistrationPhase phase) => switch (phase) {
      RegistrationPhase.awaitingName => '/home',
      _ => '/address',
    };

/// FR-2.
class OtpScreen extends StatelessWidget {
  const OtpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return OtpVerificationView(
      bodyText: 'Enter the 6-digit code we sent you',
      pinKey: const Key('otp-input'),
      resendLabel: 'Resend OTP',
      onCompleted: (context, otp) =>
          context.read<AuthBloc>().add(OtpVerifyRequested(otp)),
      onResend: (context, mobile) =>
          context.read<AuthBloc>().add(OtpResendRequested(mobile)),
      onAuthenticated: (context) async {
        final draft = await context.read<DraftStorage>().load();
        if (!context.mounted) return;
        final registrationBloc = context.read<RegistrationBloc>();
        registrationBloc.add(DraftRestored(draft));
        // `_onDraftRestored` emits exactly one settled (non-transient)
        // phase, so this resolves to whichever step the restored draft
        // actually needs next rather than always the blank Name screen.
        final phase = await registrationBloc.stream
            .map((s) => s.phase)
            .firstWhere((p) => p != RegistrationPhase.checkingServiceability);
        if (!context.mounted) return;
        context.go(_routeForPhase(phase));
      },
    );
  }
}
