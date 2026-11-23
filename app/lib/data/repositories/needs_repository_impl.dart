import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/domain/entities/need.dart';
import 'package:by_the_people/domain/repositories/needs_repository.dart';

class NeedsRepositoryImpl implements NeedsRepository {
  NeedsRepositoryImpl(this._api);
  final ApiClient _api;

  Map<String, dynamic> _m(dynamic v) => Map<String, dynamic>.from(v as Map);

  Need _need(Map<String, dynamic> j) => Need.fromJson(_m(j['need'] ?? j));

  @override
  Future<List<Need>> list({String status = 'open'}) async {
    final j = await _api.get('/needs', query: {'status': status});
    return ((j['items'] ?? const []) as List).map((e) => Need.fromJson(_m(e))).toList();
  }

  @override
  Future<Need> create(NeedDraft draft) async => _need(await _api.post('/needs', draft.toJson()));

  @override
  Future<Need> pledge(int id, {String? note}) async =>
      _need(await _api.post('/needs/$id/pledge', {if (note != null && note.isNotEmpty) 'note': note}));

  @override
  Future<Need> unpledge(int id) async => _need(await _api.delete('/needs/$id/pledge'));

  @override
  Future<Need> close(int id) async => _need(await _api.post('/needs/$id/close'));
}
