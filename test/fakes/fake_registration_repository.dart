import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/onboarding/data/registration_repository.dart';
import 'package:milkful_app/features/onboarding/models/registration_draft.dart';

class FakeRegistrationRepository implements RegistrationRepository {
  FakeRegistrationRepository({
    this.serviceabilityResult,
    this.serviceabilityException,
    this.slots = const [],
    this.slotsException,
    this.registerResult,
    this.registerException,
  });

  ServiceabilityResult? serviceabilityResult;
  ApiException? serviceabilityException;
  List<DeliverySlot> slots;
  ApiException? slotsException;
  RegistrationResult? registerResult;
  ApiException? registerException;

  RegistrationDraft? lastRegistered;

  @override
  Future<ServiceabilityResult> checkServiceability({
    required String pincode,
    required double lat,
    required double lng,
  }) async {
    if (serviceabilityException != null) throw serviceabilityException!;
    return serviceabilityResult ??
        const ServiceabilityResult(serviceable: true, zoneId: 'zone-1', zoneName: 'Zone 1');
  }

  @override
  Future<List<DeliverySlot>> getDeliverySlots(String zoneId) async {
    if (slotsException != null) throw slotsException!;
    return slots;
  }

  @override
  Future<RegistrationResult> register(RegistrationDraft draft) async {
    lastRegistered = draft;
    if (registerException != null) throw registerException!;
    return registerResult ??
        const RegistrationResult(
          userId: 'user-1',
          walletId: null,
          walletStatus: 'PENDING',
          defaultAddressId: 'addr-1',
        );
  }
}
