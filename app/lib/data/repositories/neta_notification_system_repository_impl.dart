import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/domain/entities/query.dart';
import 'package:by_the_people/domain/repositories/repositories.dart';

class NetaRepositoryImpl implements NetaRepository {
  NetaRepositoryImpl(this._api);

  final ApiClient _api;

  List<Neta> _netas(List raw) => raw.map((e) => Neta.fromJson(e)).toList();

  @override
  Future<NetaList> list(ScopeFilter scope) async {
    final j = await _api.get('/netas', query: scope.toQuery());
    return NetaList(_netas(j['items'] as List), (j['parties'] as List).cast<String>());
  }

  @override
  Future<List<Neta>> tree(ScopeFilter scope) async {
    final j = await _api.get('/netas/tree', query: scope.toQuery());
    return _netas(j['roots'] as List);
  }

  @override
  Future<NetaDetail> detail(int id) async {
    final j = await _api.get('/netas/$id');
    List<Issue> issues(String key) => (j[key] as List).map((e) => Issue.fromJson(e)).toList();
    return NetaDetail(
      Neta.fromJson(j['neta']),
      _netas(j['children'] as List),
      issues('openIssues'),
      issues('resolvedIssues'),
    );
  }
}

class NotificationRepositoryImpl implements NotificationRepository {
  NotificationRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<List<AppNotification>> list() async {
    final j = await _api.get('/notifications');
    return (j['items'] as List).map((e) => AppNotification.fromJson(e)).toList();
  }

  @override
  Future<void> markAllRead() => _api.post('/notifications/read', {});
}

class SystemRepositoryImpl implements SystemRepository {
  SystemRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<void> ping() => _api.get('/health');
}
