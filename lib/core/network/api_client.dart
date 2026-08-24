import 'package:dio/dio.dart';

import '../utils/id_generator.dart';

/// Thrown for both a real backend error envelope
/// (`{"requestId","status":"error","data":{"errorCode","message"}}`) and
/// for transport-level failures (no response at all) — callers switch on
/// [errorCode] the same way either way.
class ApiException implements Exception {
  const ApiException({
    required this.errorCode,
    required this.message,
    this.statusCode,
  });

  final String errorCode;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($errorCode): $message';
}

typedef AccessTokenProvider = Future<String?> Function();

/// Thin, shared Dio wrapper: injects `X-Request-Id` and (when a provider is
/// supplied) `Authorization: Bearer <token>` on every request, and unwraps
/// the backend's fixed `{"requestId","status","data"}` envelope centrally —
/// see services/README.md §5 — so no repository touches the envelope shape
/// directly. One instance is shared by every feature repository.
class ApiClient {
  ApiClient({
    AccessTokenProvider? accessTokenProvider,
    Duration timeout = const Duration(seconds: 10),
  }) : _dio = Dio(
         BaseOptions(connectTimeout: timeout, receiveTimeout: timeout),
       ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          options.headers['X-Request-Id'] = newHexId();
          if (accessTokenProvider != null) {
            final token = await accessTokenProvider();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;

  /// Returns the envelope's raw, unwrapped `data` field — a `Map` for
  /// every endpoint except /delivery/slots (a bare JSON array), and `null`
  /// for a body-less response (e.g. logout's 204 No Content).
  Future<dynamic> _requestRaw(
    String method,
    String url, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.request<dynamic>(
        url,
        data: body,
        queryParameters: queryParameters,
        options: Options(method: method, headers: headers),
      );
      final envelope = response.data;
      if (envelope is Map<String, dynamic>) return envelope['data'];
      return null;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// For every endpoint whose `data` is a JSON object. See [requestList]
  /// for the one endpoint (/delivery/slots) where it's a bare array.
  /// [headers] are additive to (never replace) the interceptor's own
  /// `X-Request-Id`/`Authorization` injection above — e.g. an
  /// `Idempotency-Key` a specific call site needs to set.
  Future<Map<String, dynamic>> request(
    String method,
    String url, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    final data = await _requestRaw(
      method,
      url,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
    );
    return data is Map<String, dynamic> ? data : const {};
  }

  Future<List<dynamic>> requestList(
    String method,
    String url, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final data = await _requestRaw(
      method,
      url,
      queryParameters: queryParameters,
    );
    return data is List ? data : const [];
  }

  ApiException _mapError(DioException e) {
    final response = e.response;
    final envelope = response?.data;
    if (envelope is Map<String, dynamic>) {
      final data = envelope['data'];
      if (data is Map<String, dynamic>) {
        return ApiException(
          errorCode: data['errorCode'] as String? ?? 'UNKNOWN_ERROR',
          message: data['message'] as String? ?? 'Something went wrong',
          statusCode: response?.statusCode,
        );
      }
    }
    return ApiException(
      errorCode: 'NETWORK_ERROR',
      message: e.message ?? 'Could not reach the server',
      statusCode: response?.statusCode,
    );
  }
}
