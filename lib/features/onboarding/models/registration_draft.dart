import 'package:equatable/equatable.dart';

/// Mirrors user/src/handlers/dto.py's AddressDto field-for-field so
/// serialization to the register request body needs no translation layer.
class AddressDraft extends Equatable {
  const AddressDraft({
    required this.lines,
    required this.city,
    required this.state,
    required this.pincode,
    required this.lat,
    required this.lng,
    this.landmark,
  });

  final List<String> lines;
  final String city;
  final String state;
  final String pincode;
  final double lat;
  final double lng;
  final String? landmark;

  Map<String, dynamic> toRegisterJson() => {
        'lines': lines,
        'city': city,
        'state': state,
        'pincode': pincode,
        'lat': lat,
        'lng': lng,
        if (landmark != null) 'landmark': landmark,
        'isDefault': true,
      };

  Map<String, dynamic> toDraftJson() => {
        'lines': lines,
        'city': city,
        'state': state,
        'pincode': pincode,
        'lat': lat,
        'lng': lng,
        'landmark': landmark,
      };

  factory AddressDraft.fromDraftJson(Map<String, dynamic> json) => AddressDraft(
        lines: (json['lines'] as List).cast<String>(),
        city: json['city'] as String,
        state: json['state'] as String,
        pincode: json['pincode'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        landmark: json['landmark'] as String?,
      );

  @override
  List<Object?> get props => [lines, city, state, pincode, lat, lng, landmark];
}

/// Local onboarding draft — per spec §7. Persisted to shared_preferences on
/// each Continue (FR-10) so a killed/relaunched app resumes at the last
/// completed step instead of restarting the whole flow.
class RegistrationDraft extends Equatable {
  const RegistrationDraft({
    this.mobile,
    this.requestId,
    this.name,
    this.address,
    this.zoneId,
    this.termsAccepted = false,
    this.privacyAccepted = false,
    this.pushConsent = false,
  });

  final String? mobile;
  final String? requestId;
  final String? name;
  final AddressDraft? address;
  final String? zoneId;
  final bool termsAccepted;
  final bool privacyAccepted;
  final bool pushConsent;

  RegistrationDraft copyWith({
    String? mobile,
    String? requestId,
    String? name,
    AddressDraft? address,
    String? zoneId,
    bool? termsAccepted,
    bool? privacyAccepted,
    bool? pushConsent,
  }) =>
      RegistrationDraft(
        mobile: mobile ?? this.mobile,
        requestId: requestId ?? this.requestId,
        name: name ?? this.name,
        address: address ?? this.address,
        zoneId: zoneId ?? this.zoneId,
        termsAccepted: termsAccepted ?? this.termsAccepted,
        privacyAccepted: privacyAccepted ?? this.privacyAccepted,
        pushConsent: pushConsent ?? this.pushConsent,
      );

  Map<String, dynamic> toJson() => {
        'mobile': mobile,
        'requestId': requestId,
        'name': name,
        'address': address?.toDraftJson(),
        'zoneId': zoneId,
        'termsAccepted': termsAccepted,
        'privacyAccepted': privacyAccepted,
        'pushConsent': pushConsent,
      };

  factory RegistrationDraft.fromJson(Map<String, dynamic> json) => RegistrationDraft(
        mobile: json['mobile'] as String?,
        requestId: json['requestId'] as String?,
        name: json['name'] as String?,
        address: json['address'] == null
            ? null
            : AddressDraft.fromDraftJson(json['address'] as Map<String, dynamic>),
        zoneId: json['zoneId'] as String?,
        termsAccepted: json['termsAccepted'] as bool? ?? false,
        privacyAccepted: json['privacyAccepted'] as bool? ?? false,
        pushConsent: json['pushConsent'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [
        mobile,
        requestId,
        name,
        address,
        zoneId,
        termsAccepted,
        privacyAccepted,
        pushConsent,
      ];
}
