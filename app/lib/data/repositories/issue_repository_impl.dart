import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/domain/entities/portal.dart';
import 'package:by_the_people/domain/entities/query.dart';
import 'package:by_the_people/domain/repositories/repositories.dart';
import 'package:by_the_people/data/repositories/mapping.dart';

class IssueRepositoryImpl implements IssueRepository {
  IssueRepositoryImpl(this._api);

  final ApiClient _api;

  List<Issue> _issues(Map<String, dynamic> j) => (j['items'] as List).map((e) => Issue.fromJson(e)).toList();

  Map<String, dynamic> _at(GeoPoint p) => {'lat': p.lat, 'lng': p.lng};

  @override
  Future<List<Issue>> feed({
    required ScopeFilter scope,
    required String phase,
    required String sort,
    String? category,
    String query = '',
    GeoPoint? at,
  }) async =>
      _issues(await _api.get('/issues', query: {
        ...scope.toQuery(),
        'phase': phase,
        'sort': sort,
        if (category != null) 'category': category,
        if (query.isNotEmpty) 'q': query,
        ...geoQuery(at),
      }));

  @override
  Future<Issue> detail(int id, {GeoPoint? at}) async {
    final j = await _api.get('/issues/$id', query: geoQuery(at));
    return Issue.fromJson(j['issue']);
  }

  @override
  Future<List<Issue>> activity(String type, {GeoPoint? at}) async =>
      _issues(await _api.get('/me/activity', query: {'type': type, ...geoQuery(at)}));

  @override
  Future<List<Issue>> similar(GeoPoint at, String category) async =>
      _issues(await _api.get('/issues/similar', query: {..._at(at), 'category': category}));

  @override
  Future<ActionResult> support(int id, GeoPoint at) async =>
      ActionResult.fromJson(await _api.post('/issues/$id/support', _at(at)));

  @override
  Future<ActionResult> withdraw(int id) async => ActionResult.fromJson(await _api.delete('/issues/$id/support'));

  @override
  Future<ActionResult> join(int id, GeoPoint at) async =>
      ActionResult.fromJson(await _api.post('/events/$id/join', _at(at)));

  @override
  Future<ActionResult> leave(int id) async => ActionResult.fromJson(await _api.delete('/events/$id/join'));

  @override
  Future<ActionResult> resolve(int id, GeoPoint at, String note) async =>
      ActionResult.fromJson(await _api.post('/events/$id/resolve', {..._at(at), 'note': note}));

  @override
  Future<ActionResult> verify(int id, GeoPoint at, bool approve) async =>
      ActionResult.fromJson(await _api.post('/events/$id/verify', {..._at(at), 'approve': approve}));

  @override
  Future<ActionResult> schedule(int id, DateTime at) async => ActionResult.fromJson(
      await _api.post('/events/$id/schedule', {'scheduledAt': at.millisecondsSinceEpoch}));

  @override
  Future<ActionResult> report(ReportDraft draft, GeoPoint userAt) async => ActionResult.fromJson(await _api.post('/issues', {
        'title': draft.title,
        'category': draft.category,
        'description': draft.description,
        'lat': draft.location.lat,
        'lng': draft.location.lng,
        'userLat': userAt.lat,
        'userLng': userAt.lng,
        if (draft.linkTo != null) 'linkTo': draft.linkTo,
        if (draft.address != null) 'address': draft.address,
        if (draft.media.isNotEmpty) 'media': draft.media,
      }));

  @override
  Future<Issue> like(int id) async => Issue.fromJson((await _api.post('/issues/$id/like'))['issue']);

  @override
  Future<Issue> unlike(int id) async => Issue.fromJson((await _api.delete('/issues/$id/like'))['issue']);

  @override
  Future<List<IssueComment>> comments(int id) async => ((await _api.get('/issues/$id/comments'))['items'] as List)
      .map((e) => IssueComment.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();

  @override
  Future<void> addComment(int id, String body, {List<String> media = const []}) async {
    await _api.post('/issues/$id/comments', {'body': body, if (media.isNotEmpty) 'media': media});
  }

  @override
  Future<ShareInfo> share(int id) async => ShareInfo.fromJson(await _api.post('/issues/$id/share'));
}
