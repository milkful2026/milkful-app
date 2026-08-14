import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/registration_bloc.dart';
import '../bloc/registration_event.dart';
import '../bloc/registration_state.dart';
import '../models/registration_draft.dart';

/// FR-5, manual entry only (map picker + Places autocomplete deferred —
/// need a real Google Maps API key this pass doesn't have, per the plan's
/// scope note). Since lat/lng normally comes from the map/geocoding this
/// pass doesn't have either, this screen also asks for them directly as
/// plain number fields — a deliberate deviation from the spec's literal
/// manual-entry field list, called out here rather than silently invented,
/// since both /serviceability/check and /users/register require real
/// lat/lng values.
class AddressScreen extends StatefulWidget {
  const AddressScreen({super.key});

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  final _lineController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _landmarkController = TextEditingController();

  bool get _isValid =>
      _lineController.text.trim().isNotEmpty &&
      _cityController.text.trim().isNotEmpty &&
      _stateController.text.trim().isNotEmpty &&
      RegExp(r'^\d{6}$').hasMatch(_pincodeController.text.trim()) &&
      double.tryParse(_latController.text.trim()) != null &&
      double.tryParse(_lngController.text.trim()) != null;

  @override
  void dispose() {
    for (final c in [
      _lineController,
      _cityController,
      _stateController,
      _pincodeController,
      _latController,
      _lngController,
      _landmarkController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final address = AddressDraft(
      lines: [_lineController.text.trim()],
      city: _cityController.text.trim(),
      state: _stateController.text.trim(),
      pincode: _pincodeController.text.trim(),
      lat: double.parse(_latController.text.trim()),
      lng: double.parse(_lngController.text.trim()),
      landmark: _landmarkController.text.trim().isEmpty
          ? null
          : _landmarkController.text.trim(),
    );
    context.read<RegistrationBloc>().add(AddressSubmitted(address));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery address')),
      body: BlocConsumer<RegistrationBloc, RegistrationState>(
        listener: (context, state) {
          if (state.phase == RegistrationPhase.slot) {
            context.go('/slot');
          }
        },
        builder: (context, state) {
          final checking = state.phase == RegistrationPhase.checkingServiceability ||
              state.phase == RegistrationPhase.loadingSlots;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field(_lineController, 'House / Flat, Street'),
                  _field(_landmarkController, 'Landmark (optional)'),
                  _field(_cityController, 'City'),
                  _field(_stateController, 'State'),
                  _field(_pincodeController, 'Pincode', keyboardType: TextInputType.number),
                  _field(_latController, 'Latitude', keyboardType: TextInputType.number),
                  _field(_lngController, 'Longitude', keyboardType: TextInputType.number),
                  const SizedBox(height: 16),
                  if (state.phase == RegistrationPhase.notServiceable)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        state.errorMessage ?? "Sorry, we don't deliver here yet",
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  if (state.phase == RegistrationPhase.serviceabilityCheckFailed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.errorMessage ?? 'Something went wrong',
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                          TextButton(
                            onPressed: () => context
                                .read<RegistrationBloc>()
                                .add(const ServiceabilityRetryRequested()),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: !_isValid || checking ? null : _submit,
                      child: checking
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Continue'),
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

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        label: label,
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
  }
}
