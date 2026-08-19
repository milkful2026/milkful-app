import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../bloc/registration_bloc.dart';
import '../bloc/registration_event.dart';
import '../bloc/registration_state.dart';
import '../data/places_repository.dart';
import '../models/registration_draft.dart';

/// FR-5. Real map picker: a center-fixed pin (map moves under it, rather
/// than a draggable marker) + search bar wired to Places Autocomplete, with
/// the pin's resting position reverse-geocoded to pre-fill City/State/
/// Pincode. Those three stay editable rather than read-only, though — the
/// map/geocode is a convenience, not a hard dependency, so typing/correcting
/// them directly always works even if the map/network side fails or is
/// simply skipped.
class AddressScreen extends StatefulWidget {
  const AddressScreen({super.key});

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

/// Fallback map center when device location isn't available/permitted —
/// avoids a dead-end blank map rather than blocking on permission.
const _fallbackCenter = LatLng(28.6139, 77.2090);

class _AddressScreenState extends State<AddressScreen> {
  final _mapController = Completer<GoogleMapController>();
  final _lineController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _searchController = TextEditingController();

  LatLng _cameraTarget = _fallbackCenter;
  GeocodedAddress? _resolved;
  bool _resolving = false;
  List<PlaceSuggestion> _suggestions = [];
  Timer? _searchDebounce;
  int _searchRequestId = 0;

