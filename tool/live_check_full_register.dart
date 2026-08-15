// One-off manual check: full registration round trip including the
// actual POST /users/register call (not just identity-auth's OTP verify)
// — proves the whole stack (identity-auth -> user service -> inventory
// -> real Postgres) works end to end, not just the identity-auth half.
import 'dart:convert';
import 'dart:io';

import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/auth/data/auth_repository.dart';
import 'package:milkful_app/features/onboarding/data/registration_repository.dart';
import 'package:milkful_app/features/onboarding/models/registration_draft.dart';

Future<void> main(List<String> args) async {
  final mobile = args.isNotEmpty ? args[0] : '+919876500090';
  final client = ApiClient(timeout: const Duration(seconds: 30));
  final authRepo = DioAuthRepository(client);

  stdout.writeln('Registering $mobile ...');
  final send = await authRepo.sendOtp(mobile);
  final peek = await Process.run('python', ['../services/local-dev/peek_otp.py', mobile]);
  final match = RegExp(r'otp=(\d+) template=registration').firstMatch(peek.stdout as String);
  final otp = match!.group(1)!;
  final tokens = await authRepo.verifyOtp(mobile: mobile, otp: otp, requestId: send.requestId);
  stdout.writeln('  accessToken acquired, isNewUser=${tokens.isNewUser}');

  // ApiClient's accessTokenProvider is normally wired to secure storage;
  // this script has no storage, so build a client that always returns
  // this one token instead.
  final authedClient = ApiClient(
    timeout: const Duration(seconds: 30),
    accessTokenProvider: () async => tokens.accessToken,
  );
  final authedRegRepo = DioRegistrationRepository(authedClient);

  stdout.writeln('Checking serviceability for pincode 560001 ...');
  final serviceability = await authedRegRepo.checkServiceability(
    pincode: '560001',
    lat: 12.9716,
    lng: 77.5946,
  );
  stdout.writeln('  serviceable=${serviceability.serviceable} zoneId=${serviceability.zoneId}');

  stdout.writeln('Fetching delivery slots for zone ${serviceability.zoneId} ...');
  final slots = await authedRegRepo.getDeliverySlots(serviceability.zoneId!);
  stdout.writeln('  slots=${slots.map((s) => s.id).toList()}');

  stdout.writeln('Submitting registration ...');
  final draft = RegistrationDraft(
    name: 'Priya Sharma',
    address: const AddressDraft(
      lines: ['12 MG Road'],
      city: 'Bangalore',
      state: 'Karnataka',
      pincode: '560001',
      lat: 12.9716,
      lng: 77.5946,
    ),
    zoneId: serviceability.zoneId,
    slotId: slots.first.id,
    termsAccepted: true,
    privacyAccepted: true,
  );
  final result = await authedRegRepo.register(draft);
  stdout.writeln('  userId=${result.userId} walletStatus=${result.walletStatus}');

  stdout.writeln(
    jsonEncode({'ok': true, 'userId': result.userId, 'walletStatus': result.walletStatus}),
  );
}
