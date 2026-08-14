import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/registration_bloc.dart';
import '../bloc/registration_event.dart';
import '../bloc/registration_state.dart';

/// FR-7.
class SlotScreen extends StatelessWidget {
  const SlotScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery slot')),
      body: BlocBuilder<RegistrationBloc, RegistrationState>(
        builder: (context, state) {
          final selected = state.draft.slotId;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('When should we deliver?'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: state.availableSlots
                        .where((s) => s.available)
                        .map(
                          (slot) => ChoiceChip(
                            label: Text(slot.label),
                            selected: selected == slot.id,
                            onSelected: (_) => context
                                .read<RegistrationBloc>()
                                .add(SlotSelected(slot.id)),
                          ),
                        )
                        .toList(),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selected == null
                          ? null
                          : () => context.go('/consent'),
                      child: const Text('Continue'),
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
