// Manual live-backend sanity check for MA-21's login flow, mirroring
// live_check.dart's approach for MA-1's registration flow — drives the
// real DioAuthRepository (not a fake) against a real running
// identity-auth backend: register a fresh number first (login only works
// for an already-registered user), log in via the separate
// /login/otp/... endpoints, then log out.
//
//   dart run tool/live_check_login.dart +919876500099
import 'dart:convert';
import 'dart:io';

import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/auth/data/auth_repository.dart';

/// [template] disambiguates "registration" vs "login" — the debug queue
/// can hold both for the same mobile number (e.g. this script registers
/// then logs in with the same number), and picking the wrong one fails
/// with a confusing OTP_INVALID rather than a clear "wrong OTP picked".
Future<String> _readOtp(String mobile, String template) async {
  final peek = await Process.run('python', [
    '../services/local-dev/peek_otp.py',
    mobile,
  ]);
  stdout.write(peek.stdout);
  final pattern = RegExp('otp=(\\d+) template=$template');
  final match = pattern.firstMatch(peek.stdout as String);
  if (match == null) {
    stderr.writeln(
      'Could not find a $template OTP for $mobile — is the backend actually running?',
    );
    exit(1);
  }
  return match.group(1)!;
}

Future<void> main(List<String> args) async {
  final mobile = args.isNotEmpty ? args[0] : '+919876500098';
  final client = ApiClient(timeout: const Duration(seconds: 30));
  final repository = DioAuthRepository(client);

  stdout.writeln('=== Step 1: register $mobile (login needs an existing account) ===');
  final registerSend = await repository.sendOtp(mobile);
  final registerOtp = await _readOtp(mobile, 'registration');
  final registerTokens = await repository.verifyOtp(
    mobile: mobile,
    otp: registerOtp,
    requestId: registerSend.requestId,
  );
  stdout.writeln('  registered: isNewUser=${registerTokens.isNewUser}');

  stdout.writeln('=== Step 2: log in with the same number ===');
  final loginSend = await repository.sendLoginOtp(mobile);
  stdout.writeln('  requestId=${loginSend.requestId}');
  final loginOtp = await _readOtp(mobile, 'login');
  final loginTokens = await repository.verifyLoginOtp(
    mobile: mobile,
    otp: loginOtp,
    requestId: loginSend.requestId,
  );
  stdout.writeln('  isNewUser=${loginTokens.isNewUser} (should be null, not false or true)');
  stdout.writeln('  accessToken (first 20 chars)=${loginTokens.accessToken.substring(0, 20)}...');

  stdout.writeln('=== Step 3: log out ===');
  await repository.logout(loginTokens.refreshToken);
  stdout.writeln('  logout call completed without throwing');

  stdout.writeln(
    jsonEncode({
      'ok': true,
      'registerIsNewUser': registerTokens.isNewUser,
      'loginIsNewUser': loginTokens.isNewUser,
    }),
  );
}
