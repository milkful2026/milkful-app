import 'package:equatable/equatable.dart';

/// MA-135 FR-6 / MA-137 FR-6 — the customer's default delivery address,
/// exactly as saved from the onboarding Google Maps / Places screen and
/// returned by `GET /users/me`'s `defaultAddress`.
class DeliveryAddress extends Equatable {
  const DeliveryAddress({
    required this.id,
    required this.lines,
    required this.city,
    required this.state,
    required this.pincode,
    required this.lat,
    required this.lng,
    this.landmark,
  });

  final String id;
  final List<String> lines;
  final String? landmark;
  final String city;
  final String state;
  final String pincode;
  final double lat;
  final double lng;

  factory DeliveryAddress.fromJson(Map<String, dynamic> json) => DeliveryAddress(
    id: json['id'] as String,
    lines: (json['lines'] as List<dynamic>).cast<String>(),
    landmark: json['landmark'] as String?,
    city: json['city'] as String,
    state: json['state'] as String,
    pincode: json['pincode'] as String,
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
  );

  /// "Flat 402, Sai Heights, Baner Road"
  String get street => lines.where((line) => line.trim().isNotEmpty).join(', ');

  /// "Pune, Maharashtra 411045"
  String get cityStatePincode => '$city, $state $pincode';

  @override
  List<Object?> get props => [id, lines, landmark, city, state, pincode, lat, lng];
}
