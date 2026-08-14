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
    final current = state;
    if (current is! AuthOtpSent) return;

    emit(AuthOtpVerifying(mobile: current.mobile, requestId: current.requestId));
    try {
      final tokens = await _authRepository.verifyOtp(
        mobile: current.mobile,
        otp: event.otp,
        requestId: current.requestId,
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
          mobile: current.mobile,
          requestId: current.requestId,
          errorCode: e.errorCode,
          message: e.message,
        ),
      );
    }
  }
}
