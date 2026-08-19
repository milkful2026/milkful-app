import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_token_storage.dart';
import '../data/auth_repository.dart';
import '../data/profile_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({
    required AuthRepository authRepository,
    required SecureTokenStorage tokenStorage,
    required ProfileRepository profileRepository,
  })  : _authRepository = authRepository,
        _tokenStorage = tokenStorage,
        _profileRepository = profileRepository,
        super(const AuthInitial()) {
    on<OtpSendRequested>(_onOtpSendRequested);
    on<OtpResendRequested>(_onOtpSendRequested);
    on<OtpVerifyRequested>(_onOtpVerifyRequested);
    on<LoginOtpSendRequested>(_onLoginOtpSendRequested);
    on<LoginOtpResendRequested>(_onLoginOtpSendRequested);
    on<LoginOtpVerifyRequested>(_onLoginOtpVerifyRequested);
    on<SessionBootstrapRequested>(_onSessionBootstrapRequested);
    on<LogoutRequested>(_onLogoutRequested);
    on<ProfileRefreshRequested>(_onProfileRefreshRequested);
    on<AuthReset>((event, emit) => emit(const AuthInitial()));
  }

  final AuthRepository _authRepository;
  final SecureTokenStorage _tokenStorage;
  final ProfileRepository _profileRepository;

  Future<void> _onOtpSendRequested(AuthEvent event, Emitter<AuthState> emit) async {
    final mobile = switch (event) {
      OtpSendRequested(:final mobile) => mobile,
      OtpResendRequested(:final mobile) => mobile,
      _ => throw StateError('unreachable'),
    };
    emit(AuthOtpSending(mobile, flow: OtpFlow.registration));
    try {
      final result = await _authRepository.sendOtp(mobile);
      emit(
        AuthOtpSent(
          mobile: mobile,
          requestId: result.requestId,
          expiresIn: result.expiresIn,
          resendAfter: result.resendAfter,
          flow: OtpFlow.registration,
        ),
      );
    } on ApiException catch (e) {
      if (e.errorCode == 'USER_EXISTS') {
        emit(AuthUserAlreadyExists(mobile));
      } else {
        emit(
          AuthOtpSendFailure(
            mobile: mobile,
            errorCode: e.errorCode,
            message: e.message,
            flow: OtpFlow.registration,
          ),
        );
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
      // No GET /users/me here — this path is registration's own OTP
      // verify, and the user doesn't exist in User Service yet at this
      // point (POST /users/register hasn't run). accountType is resolved
      // later, after registration actually completes (see
      // _onLoginOtpVerifyRequested for the login-flow equivalent, where
      // the user is guaranteed to already exist).
      emit(const AuthAuthenticated());
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

  Future<void> _onLoginOtpSendRequested(AuthEvent event, Emitter<AuthState> emit) async {
    final mobile = switch (event) {
      LoginOtpSendRequested(:final mobile) => mobile,
      LoginOtpResendRequested(:final mobile) => mobile,
      _ => throw StateError('unreachable'),
    };
    emit(AuthOtpSending(mobile, flow: OtpFlow.login));
    try {
      final result = await _authRepository.sendLoginOtp(mobile);
      emit(
        AuthOtpSent(
          mobile: mobile,
          requestId: result.requestId,
          expiresIn: result.expiresIn,
          resendAfter: result.resendAfter,
          flow: OtpFlow.login,
        ),
      );
    } on ApiException catch (e) {
      if (e.errorCode == 'USER_NOT_FOUND') {
        emit(AuthUserNotFound(mobile));
      } else {
        emit(
          AuthOtpSendFailure(
            mobile: mobile,
            errorCode: e.errorCode,
            message: e.message,
            flow: OtpFlow.login,
          ),
        );
      }
    }
  }

  Future<void> _onLoginOtpVerifyRequested(
    LoginOtpVerifyRequested event,
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
      final tokens = await _authRepository.verifyLoginOtp(
        mobile: mobile,
        otp: event.otp,
        requestId: requestId,
      );
      await _tokenStorage.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        accessTokenExpiresAt: tokens.expiresAt,
      );
      final profile = await _resolveProfile();
      emit(AuthAuthenticated(accountType: profile.accountType, name: profile.name));
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

  Future<void> _onSessionBootstrapRequested(
    SessionBootstrapRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthBootstrapping());
    // Both reads are independent secure-storage lookups — fire them off
    // together instead of paying two sequential round-trips on every cold
    // start. The refreshToken future is awaited first since its null-ness
    // gates everything else; expiresAt has already been in flight the
    // whole time either way. catchError is attached immediately (not just
    // when we later await it) so a failing read can't surface as an
    // unhandled zone error on the no-refresh-token early-return path below.
    final refreshTokenFuture = _tokenStorage.readRefreshToken();
    final expiresAtFuture = _tokenStorage.readAccessTokenExpiresAt().catchError((_) => null);
    final refreshToken = await refreshTokenFuture;
    if (refreshToken == null) {
      emit(const AuthInitial());
      return;
    }

    final expiresAt = await expiresAtFuture;
    final needsRefresh = expiresAt == null || !DateTime.now().isBefore(expiresAt);
    if (needsRefresh) {
      try {
        final tokens = await _authRepository.refreshToken(refreshToken);
        await _tokenStorage.saveTokens(
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          accessTokenExpiresAt: tokens.expiresAt,
        );
      } catch (_) {
        // FR-3: refresh failure clears storage and routes to the entry
        // screen — no error dialog, just a clean re-auth prompt.
        await _tokenStorage.clear();
        emit(const AuthInitial());
        return;
      }
    }
    final profile = await _resolveProfile();
    emit(AuthAuthenticated(accountType: profile.accountType, name: profile.name));
  }

  Future<void> _onLogoutRequested(LogoutRequested event, Emitter<AuthState> emit) async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken != null) {
      try {
        await _authRepository.logout(refreshToken);
      } catch (_) {
        // FR-5: a failed/timed-out server-side revoke must never trap the
        // user in a logged-in-looking state — local logout proceeds
        // regardless.
      }
    }
    await _tokenStorage.clear();
    emit(const AuthInitial());
  }

  /// Dispatched right after registration finishes — the only way this
  /// bloc's own `name`/`accountType` catch up on the fresh-signup path,
  /// since `_onOtpVerifyRequested` deliberately skips the profile lookup
  /// (the profile doesn't exist yet at that point). A no-op unless already
  /// authenticated.
  Future<void> _onProfileRefreshRequested(
    ProfileRefreshRequested event,
    Emitter<AuthState> emit,
  ) async {
    if (state is! AuthAuthenticated) return;
    final profile = await _resolveProfile();
    emit(AuthAuthenticated(accountType: profile.accountType, name: profile.name));
  }

  /// FR-4: a failed profile lookup must never block reaching Home —
  /// returns nulls (degrades to a B2C-equivalent, name-less view) instead
  /// of propagating.
  Future<({String? accountType, String? name})> _resolveProfile() async {
    try {
      final profile = await _profileRepository.getMe();
      return (accountType: profile.accountType, name: profile.name);
    } catch (_) {
      return (accountType: null, name: null);
    }
  }
}
