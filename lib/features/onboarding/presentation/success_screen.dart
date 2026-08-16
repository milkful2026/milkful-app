import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/registration_bloc.dart';
import '../bloc/registration_state.dart';

/// FR-9. No wallet-status polling/retry endpoint exists yet (MA-100
/// auto-provision is explicitly out of scope on the backend — see
/// user/README.md), so PENDING and FAILED are both shown as informational
/// only, not with a working retry action. FAILED is called out distinctly
/// from PENDING/success per AC-9 ("user never sees silent failure") even
/// though the backend today always returns PENDING at registration time —
/// see specs/services/tasks/MA/MA-1/wallet-auto-provision.md FR-2/FR-3.
class SuccessScreen extends StatelessWidget {
  const SuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<RegistrationBloc, RegistrationState>(
        builder: (context, state) {
          final result = state.result;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, size: 64, color: Colors.green),
                  const SizedBox(height: 16),
                  Text('Welcome to Freshoza!', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  if (result?.walletStatus == 'PENDING')
                    const Text("Your Freshoza Wallet is being set up.")
                  else if (result?.walletStatus == 'FAILED')
                    Text(
                      'Wallet setup incomplete — contact support if this persists.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    )
                  else if (result != null)
                    const Text('Your Freshoza Wallet is ready.'),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => context.go('/home'),
                      child: const Text('Start ordering'),
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
