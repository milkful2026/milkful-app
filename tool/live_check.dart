// Manual live-backend sanity check — NOT part of `flutter test` (which
// stays fully offline against fakes). Exercises the real DioAuthRepository
// against a real running identity-auth backend end-to-end: send OTP,
// read it back via services/local-dev/peek_otp.py (no SMS provider exists
// locally), verify it, confirm a real access token comes back. Useful for
// catching wire-contract mismatches (URL/field-name typos) that fakes,
// which are written by hand to match the contract, can't catch by
// construction.
//
// Prerequisites: services/local-dev's moto_server + identity-auth running
// locally (see services/local-dev/README.md), with a fresh mobile number
// each run (OTP resend cooldown otherwise blocks a second run).
//
//   dart run tool/live_check.dart +919876543299
import 'dart:convert';
import 'dart:io';

import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/auth/data/auth_repository.dart';

Future<void> main(List<String> args) async {
  final mobile = args.isNotEmpty ? args[0] : '+919876543298';
  // moto_server's Flask dev server can take >10s for verify (chains
  // AdminCreateUser + AdminSetUserPassword + AdminInitiateAuth) — already
  // observed and documented in services/local-dev/README.md's Known Gaps;
  // ApiClient's production default (10s) is fine for a real backend.
  final client = ApiClient(timeout: const Duration(seconds: 30));
  final repository = DioAuthRepository(client);

  stdout.writeln('Sending OTP to $mobile ...');
  final sendResult = await repository.sendOtp(mobile);
  stdout.writeln('  requestId=${sendResult.requestId} expiresIn=${sendResult.expiresIn}');

  stdout.writeln('Reading OTP via services/local-dev/peek_otp.py ...');
  final peek = await Process.run('python', [
    '../services/local-dev/peek_otp.py',
    mobile,
  ]);
  stdout.write(peek.stdout);
  final match = RegExp(r'otp=(\d+)').firstMatch(peek.stdout as String);
  if (match == null) {
    stderr.writeln('Could not find an OTP for $mobile — is the backend actually running?');
    exit(1);
  }
  final otp = match.group(1)!;

  stdout.writeln('Verifying OTP $otp ...');
  final tokens = await repository.verifyOtp(
    mobile: mobile,
    otp: otp,
    requestId: sendResult.requestId,
  );
  stdout.writeln('  isNewUser=${tokens.isNewUser}');
  stdout.writeln('  accessToken (first 20 chars)=${tokens.accessToken.substring(0, 20)}...');
  stdout.writeln(
    jsonEncode({'ok': true, 'isNewUser': tokens.isNewUser, 'expiresIn': tokens.expiresIn}),
  );
}
