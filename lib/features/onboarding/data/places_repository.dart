import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

import '../../../core/config/app_config.dart';

/// A single Places Autocomplete suggestion — only what the search bar's
/// suggestion list and the follow-up geocode need, not Google's full
/// response shape.
class PlaceSuggestion extends Equatable {
  const PlaceSuggestion({required this.placeId, required this.description});

  final String placeId;
  final String description;

  @override
  List<Object?> get props => [placeId, description];
}

/// A resolved point on the map, reverse-geocoded (or geocoded from a
/// [PlaceSuggestion.placeId]) into the fields [AddressDraft] needs directly
/// — city/state/pincode/lat/lng — plus a human-readable formattedAddress for
/// the address screen's read-only preview line.
class GeocodedAddress extends Equatable {
  const GeocodedAddress({
    required this.formattedAddress,
    required this.city,
    required this.state,
    required this.pincode,
    required this.lat,
    required this.lng,
  });

  final String formattedAddress;
  final String city;
  final String state;
  final String pincode;
  final double lat;
  final double lng;

  @override
  List<Object?> get props => [formattedAddress, city, state, pincode, lat, lng];
}

/// Thrown when Google's API responds but with a non-OK `status` (e.g.
/// `ZERO_RESULTS`, `REQUEST_DENIED`) — kept separate from Dio's own
/// [DioException] so callers can show a specific "couldn't find that
/// address" message rather than a generic network-error one.
class PlacesApiException implements Exception {
  const PlacesApiException(this.status, [this.message]);

  final String status;
  final String? message;

  @override
  String toString() => 'PlacesApiException($status${message != null ? ": $message" : ""})';
}

/// Wraps Google's Places Autocomplete + Geocoding REST APIs — used by the
/// address screen's search bar and its onCameraIdle reverse-geocode. Not
/// layered on [ApiClient]: that class unwraps this app's own backend
/// envelope (`{requestId,status,data}`), which Google's APIs don't use, so
/// this repository takes a raw [Dio] instead, following the same
/// interface-+-impl split as RegistrationRepository for testability.
abstract class PlacesRepository {
  Future<List<PlaceSuggestion>> autocomplete(String query);

  Future<GeocodedAddress> reverseGeocode({required double lat, required double lng});

  /// Resolves a suggestion tapped from [autocomplete]'s results to a full
  /// [GeocodedAddress] (including lat/lng, so the map can move its camera
  /// there) — the Geocoding API accepts `place_id` as an alternative to
  /// `latlng`, so this reuses the exact same response parsing as
  /// [reverseGeocode] rather than needing a separate Place Details call.
  Future<GeocodedAddress> geocodeByPlaceId(String placeId);
}

class GooglePlacesRepository implements PlacesRepository {
  GooglePlacesRepository(this._dio, {this.apiKey = AppConfig.googleMapsApiKey});

  static const _baseUrl = 'https://maps.googleapis.com/maps/api';

  final Dio _dio;
  final String apiKey;

  @override
  Future<List<PlaceSuggestion>> autocomplete(String query) async {
    if (query.trim().isEmpty) return const [];
    final response = await _dio.get<Map<String, dynamic>>(
      '$_baseUrl/place/autocomplete/json',
      queryParameters: {'input': query, 'key': apiKey},
    );
    final data = response.data!;
    final status = data['status'] as String;
    if (status == 'ZERO_RESULTS') return const [];
    if (status != 'OK') {
      throw PlacesApiException(status, data['error_message'] as String?);
    }
    return (data['predictions'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (p) => PlaceSuggestion(
            placeId: p['place_id'] as String,
            description: p['description'] as String,
          ),
        )
        .toList();
  }

  @override
  Future<GeocodedAddress> reverseGeocode({required double lat, required double lng}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$_baseUrl/geocode/json',
      queryParameters: {'latlng': '$lat,$lng', 'key': apiKey},
    );
    return _firstResultToGeocodedAddress(response.data!);
  }

  @override
  Future<GeocodedAddress> geocodeByPlaceId(String placeId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$_baseUrl/geocode/json',
      queryParameters: {'place_id': placeId, 'key': apiKey},
    );
    return _firstResultToGeocodedAddress(response.data!);
  }

  GeocodedAddress _firstResultToGeocodedAddress(Map<String, dynamic> data) {
    final status = data['status'] as String;
    if (status != 'OK') {
      throw PlacesApiException(status, data['error_message'] as String?);
    }
    final results = data['results'] as List;
    if (results.isEmpty) {
      throw const PlacesApiException('ZERO_RESULTS');
    }
    final result = results.first as Map<String, dynamic>;
    final components = (result['address_components'] as List).cast<Map<String, dynamic>>();

    String? componentNamed(String type) {
      for (final c in components) {
        if ((c['types'] as List).contains(type)) return c['long_name'] as String;
      }
      return null;
    }

    final location = (result['geometry'] as Map<String, dynamic>)['location'] as Map<String, dynamic>;
    return GeocodedAddress(
      formattedAddress: result['formatted_address'] as String,
      city: componentNamed('locality') ?? componentNamed('administrative_area_level_2') ?? '',
      state: componentNamed('administrative_area_level_1') ?? '',
      pincode: componentNamed('postal_code') ?? '',
      lat: (location['lat'] as num).toDouble(),
      lng: (location['lng'] as num).toDouble(),
    );
  }
}
