import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/data/repositories/mapping.dart';
import 'package:by_the_people/domain/entities/club.dart';
import 'package:by_the_people/domain/entities/comment.dart';
import 'package:by_the_people/domain/entities/gathering.dart';
import 'package:by_the_people/domain/entities/query.dart';
import 'package:by_the_people/domain/repositories/welfare_repositories.dart';

class GatheringRepositoryImpl implements GatheringRepository {
  GatheringRepositoryImpl(this._api);
  final ApiClient _api;

  Map<String, dynamic> _m(dynamic v) => Map<String, dynamic>.from(v as Map);

  Outcome<Gathering> _out(Map<String, dynamic> j) {
    final g = j['gathering'] ?? j['item'] ?? j;
    return Outcome(Gathering.fromJson(_m(g)), j['rewards'] is Map ? _m(j['rewards']) : null);
  }

  @override
  Future<List<Gathering>> list({String when = 'upcoming', String? type, int? clubId, String sort = 'soon', String? query, GeoPoint? at}) async {
    final j = await _api.get('/gatherings', query: {
      'when': when,
      'type': type,
      'club': clubId,
      'sort': sort,
      if (query != null && query.isNotEmpty) 'q': query,
      ...geoQuery(at),
    });
    return ((j['items'] ?? const []) as List).map((e) => Gathering.fromJson(_m(e))).toList();
  }

  @override
  Future<Gathering> detail(int id, {GeoPoint? at}) async {
    final j = await _api.get('/gatherings/$id', query: geoQuery(at));
    return Gathering.fromJson(_m(j['gathering'] ?? j));
  }

  @override
  Future<Outcome<Gathering>> create(GatheringDraft d) async => _out(await _api.post('/gatherings', d.toJson()));
  @override
  Future<Outcome<Gathering>> rsvp(int id) async => _out(await _api.post('/gatherings/$id/rsvp'));
  @override
  Future<Outcome<Gathering>> unrsvp(int id) async => _out(await _api.delete('/gatherings/$id/rsvp'));
  @override
  Future<Outcome<Gathering>> vote(int id) async => _out(await _api.post('/gatherings/$id/vote'));
  @override
  Future<Outcome<Gathering>> unvote(int id) async => _out(await _api.delete('/gatherings/$id/vote'));
  @override
  Future<Outcome<Gathering>> checkIn(int id, GeoPoint at) async =>
      _out(await _api.post('/gatherings/$id/checkin', {'lat': at.lat, 'lng': at.lng}));
  @override
  Future<Outcome<Gathering>> complete(int id, String note) async => _out(await _api.post('/gatherings/$id/complete', {'note': note}));
  @override
  Future<Outcome<Gathering>> cancel(int id) async => _out(await _api.post('/gatherings/$id/cancel'));
  @override
  Future<Outcome<Gathering>> like(int id) async => _out(await _api.post('/gatherings/$id/like'));
  @override
  Future<Outcome<Gathering>> unlike(int id) async => _out(await _api.delete('/gatherings/$id/like'));

  @override
  Future<List<Comment>> comments(int id) async {
    final j = await _api.get('/gatherings/$id/comments');
    return ((j['items'] ?? const []) as List).map((e) => Comment.fromJson(_m(e))).toList();
  }

  @override
  Future<void> addComment(int id, String body) async {
    await _api.post('/gatherings/$id/comments', {'body': body});
  }

  @override
  Future<ShareInfo> share(int id) async => ShareInfo.fromJson(await _api.post('/gatherings/$id/share'));

  @override
  Future<Map<String, List<GatheringLite>>> calendar(String month) async {
    final j = await _api.get('/gatherings/calendar', query: {'month': month});
    final days = (j['days'] ?? const {}) as Map;
    return {
      for (final e in days.entries) '${e.key}': ((e.value ?? const []) as List).map((x) => GatheringLite.fromJson(_m(x))).toList(),
    };
  }

  @override
  Future<List<Club>> clubs() async {
    final j = await _api.get('/clubs');
    return ((j['items'] ?? const []) as List).map((e) => Club.fromJson(_m(e))).toList();
  }

  @override
  Future<ClubDetail> club(int id) async {
    final j = await _api.get('/clubs/$id');
    final clubJson = _m(j['club'] ?? j);
    return ClubDetail(
      Club.fromJson(clubJson),
      ((j['members'] ?? clubJson['members'] ?? const []) as List).map((e) => PersonRef.fromJson(_m(e))).toList(),
      ((j['upcoming'] ?? j['gatherings'] ?? clubJson['upcoming'] ?? const []) as List).map((e) => Gathering.fromJson(_m(e))).toList(),
    );
  }

  @override
  Future<Club> createClub(String name, String description, String category) async {
    final j = await _api.post('/clubs', {'name': name, 'description': description, 'category': category});
    return Club.fromJson(_m(j['club'] ?? j));
  }

  @override
  Future<void> joinClub(int id) async {
    await _api.post('/clubs/$id/join');
  }

  @override
  Future<void> leaveClub(int id) async {
    await _api.delete('/clubs/$id/join');
  }
}
