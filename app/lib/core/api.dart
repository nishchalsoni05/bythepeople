import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final String message, code;
  final int status;
  final Map<String, dynamic> extra;
  ApiException(this.message, this.code, this.status, [this.extra = const {}]);
  @override
  String toString() => message;
}

class ApiClient {
  String? token;
  void Function()? onUnauthorized;
  late final String baseUrl;
  final http.Client _c = http.Client();

  ApiClient() {
    const override = String.fromEnvironment('API_URL');
    baseUrl = override.isNotEmpty ? override : (Platform.isAndroid ? 'http://10.0.2.2:3000' : 'http://localhost:3000');
  }

  Future<void> loadToken() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString('token');
  }

  Future<void> saveToken(String? t) async {
    token = t;
    final p = await SharedPreferences.getInstance();
    if (t == null) {
      await p.remove('token');
    } else {
      await p.setString('token', t);
    }
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _send(String method, String path, {Map<String, dynamic>? query, Object? body}) async {
    var uri = Uri.parse('$baseUrl$path');
    if (query != null) {
      uri = uri.replace(queryParameters: {
        for (final e in query.entries)
          if (e.value != null) e.key: e.value.toString(),
      });
    }
    http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(_headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(await _c.send(req).timeout(const Duration(seconds: 12)));
    } catch (_) {
      throw ApiException('Cannot reach the server. Is the backend running?', 'NETWORK', 0);
    }
    final data = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 401 && token != null) onUnauthorized?.call();
    if (res.statusCode >= 400) {
      throw ApiException(data['error']?.toString() ?? 'Request failed', data['code']?.toString() ?? 'ERROR', res.statusCode, data);
    }
    return data;
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) => _send('GET', path, query: query);
  Future<Map<String, dynamic>> post(String path, [Object? body]) => _send('POST', path, body: body ?? {});
  Future<Map<String, dynamic>> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);
}
