import 'package:milkful_app/features/onboarding/data/places_repository.dart';

/// Matches PlacesRepository's real contract exactly (same "fix the fake,
/// not the assertion" discipline used throughout this repo) — configure the
/// `*Exception`/result fields to simulate failures/results instead of
/// hand-rolling ad-hoc mocks per test.
class FakePlacesRepository implements PlacesRepository {
  FakePlacesRepository({
    this.autocompleteException,
    this.reverseGeocodeException,
    this.geocodeByPlaceIdException,
    this.geocodeAddressException,
    this.suggestions = const [],
    this.geocodedAddress,
  });

  Object? autocompleteException;
  Object? reverseGeocodeException;
  Object? geocodeByPlaceIdException;
  Object? geocodeAddressException;
  List<PlaceSuggestion> suggestions;
  GeocodedAddress? geocodedAddress;

  final List<String> autocompleteQueries = [];
  final List<String> geocodedPlaceIds = [];
  final List<({double lat, double lng})> reverseGeocodedPoints = [];
  final List<String> geocodedAddresses = [];

  static const _defaultGeocodedAddress = GeocodedAddress(
    formattedAddress: '123 Green Valley, Sector 45, Fresh Meadows, 10023',
    city: 'Fresh Meadows',
    state: 'Test State',
    pincode: '560001',
    lat: 28.6139,
    lng: 77.2090,
  );

  @override
  Future<List<PlaceSuggestion>> autocomplete(String query) async {
    autocompleteQueries.add(query);
    if (autocompleteException != null) throw autocompleteException!;
    return suggestions;
  }

  @override
  Future<GeocodedAddress> reverseGeocode({required double lat, required double lng}) async {
    reverseGeocodedPoints.add((lat: lat, lng: lng));
    if (reverseGeocodeException != null) throw reverseGeocodeException!;
    return geocodedAddress ?? _defaultGeocodedAddress;
  }

  @override
  Future<GeocodedAddress> geocodeByPlaceId(String placeId) async {
    geocodedPlaceIds.add(placeId);
    if (geocodeByPlaceIdException != null) throw geocodeByPlaceIdException!;
    return geocodedAddress ?? _defaultGeocodedAddress;
  }

  @override
  Future<GeocodedAddress> geocodeAddress(String address) async {
    geocodedAddresses.add(address);
    if (geocodeAddressException != null) throw geocodeAddressException!;
    return geocodedAddress ?? _defaultGeocodedAddress;
  }
}
