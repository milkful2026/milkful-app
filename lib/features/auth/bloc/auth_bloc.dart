import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_token_storage.dart';
import '../data/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required AuthRepository authRepository,
    required SecureTokenStorage tokenStorage,
  })  : _authRepository = authRepository,
        _tokenStorage = tokenStorage,
        super(const AuthInitial()) {
    on<OtpSendRequested>(_onOtpSendRequested);
    on<OtpResendRequested>(_onOtpSendRequested);
    on<OtpVerifyRequested>(_onOtpVerifyRequested);
    on<AuthReset>((event, emit) => emit(const AuthInitial()));
  }

  final AuthRepository _authRepository;
  final SecureTokenStorage _tokenStorage;

  Future<void> _onOtpSendRequested(AuthEvent event, Emitter<AuthState> emit) async {
    final mobile = switch (event) {
      OtpSendRequested(:final mobile) => mobile,
      OtpResendRequested(:final mobile) => mobile,
      _ => throw StateError('unreachable'),
    };
    emit(AuthOtpSending(mobile));
    try {
      final result = await _authRepository.sendOtp(mobile);
      emit(
        AuthOtpSent(
          mobile: mobile,
          requestId: result.requestId,
          expiresIn: result.expiresIn,
          resendAfter: result.resendAfter,
        ),
      );
    } on ApiException catch (e) {
      if (e.errorCode == 'USER_EXISTS') {
        emit(AuthUserAlreadyExists(mobile));
      } else {
        emit(AuthOtpSendFailure(mobile: mobile, errorCode: e.errorCode, message: e.message));
      }
    }
  }

  Future<void> _onOtpVerifyRequested(
    OtpVerifyRequested event,
    Emitter<AuthState> emit,
  ) async {
    final (mobile, requestId) = switch (state) {
      AuthOtpSent(:final mobile, :final requestId) => (mobile, requestId),
      AuthOtpVerifyFailure(:final mobile, :final requestId) => (mobile, requestId),
      _ => (null, null),
    };
    if (mobile == null || requestId == null) return;

    emit(AuthOtpVerifying(mobile: mobile, requestId: requestId));
    try {
      final tokens = await _authRepository.verifyOtp(
        mobile: mobile,
        otp: event.otp,
        requestId: requestId,
      );
      await _tokenStorage.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        accessTokenExpiresAt: tokens.expiresAt,
      );
      emit(AuthAuthenticated(tokens));
    } on ApiException catch (e) {
      emit(
        AuthOtpVerifyFailure(
          mobile: mobile,
          requestId: requestId,
          errorCode: e.errorCode,
          message: e.message,
        ),
      );
    } catch (_) {
      // Non-API failures (e.g. secure-storage write errors, malformed
      // token responses) must still resolve the pending spinner state.
      emit(
        AuthOtpVerifyFailure(
          mobile: mobile,
          requestId: requestId,
          errorCode: 'UNKNOWN_ERROR',
          message: 'Something went wrong. Please try again.',
        ),
      );
    }
  }
}
