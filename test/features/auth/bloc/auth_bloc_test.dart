import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/auth/bloc/auth_bloc.dart';
import 'package:milkful_app/features/auth/bloc/auth_event.dart';
import 'package:milkful_app/features/auth/bloc/auth_state.dart';

import '../../../fakes/fake_auth_repository.dart';
import '../../../fakes/fake_secure_token_storage.dart';

void main() {
  group('AuthBloc', () {
    late FakeAuthRepository repository;
    late FakeSecureTokenStorage tokenStorage;

    setUp(() {
      repository = FakeAuthRepository();
      tokenStorage = FakeSecureTokenStorage();
    });

    AuthBloc build() => AuthBloc(authRepository: repository, tokenStorage: tokenStorage);

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
  });
}
