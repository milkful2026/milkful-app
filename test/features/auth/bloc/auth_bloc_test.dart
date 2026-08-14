import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/auth/bloc/auth_bloc.dart';
import 'package:milkful_app/features/auth/bloc/auth_event.dart';
import 'package:milkful_app/features/auth/bloc/auth_state.dart';

import '../../../fakes/fake_auth_repository.dart';
import '../../../fakes/fake_profile_repository.dart';
import '../../../fakes/fake_secure_token_storage.dart';

void main() {
  group('AuthBloc', () {
    late FakeAuthRepository repository;
    late FakeSecureTokenStorage tokenStorage;
    late FakeProfileRepository profileRepository;

    setUp(() {
      repository = FakeAuthRepository();
      tokenStorage = FakeSecureTokenStorage();
      profileRepository = FakeProfileRepository();
    });

    AuthBloc build() => AuthBloc(
          authRepository: repository,
          tokenStorage: tokenStorage,
          profileRepository: profileRepository,
        );

    blocTest<AuthBloc, AuthState>(
      'OtpSendRequested emits sending then sent on success',
      build: build,
      act: (bloc) => bloc.add(const OtpSendRequested('+919876543210')),
      expect: () => [
        const AuthOtpSending('+919876543210'),
        const AuthOtpSent(
          mobile: '+919876543210',
          requestId: 'req-1',
          expiresIn: 300,
          resendAfter: 30,
        ),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'OtpSendRequested with USER_EXISTS emits AuthUserAlreadyExists, not a generic failure',
      build: () {
        repository.sendOtpException = const ApiException(
          errorCode: 'USER_EXISTS',
          message: 'already registered',
        );
        return build();
      },
      act: (bloc) => bloc.add(const OtpSendRequested('+919876543210')),
      expect: () => [
        const AuthOtpSending('+919876543210'),
        const AuthUserAlreadyExists('+919876543210'),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'OtpSendRequested with a non-USER_EXISTS error emits AuthOtpSendFailure',
      build: () {
        repository.sendOtpException = const ApiException(
          errorCode: 'RATE_LIMIT_EXCEEDED',
          message: 'Too many attempts',
        );
        return build();
      },
      act: (bloc) => bloc.add(const OtpSendRequested('+919876543210')),
      expect: () => [
        const AuthOtpSending('+919876543210'),
        const AuthOtpSendFailure(
          mobile: '+919876543210',
          errorCode: 'RATE_LIMIT_EXCEEDED',
          message: 'Too many attempts',
        ),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'OtpVerifyRequested on success emits verifying then authenticated, and saves tokens',
      build: build,
      seed: () => const AuthOtpSent(
        mobile: '+919876543210',
        requestId: 'req-1',
        expiresIn: 300,
        resendAfter: 30,
      ),
      act: (bloc) => bloc.add(const OtpVerifyRequested('123456')),
      expect: () => [
        const AuthOtpVerifying(mobile: '+919876543210', requestId: 'req-1'),
        isA<AuthAuthenticated>(),
      ],
      verify: (_) {
        expect(tokenStorage.accessToken, 'access-token');
        expect(tokenStorage.refreshToken, 'refresh-token');
        // Registration verify never calls GET /users/me — the user
        // doesn't exist in User Service yet at this point.
        expect(profileRepository.getMeCallCount, 0);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'OtpVerifyRequested with an invalid code emits AuthOtpVerifyFailure',
      build: () {
        repository.verifyOtpException = const ApiException(
          errorCode: 'OTP_INVALID',
          message: 'Invalid code',
        );
        return build();
      },
      seed: () => const AuthOtpSent(
        mobile: '+919876543210',
        requestId: 'req-1',
        expiresIn: 300,
        resendAfter: 30,
      ),
      act: (bloc) => bloc.add(const OtpVerifyRequested('000000')),
      expect: () => [
        const AuthOtpVerifying(mobile: '+919876543210', requestId: 'req-1'),
        const AuthOtpVerifyFailure(
          mobile: '+919876543210',
          requestId: 'req-1',
          errorCode: 'OTP_INVALID',
          message: 'Invalid code',
        ),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'OtpVerifyRequested without a prior send is a no-op (nothing to verify against)',
      build: build,
      act: (bloc) => bloc.add(const OtpVerifyRequested('123456')),
      expect: () => <AuthState>[],
    );

    blocTest<AuthBloc, AuthState>(
      'OtpVerifyRequested retried after a previous wrong-code failure still verifies',
      build: build,
      seed: () => const AuthOtpVerifyFailure(
        mobile: '+919876543210',
        requestId: 'req-1',
        errorCode: 'OTP_INVALID',
        message: 'Invalid code',
      ),
      act: (bloc) => bloc.add(const OtpVerifyRequested('123456')),
      expect: () => [
        const AuthOtpVerifying(mobile: '+919876543210', requestId: 'req-1'),
        isA<AuthAuthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'OtpVerifyRequested resolves to AuthOtpVerifyFailure, not an uncaught error, '
      'when token storage fails for a non-API reason',
      build: () {
        tokenStorage.saveTokensException = StateError('Keystore unavailable');
        return build();
      },
      seed: () => const AuthOtpSent(
        mobile: '+919876543210',
        requestId: 'req-1',
        expiresIn: 300,
        resendAfter: 30,
      ),
      act: (bloc) => bloc.add(const OtpVerifyRequested('123456')),
      expect: () => [
        const AuthOtpVerifying(mobile: '+919876543210', requestId: 'req-1'),
        isA<AuthOtpVerifyFailure>().having((s) => s.errorCode, 'errorCode', 'UNKNOWN_ERROR'),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthReset returns to AuthInitial',
      build: build,
      seed: () => const AuthOtpSendFailure(
        mobile: '+919876543210',
        errorCode: 'X',
        message: 'x',
      ),
      act: (bloc) => bloc.add(const AuthReset()),
      expect: () => [const AuthInitial()],
    );

    // --- MA-21: login OTP send/verify ---

    blocTest<AuthBloc, AuthState>(
      'LoginOtpSendRequested emits sending then sent on success',
      build: build,
      act: (bloc) => bloc.add(const LoginOtpSendRequested('+919876543210')),
      expect: () => [
        const AuthOtpSending('+919876543210'),
        const AuthOtpSent(
          mobile: '+919876543210',
          requestId: 'login-req-1',
          expiresIn: 300,
          resendAfter: 30,
        ),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'LoginOtpSendRequested with USER_NOT_FOUND emits AuthUserNotFound, not a generic failure',
      build: () {
        repository.sendLoginOtpException = const ApiException(
          errorCode: 'USER_NOT_FOUND',
          message: 'no account',
        );
        return build();
      },
      act: (bloc) => bloc.add(const LoginOtpSendRequested('+919876543210')),
      expect: () => [
        const AuthOtpSending('+919876543210'),
        const AuthUserNotFound('+919876543210'),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'LoginOtpVerifyRequested on success saves tokens, resolves accountType via GET /users/me',
      build: build,
      seed: () => const AuthOtpSent(
        mobile: '+919876543210',
        requestId: 'login-req-1',
        expiresIn: 300,
        resendAfter: 30,
      ),
      act: (bloc) => bloc.add(const LoginOtpVerifyRequested('123456')),
      expect: () => [
        const AuthOtpVerifying(mobile: '+919876543210', requestId: 'login-req-1'),
        const AuthAuthenticated(accountType: 'B2C'),
      ],
      verify: (_) {
        expect(tokenStorage.accessToken, 'login-access-token');
        expect(profileRepository.getMeCallCount, 1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'LoginOtpVerifyRequested succeeds even when GET /users/me fails afterward (FR-4 degrade)',
      build: () {
        profileRepository.getMeException = const ApiException(
          errorCode: 'EXTERNAL_SERVICE_UNAVAILABLE',
          message: 'db down',
        );
        return build();
      },
      seed: () => const AuthOtpSent(
        mobile: '+919876543210',
        requestId: 'login-req-1',
        expiresIn: 300,
        resendAfter: 30,
      ),
      act: (bloc) => bloc.add(const LoginOtpVerifyRequested('123456')),
      expect: () => [
        const AuthOtpVerifying(mobile: '+919876543210', requestId: 'login-req-1'),
        const AuthAuthenticated(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'LoginOtpVerifyRequested with an invalid code emits AuthOtpVerifyFailure',
      build: () {
        repository.verifyLoginOtpException = const ApiException(
          errorCode: 'OTP_INVALID',
          message: 'Invalid code',
        );
        return build();
      },
      seed: () => const AuthOtpSent(
        mobile: '+919876543210',
        requestId: 'login-req-1',
        expiresIn: 300,
        resendAfter: 30,
      ),
      act: (bloc) => bloc.add(const LoginOtpVerifyRequested('000000')),
      expect: () => [
        const AuthOtpVerifying(mobile: '+919876543210', requestId: 'login-req-1'),
        const AuthOtpVerifyFailure(
          mobile: '+919876543210',
          requestId: 'login-req-1',
          errorCode: 'OTP_INVALID',
          message: 'Invalid code',
        ),
      ],
    );

    // --- MA-21: session bootstrap ---

    blocTest<AuthBloc, AuthState>(
      'SessionBootstrapRequested with no stored session lands on AuthInitial',
      build: build,
      act: (bloc) => bloc.add(const SessionBootstrapRequested()),
      expect: () => [const AuthBootstrapping(), const AuthInitial()],
    );

    blocTest<AuthBloc, AuthState>(
      'SessionBootstrapRequested with a still-valid access token skips refresh',
      build: () {
        tokenStorage.refreshToken = 'stored-refresh';
        tokenStorage.accessToken = 'stored-access';
        tokenStorage.accessTokenExpiresAt = DateTime.now().add(const Duration(hours: 1));
        return build();
      },
      act: (bloc) => bloc.add(const SessionBootstrapRequested()),
      expect: () => [const AuthBootstrapping(), const AuthAuthenticated(accountType: 'B2C')],
      verify: (_) => expect(repository.refreshedWith, isEmpty),
    );

    blocTest<AuthBloc, AuthState>(
      'SessionBootstrapRequested with an expired access token silently refreshes first',
      build: () {
        tokenStorage.refreshToken = 'stored-refresh';
        tokenStorage.accessToken = 'stored-access';
        tokenStorage.accessTokenExpiresAt = DateTime.now().subtract(const Duration(hours: 1));
        return build();
      },
      act: (bloc) => bloc.add(const SessionBootstrapRequested()),
      expect: () => [const AuthBootstrapping(), const AuthAuthenticated(accountType: 'B2C')],
      verify: (_) {
        expect(repository.refreshedWith, ['stored-refresh']);
        expect(tokenStorage.accessToken, 'refreshed-access-token');
      },
    );

    blocTest<AuthBloc, AuthState>(
      'SessionBootstrapRequested clears storage and lands on AuthInitial when refresh fails',
      build: () {
        tokenStorage.refreshToken = 'stored-refresh';
        tokenStorage.accessTokenExpiresAt = DateTime.now().subtract(const Duration(hours: 1));
        repository.refreshTokenException = const ApiException(
          errorCode: 'INVALID_REFRESH_TOKEN',
          message: 'expired',
        );
        return build();
      },
      act: (bloc) => bloc.add(const SessionBootstrapRequested()),
      expect: () => [const AuthBootstrapping(), const AuthInitial()],
      verify: (_) => expect(tokenStorage.refreshToken, isNull),
    );

    // --- MA-21: logout ---

    blocTest<AuthBloc, AuthState>(
      'LogoutRequested clears storage and lands on AuthInitial even when the server call fails',
      build: () {
        tokenStorage.refreshToken = 'stored-refresh';
        tokenStorage.accessToken = 'stored-access';
        repository.logoutException = const ApiException(
          errorCode: 'NETWORK_ERROR',
          message: 'timed out',
        );
        return build();
      },
      act: (bloc) => bloc.add(const LogoutRequested()),
      expect: () => [const AuthInitial()],
      verify: (_) {
        expect(repository.loggedOutWith, ['stored-refresh']);
        expect(tokenStorage.accessToken, isNull);
        expect(tokenStorage.refreshToken, isNull);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'LogoutRequested with no stored refresh token still clears storage locally',
      build: build,
      act: (bloc) => bloc.add(const LogoutRequested()),
      expect: () => [const AuthInitial()],
      verify: (_) => expect(repository.loggedOutWith, isEmpty),
    );
  });
}
