import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/data/repositories/mapping.dart';
import 'package:by_the_people/domain/entities/comment.dart';
import 'package:by_the_people/domain/entities/donation.dart';
import 'package:by_the_people/domain/entities/query.dart';
import 'package:by_the_people/domain/repositories/welfare_repositories.dart';

class DonationRepositoryImpl implements DonationRepository {
  DonationRepositoryImpl(this._api);
  final ApiClient _api;

  Map<String, dynamic> _m(dynamic v) => Map<String, dynamic>.from(v as Map);

  Outcome<Donation> _out(Map<String, dynamic> j) =>
      Outcome(Donation.fromJson(_m(j['donation'] ?? j['item'] ?? j)), j['rewards'] is Map ? _m(j['rewards']) : null);

  @override
  Future<List<Donation>> list({String? kind, String status = 'available', String sort = 'expiring', GeoPoint? at}) async {
    final j = await _api.get('/donations', query: {'kind': kind, 'status': status, 'sort': sort, ...geoQuery(at)});
    return ((j['items'] ?? const []) as List).map((e) => Donation.fromJson(_m(e))).toList();
  }

  @override
  Future<Donation> detail(int id, {GeoPoint? at}) async {
    final j = await _api.get('/donations/$id', query: geoQuery(at));
    return Donation.fromJson(_m(j['donation'] ?? j));
  }

  @override
  Future<Outcome<Donation>> create(DonationDraft d) async => _out(await _api.post('/donations', d.toJson()));
  @override
  Future<Outcome<Donation>> claim(int id, int etaMinutes) async => _out(await _api.post('/donations/$id/claim', {'etaMinutes': etaMinutes}));
  @override
  Future<Outcome<Donation>> release(int id) async => _out(await _api.post('/donations/$id/release'));
  @override
  Future<Outcome<Donation>> pickup(int id) async => _out(await _api.post('/donations/$id/pickup'));
  @override
  Future<Outcome<Donation>> distribute(int id, {required String note, required int beneficiaries, List<String> media = const []}) async =>
      _out(await _api.post('/donations/$id/distribute', {'note': note, 'beneficiaries': beneficiaries, if (media.isNotEmpty) 'media': media}));
  @override
  Future<Outcome<Donation>> cancel(int id) async => _out(await _api.post('/donations/$id/cancel'));
  @override
  Future<Outcome<Donation>> like(int id) async => _out(await _api.post('/donations/$id/like'));
  @override
  Future<Outcome<Donation>> unlike(int id) async => _out(await _api.delete('/donations/$id/like'));

  @override
  Future<List<Comment>> comments(int id) async {
    final j = await _api.get('/donations/$id/comments');
    return ((j['items'] ?? const []) as List).map((e) => Comment.fromJson(_m(e))).toList();
  }

  @override
  Future<void> addComment(int id, String body) async {
    await _api.post('/donations/$id/comments', {'body': body});
  }

  @override
  Future<ShareInfo> share(int id) async => ShareInfo.fromJson(await _api.post('/donations/$id/share'));

  @override
  Future<List<Donation>> mine() async {
    final j = await _api.get('/me/donations');
    return ((j['items'] ?? const []) as List).map((e) => Donation.fromJson(_m(e))).toList();
  }
}
