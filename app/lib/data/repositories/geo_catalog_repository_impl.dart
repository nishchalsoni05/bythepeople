import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/domain/entities/query.dart';
import 'package:by_the_people/domain/repositories/repositories.dart';
import 'package:by_the_people/data/repositories/mapping.dart';

class GeoRepositoryImpl implements GeoRepository {
  GeoRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<List<Area>> areas() async {
    final j = await _api.get('/geo/areas');
    final out = <Area>[];
    for (final r in j['regions'] as List) {
      out.add(Area(r['id'], r['name'], 'region', null));
      for (final s in r['states'] as List) {
        out.add(Area(s['id'], s['name'], 'state', r['id']));
        for (final c in s['cities'] as List) {
          out.add(Area(c['id'], c['name'], 'city', s['id']));
        }
      }
    }
    return out;
  }

  @override
  Future<Map<String, dynamic>?> resolve(GeoPoint at) =>
      _api.get('/geo/resolve', query: geoQuery(at));

  @override
  Future<ScopeSummary> summary(ScopeFilter scope, {GeoPoint? at}) async =>
      ScopeSummary.fromJson(await _api.get('/geo/summary', query: {...scope.toQuery(), ...geoQuery(at)}));
}

class CatalogRepositoryImpl implements CatalogRepository {
  CatalogRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<List<CategoryInfo>> categories() async {
    final j = await _api.get('/meta');
    return (j['categories'] as List).map((e) => CategoryInfo.fromJson(e)).toList();
  }
}
