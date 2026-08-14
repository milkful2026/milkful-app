import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../models/registration_draft.dart';

class DeliverySlot {
  const DeliverySlot({required this.id, required this.label, required this.available});

  final String id;
  final String label;
  final bool available;

  factory DeliverySlot.fromJson(Map<String, dynamic> json) => DeliverySlot(
        id: json['id'] as String,
        label: json['label'] as String,
        available: json['available'] as bool,
      );
}

class ServiceabilityResult {
  const ServiceabilityResult({
    required this.serviceable,
    this.zoneId,
    this.zoneName,
    this.slots = const [],
    this.message,
  });

  final bool serviceable;
  final String? zoneId;
  final String? zoneName;
  final List<DeliverySlot> slots;
  final String? message;

  factory ServiceabilityResult.fromJson(Map<String, dynamic> json) => ServiceabilityResult(
        serviceable: json['serviceable'] as bool,
        zoneId: json['zoneId'] as String?,
        zoneName: json['zoneName'] as String?,
        slots: (json['slots'] as List? ?? const [])
            .map((s) => DeliverySlot.fromJson(s as Map<String, dynamic>))
            .toList(),
        message: json['message'] as String?,
      );
}

class RegistrationResult {
  const RegistrationResult({
    required this.userId,
    required this.walletId,
    required this.walletStatus,
    required this.defaultAddressId,
  });

  final String userId;
  final String? walletId;
  final String walletStatus;
  final String defaultAddressId;

  factory RegistrationResult.fromJson(Map<String, dynamic> json) => RegistrationResult(
        userId: json['userId'] as String,
        walletId: json['walletId'] as String?,
        walletStatus: json['walletStatus'] as String,
        defaultAddressId: json['defaultAddressId'] as String,
      );
}

abstract class RegistrationRepository {
  /// FR-6: called after the address/pincode settles. Inventory's own
  /// response already carries `slots` for the matched zone, but the slot
  /// screen deliberately calls User Service's own /delivery/slots
  /// endpoint instead (see [getDeliverySlots]) — matching the spec's
  /// documented integration table exactly, not taking an undocumented
  /// shortcut through this response's embedded slots.
  Future<ServiceabilityResult> checkServiceability({
    required String pincode,
    required double lat,
    required double lng,
  });

  /// FR-7. Reads from User Service's own zone_slots table — see
  /// services/user/README.md's flagged decision #1 on how that table
  /// relates (or doesn't yet) to Inventory's zone config.
  Future<List<DeliverySlot>> getDeliverySlots(String zoneId);

  /// FR-8/9. Requires an access token — the caller (RegistrationBloc) is
  /// responsible for having one; ApiClient's token provider attaches it.
  Future<RegistrationResult> register(RegistrationDraft draft);
}

class DioRegistrationRepository implements RegistrationRepository {
  DioRegistrationRepository(this._client);

  final ApiClient _client;

  @override
  Future<ServiceabilityResult> checkServiceability({
    required String pincode,
    required double lat,
    required double lng,
  }) async {
    final data = await _client.request(
      'GET',
      '${AppConfig.inventoryBaseUrl}/v1/serviceability/check',
      queryParameters: {'pincode': pincode, 'lat': lat, 'lng': lng},
    );
    return ServiceabilityResult.fromJson(data);
  }

  @override
  Future<List<DeliverySlot>> getDeliverySlots(String zoneId) async {
    // The only endpoint whose `data` is a bare JSON array, not an object —
    // see ApiClient.requestList's docstring.
    final list = await _client.requestList(
      'GET',
      '${AppConfig.userBaseUrl}/delivery/slots',
      queryParameters: {'zoneId': zoneId},
    );
    return list.map((s) => DeliverySlot.fromJson(s as Map<String, dynamic>)).toList();
  }

  @override
  Future<RegistrationResult> register(RegistrationDraft draft) async {
    final address = draft.address;
    if (address == null) {
      throw const ApiException(errorCode: 'INVALID_DRAFT', message: 'No address in draft');
    }
    final data = await _client.request(
      'POST',
      '${AppConfig.userBaseUrl}/users/register',
      body: {
        'name': draft.name,
        'addresses': [address.toRegisterJson()],
        if (draft.slotId != null) 'preferredSlotId': draft.slotId,
        'consents': [
          {
            'type': 'TERMS',
            'accepted': draft.termsAccepted,
            'acceptedAt': DateTime.now().toUtc().toIso8601String(),
          },
          {
            'type': 'PRIVACY',
            'accepted': draft.privacyAccepted,
            'acceptedAt': DateTime.now().toUtc().toIso8601String(),
          },
          {
            'type': 'PUSH_NOTIFICATIONS',
            'accepted': draft.pushConsent,
            'acceptedAt': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      },
    );
    return RegistrationResult.fromJson(data);
  }
}
