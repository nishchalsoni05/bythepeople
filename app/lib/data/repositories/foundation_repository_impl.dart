import 'dart:convert';

import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/domain/entities/foundation.dart';
import 'package:by_the_people/domain/repositories/welfare_repositories.dart';

class FoundationRepositoryImpl implements FoundationRepository {
  FoundationRepositoryImpl(this._api);
  final ApiClient _api;

  @override
  Future<List<Foundation>> list({String? query, String? need}) async {
    final j = await _api.get('/foundations', query: {if (query != null && query.isNotEmpty) 'q': query, 'need': need});
    return ((j['items'] ?? const []) as List).map((e) => Foundation.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  @override
  Future<Foundation> detail(int id) async {
    final j = await _api.get('/foundations/$id');
    return Foundation.fromJson(Map<String, dynamic>.from((j['foundation'] ?? j) as Map));
  }

  @override
  Future<FoundationDashboard> dashboard() async => FoundationDashboard.fromJson(await _api.get('/foundation/dashboard'));
}

class MediaRepositoryImpl implements MediaRepository {
  MediaRepositoryImpl(this._api);
  final ApiClient _api;

  @override
  Future<String> upload(List<int> bytes, String mime) async {
    final j = await _api.post('/media', {'dataBase64': base64Encode(bytes), 'mime': mime});
    return (j['url'] ?? '').toString();
  }
}
