import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:by_the_people/core/config/env.dart';
import 'package:by_the_people/core/network/api_client.dart';

/// Returns a canned JSON response and remembers the last request it saw.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.status, this.body);

  final int status;
  final Map<String, dynamic> body;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    last = options;
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _client(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local', validateStatus: (_) => true));
  dio.httpClientAdapter = adapter;
  return ApiClient(baseUrl: 'http://test.local', dio: dio);
}

void main() {
  test('returns parsed JSON on success', () async {
    final api = _client(_FakeAdapter(200, {'ok': true}));
    expect(await api.get('/health'), {'ok': true});
  });

  test('attaches the bearer token once set', () async {
    final adapter = _FakeAdapter(200, {});
    final api = _client(adapter)..setToken('abc');
    await api.get('/me');
    expect(adapter.last!.headers['Authorization'], 'Bearer abc');
  });

  test('omits the Authorization header when signed out', () async {
    final adapter = _FakeAdapter(200, {});
    await _client(adapter).get('/meta');
    expect(adapter.last!.headers.containsKey('Authorization'), isFalse);
  });

  test('maps server errors to ApiException with the server message and code', () async {
    final api = _client(_FakeAdapter(422, {'error': 'Title is too short', 'code': 'VALIDATION'}));
    await expectLater(
      api.post('/issues', {'title': 'x'}),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', 'Title is too short')
          .having((e) => e.code, 'code', 'VALIDATION')
          .having((e) => e.status, 'status', 422)),
    );
  });

  test('a 401 on a signed-in request triggers onUnauthorized', () async {
    var fired = false;
    final api = _client(_FakeAdapter(401, {'error': 'Session expired', 'code': 'UNAUTHORIZED'}))
      ..setToken('stale')
      ..onUnauthorized = () => fired = true;
    await expectLater(api.get('/me'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
    expect(fired, isTrue);
  });

  test('bodyless DELETE sends no JSON content-type, bodies do', () async {
    final adapter = _FakeAdapter(200, {});
    final api = _client(adapter);
    await api.delete('/issues/1/like');
    expect(adapter.last!.contentType, isNull);
    await api.post('/issues/1/like');
    expect(adapter.last!.contentType, contains('json'));
  });

  test('default API URL is localhost when nothing is configured', () {
    expect(Env.apiBaseUrl, 'http://localhost:3000');
  });
}