  // Once the user edits City/State/Pincode directly, further map-driven
  // reverse-geocode results stop overwriting them — otherwise panning the
  // map after a manual correction would silently clobber it.
  bool _addressFieldsEditedManually = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_lineController, _cityController, _stateController, _pincodeController]) {
      c.addListener(() => setState(() {}));
    }
    unawaited(_centerOnCurrentLocation());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _lineController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    _landmarkController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _applyResolvedToFields(GeocodedAddress resolved) {
    if (_addressFieldsEditedManually) return;
    _cityController.text = resolved.city;
    _stateController.text = resolved.state;
    _pincodeController.text = resolved.pincode;
  }

  Future<void> _centerOnCurrentLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final granted = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (!granted) return;
      final position = await Geolocator.getCurrentPosition();
      final target = LatLng(position.latitude, position.longitude);
      final controller = await _mapController.future;
      await controller.animateCamera(CameraUpdate.newLatLng(target));
      // onCameraIdle (fired by the animate above) picks up the reverse
      // geocode from here — see its own comment on why this isn't called
      // again directly.
    } catch (_) {
      // Falls back to the fallback-center's own initial onCameraIdle
      // reverse-geocode — no dead-end UX either way.
    }
  }

  Future<void> _reverseGeocodeCurrentCamera() async {
    setState(() => _resolving = true);
    try {
      final result = await context
          .read<PlacesRepository>()
          .reverseGeocode(lat: _cameraTarget.latitude, lng: _cameraTarget.longitude);
      if (!mounted) return;
      setState(() {
        _resolved = result;
        _resolving = false;
        _applyResolvedToFields(result);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolved = null;
        _resolving = false;
      });
    }
  }

  // Debounced (300ms, matching the catalog search field's own pattern) to
  // avoid firing a Places Autocomplete call on every keystroke. Requests are
  // also tagged with an incrementing id so a slower response for an earlier
  // (shorter) query can't land after — and overwrite — a newer one.
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      _searchRequestId++;
      setState(() => _suggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    final requestId = ++_searchRequestId;
    try {
      final results = await context.read<PlacesRepository>().autocomplete(query);
      if (!mounted || requestId != _searchRequestId) return;
      setState(() => _suggestions = results);
    } catch (_) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() => _suggestions = []);
    }
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    setState(() {
      _suggestions = [];
      _searchController.clear();
      _resolving = true;
    });
    try {
      final geocoded = await context.read<PlacesRepository>().geocodeByPlaceId(suggestion.placeId);
      _cameraTarget = LatLng(geocoded.lat, geocoded.lng);
      final controller = await _mapController.future;
      await controller.animateCamera(CameraUpdate.newLatLng(_cameraTarget));
      if (!mounted) return;
      setState(() {
        _resolved = geocoded;
        _resolving = false;
        _applyResolvedToFields(geocoded);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _resolving = false);
    }
  }

  // Deliberately does NOT require _resolved — the map/search/reverse-geocode
  // path is a convenience to pre-fill City/State/Pincode, not a hard
  // dependency. If it fails (no network, emulator quirks, etc.) or the user
  // simply prefers to type the address directly, these fields are always
  // editable and gate submission on their own.
  bool get _isValid =>
      _lineController.text.trim().isNotEmpty &&
      _cityController.text.trim().isNotEmpty &&
      _stateController.text.trim().isNotEmpty &&
      RegExp(r'^\d{6}$').hasMatch(_pincodeController.text.trim());

  Future<void> _submit() async {
    var lat = _resolved?.lat;
    var lng = _resolved?.lng;
    // No resolved map/search geocode (e.g. the user typed City/State/
    // Pincode by hand and the map's own reverse-geocode never succeeded) —
    // best-effort forward-geocode what they typed, so the submitted point
    // matches the address text rather than silently defaulting to wherever
    // the map camera happened to be resting (which could be a different
    // city entirely).
    if (lat == null || lng == null) {
      setState(() => _resolving = true);
      try {
        final typed = [
          _lineController.text.trim(),
          _cityController.text.trim(),
          _stateController.text.trim(),
          _pincodeController.text.trim(),
        ].where((s) => s.isNotEmpty).join(', ');
        final geocoded = await context.read<PlacesRepository>().geocodeAddress(typed);
        lat = geocoded.lat;
        lng = geocoded.lng;
      } catch (_) {
        // Falls through to the map's current pin position below — still
        // the actual point the user last saw/selected, just without a
        // resolved match for what they typed.
      } finally {
        if (mounted) setState(() => _resolving = false);
      }
    }
    if (!mounted) return;
    final address = AddressDraft(
      lines: [_lineController.text.trim()],
      city: _cityController.text.trim(),
      state: _stateController.text.trim(),
      pincode: _pincodeController.text.trim(),
      lat: lat ?? _cameraTarget.latitude,
      lng: lng ?? _cameraTarget.longitude,
      landmark:
          _landmarkController.text.trim().isEmpty ? null : _landmarkController.text.trim(),
    );
    context.read<RegistrationBloc>().add(AddressSubmitted(address));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      extendBodyBehindAppBar: true,
      body: BlocConsumer<RegistrationBloc, RegistrationState>(
        listener: (context, state) {
          // Serviceability confirmed — registration auto-submits from here
          // (name/consent/slot no longer have their own dedicated wizard
          // steps), so Home is where that plays out.
          if (state.phase == RegistrationPhase.submitting) {
            context.go('/home');
          }
        },
        builder: (context, state) {
          final checking = state.phase == RegistrationPhase.checkingServiceability;
          return Column(
            children: [
              Expanded(
                flex: 6,
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(target: _cameraTarget, zoom: 16),
                      onMapCreated: _mapController.complete,
                      onCameraMove: (position) => _cameraTarget = position.target,
                      onCameraIdle: _reverseGeocodeCurrentCamera,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                    ),
                    const IgnorePointer(
                      child: Center(
                        child: Padding(
                          // Pin's tip (not its center) should sit over the
                          // camera's true center point.
                          padding: EdgeInsets.only(bottom: 36),
                          child: Icon(Icons.location_pin, size: 44, color: Colors.redAccent),
                        ),
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 12,
                      right: 12,
                      child: Column(
                        children: [
                          Material(
                            elevation: 2,
                            borderRadius: BorderRadius.circular(12),
                            child: TextField(
                              controller: _searchController,
                              onChanged: _onSearchChanged,
                              decoration: const InputDecoration(
                                hintText: 'Search for area, street name',
                                prefixIcon: Icon(Icons.search),
                                border: InputBorder.none,
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                          ),
                          if (_suggestions.isNotEmpty)
                            Material(
                              elevation: 2,
                              borderRadius: BorderRadius.circular(12),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 200),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _suggestions.length,
                                  itemBuilder: (context, index) {
                                    final suggestion = _suggestions[index];
                                    return ListTile(
                                      dense: true,
                                      leading: const Icon(Icons.location_on_outlined),
                                      title: Text(suggestion.description),
                                      onTap: () => _selectSuggestion(suggestion),
                                    );
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 5,
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Select Location',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_resolving)
                          const LinearProgressIndicator()
                        else
                          Text(
                            _resolved?.formattedAddress ?? 'Move the map to select a location',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        const SizedBox(height: 16),
                        Semantics(
                          label: 'House / Flat / Block No.',
                          child: TextField(
                            key: const Key('house-flat-field'),
                            controller: _lineController,
                            decoration: const InputDecoration(
                              labelText: 'House / Flat / Block No.',
                              hintText: 'e.g. Apt 4B, Building 7',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Pre-filled from the map/search's reverse-geocode
                        // when available, but always editable — the map is a
                        // convenience, not a requirement, to fill these in.
                        Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                label: 'City',
                                child: TextField(
                                  key: const Key('city-field'),
                                  controller: _cityController,
                                  onChanged: (_) => _addressFieldsEditedManually = true,
                                  decoration: const InputDecoration(labelText: 'City'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Semantics(
                                label: 'State',
                                child: TextField(
                                  key: const Key('state-field'),
                                  controller: _stateController,
                                  onChanged: (_) => _addressFieldsEditedManually = true,
                                  decoration: const InputDecoration(labelText: 'State'),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Semantics(
                          label: 'Pincode',
                          child: TextField(
                            key: const Key('pincode-field'),
                            controller: _pincodeController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            onChanged: (_) => _addressFieldsEditedManually = true,
                            decoration: const InputDecoration(labelText: 'Pincode', counterText: ''),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Semantics(
                          label: 'Landmark (optional)',
                          child: TextField(
                            key: const Key('landmark-field'),
                            controller: _landmarkController,
                            decoration: const InputDecoration(
                              labelText: 'Landmark (optional)',
                              hintText: 'e.g. Near Central Park West',
                            ),
                          ),
                        ),
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
                          child: FilledButton.icon(
                            onPressed: !_isValid || checking || _resolving ? null : _submit,
                            icon: checking
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: const Text('Confirm Location'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
