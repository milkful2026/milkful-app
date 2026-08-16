import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/features/onboarding/data/places_repository.dart';

/// Hand-written HttpClientAdapter, matching this repo's "hand-written
/// fakes, not a mocking package" convention — no Dio-level fake existed
/// anywhere in this repo before this file, so this introduces the pattern
/// for just this one repository rather than reaching for a new
/// dev_dependency.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this.responseFor);

  final Map<String, dynamic> Function(RequestOptions options) responseFor;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = jsonEncode(responseFor(options));
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('autocomplete', () {
    test('parses predictions into PlaceSuggestions', () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter(
          (_) => {
            'status': 'OK',
            'predictions': [
              {'place_id': 'place-1', 'description': '123 Green Valley, Sector 45'},
              {'place_id': 'place-2', 'description': '456 Oak Avenue, Cityville'},
            ],
          },
        );
      final repository = GooglePlacesRepository(dio, apiKey: 'test-key');

      final result = await repository.autocomplete('Green Valley');

      expect(result, [
        const PlaceSuggestion(placeId: 'place-1', description: '123 Green Valley, Sector 45'),
        const PlaceSuggestion(placeId: 'place-2', description: '456 Oak Avenue, Cityville'),
      ]);
    });

    test('ZERO_RESULTS returns an empty list, not an exception', () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter((_) => {'status': 'ZERO_RESULTS'});
      final repository = GooglePlacesRepository(dio, apiKey: 'test-key');

      expect(await repository.autocomplete('nowhere'), isEmpty);
    });

    test('a blank query short-circuits without calling the API', () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter(
          (_) => fail('should not have called the API for a blank query'),
        );
      final repository = GooglePlacesRepository(dio, apiKey: 'test-key');

      expect(await repository.autocomplete('   '), isEmpty);
    });

    test('a non-OK status throws PlacesApiException', () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter(
          (_) => {'status': 'REQUEST_DENIED', 'error_message': 'bad key'},
        );
      final repository = GooglePlacesRepository(dio, apiKey: 'test-key');

      await expectLater(
        repository.autocomplete('Green Valley'),
        throwsA(
          isA<PlacesApiException>()
              .having((e) => e.status, 'status', 'REQUEST_DENIED')
              .having((e) => e.message, 'message', 'bad key'),
        ),
      );
    });
  });

  group('reverseGeocode / geocodeByPlaceId', () {
    Map<String, dynamic> okGeocodeResponse() => {
          'status': 'OK',
          'results': [
            {
              'formatted_address': '123 Green Valley, Sector 45, Fresh Meadows, 10023',
              'geometry': {
                'location': {'lat': 28.6139, 'lng': 77.2090},
              },
              'address_components': [
                {
                  'long_name': 'Fresh Meadows',
                  'types': ['locality'],
                },
                {
                  'long_name': 'Test State',
                  'types': ['administrative_area_level_1'],
                },
                {
                  'long_name': '10023',
                  'types': ['postal_code'],
                },
              ],
            },
          ],
        };

    test('reverseGeocode parses city/state/pincode/lat/lng from address_components', () async {
      final dio = Dio()..httpClientAdapter = _FakeHttpClientAdapter((_) => okGeocodeResponse());
      final repository = GooglePlacesRepository(dio, apiKey: 'test-key');

      final result = await repository.reverseGeocode(lat: 28.6139, lng: 77.2090);

      expect(result.formattedAddress, '123 Green Valley, Sector 45, Fresh Meadows, 10023');
      expect(result.city, 'Fresh Meadows');
      expect(result.state, 'Test State');
      expect(result.pincode, '10023');
      expect(result.lat, 28.6139);
      expect(result.lng, 77.2090);
    });

    test('geocodeByPlaceId sends place_id, not latlng', () async {
      RequestOptions? capturedOptions;
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter((options) {
          capturedOptions = options;
          return okGeocodeResponse();
        });
      final repository = GooglePlacesRepository(dio, apiKey: 'test-key');

      await repository.geocodeByPlaceId('place-1');

      expect(capturedOptions!.queryParameters['place_id'], 'place-1');
      expect(capturedOptions!.queryParameters.containsKey('latlng'), isFalse);
    });

    test('missing address components fall back to empty strings, not a crash', () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter(
          (_) => {
            'status': 'OK',
            'results': [
              {
                'formatted_address': 'Somewhere unresolved',
                'geometry': {
                  'location': {'lat': 1.0, 'lng': 2.0},
                },
                'address_components': <Map<String, dynamic>>[],
              },
            ],
          },
        );
      final repository = GooglePlacesRepository(dio, apiKey: 'test-key');

      final result = await repository.reverseGeocode(lat: 1.0, lng: 2.0);

      expect(result.city, '');
      expect(result.state, '');
      expect(result.pincode, '');
    });

    test('ZERO_RESULTS throws PlacesApiException', () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter(
          (_) => {'status': 'ZERO_RESULTS', 'results': []},
        );
      final repository = GooglePlacesRepository(dio, apiKey: 'test-key');

      await expectLater(
        repository.reverseGeocode(lat: 0, lng: 0),
        throwsA(isA<PlacesApiException>().having((e) => e.status, 'status', 'ZERO_RESULTS')),
      );
    });
  });
}
