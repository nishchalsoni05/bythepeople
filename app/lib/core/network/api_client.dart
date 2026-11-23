import 'package:dio/dio.dart';

import 'package:by_the_people/core/config/env.dart';
import 'package:by_the_people/core/logging/app_logger.dart';

/// A failed backend call. [code] is the server's machine-readable code, or `NETWORK` when unreachable.
class ApiException implements Exception {
  final String message;
  final String code;
  final int status;
  final Map<String, dynamic> extra;

  const ApiException(this.message, this.code, this.status, [this.extra = const {}]);

  bool get isNetwork => code == 'NETWORK';

  @override
  String toString() => message;
}

/// Thin JSON client over Dio. Owns the bearer token, timeouts and error mapping.
class ApiClient {
  ApiClient({required String baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: _timeout,
              sendTimeout: _timeout,
              receiveTimeout: _timeout,
              responseType: ResponseType.json,
              headers: const {'Accept': 'application/json'},
              // We read error bodies ourselves, so Dio must not throw on 4xx/5xx.
              validateStatus: (_) => true,
            )) {
    _dio.interceptors.add(_AuthInterceptor(this));
    if (Env.httpLogging) _dio.interceptors.add(_HttpLogInterceptor());
  }

  static const _timeout = Duration(seconds: 12);

  final Dio _dio;
  String? _token;

  /// Called when the server rejects a signed-in request with 401 (expired or reset session).
  void Function()? onUnauthorized;

  String? get token => _token;
  void setToken(String? token) => _token = token;

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) => _send('GET', path, query: query);

  Future<Map<String, dynamic>> post(String path, [Object? body]) => _send('POST', path, body: body ?? const {});

  Future<Map<String, dynamic>> patch(String path, Object body) => _send('PATCH', path, body: body);

  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  Future<Map<String, dynamic>> _send(String method, String path, {Map<String, dynamic>? query, Object? body}) async {
    final Response<dynamic> res;
    try {
      res = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: _withoutNulls(query),
        // Only declare a JSON body when there is one: bodyless DELETE/GET must not carry a content-type.
        options: Options(method: method, contentType: body == null ? null : Headers.jsonContentType),
      );
    } on DioException catch (e) {
      appLogger.w('$method $path: network failure (${e.type.name})');
      throw const ApiException('Cannot reach the server. Is the backend running?', 'NETWORK', 0);
    }

    final status = res.statusCode ?? 0;
    final data = _asMap(res.data);
    if (status == 401 && _token != null) onUnauthorized?.call();
    if (status >= 400) {
      throw ApiException(
        data['error']?.toString() ?? 'Request failed',
        data['code']?.toString() ?? 'ERROR',
        status,
        data,
      );
    }
    return data;
  }

  static Map<String, dynamic>? _withoutNulls(Map<String, dynamic>? query) =>
      query == null ? null : {for (final e in query.entries) if (e.value != null) e.key: e.value};

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }
}

/// Attaches the bearer token to every request made while signed in.
class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._client);

  final ApiClient _client;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _client.token;
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }
}

/// Logs method, path and status only. Headers and bodies are never logged, so tokens and personal data stay out of logs.
class _HttpLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    appLogger.d('-> ${options.method} ${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    appLogger.d('<- ${response.statusCode} ${response.requestOptions.method} ${response.requestOptions.path}');
    handler.next(response);
  }
}
