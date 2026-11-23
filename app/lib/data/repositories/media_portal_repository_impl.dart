import 'dart:convert';
import 'dart:typed_data';

import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/domain/entities/portal.dart';
import 'package:by_the_people/domain/repositories/repositories.dart';

class MediaUploadRepositoryImpl implements MediaUploadRepository {
  MediaUploadRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<String> upload(Uint8List bytes, String mime) async {
    final j = await _api.post('/media', {'dataBase64': base64Encode(bytes), 'mime': mime});
    return j['url'] as String;
  }
}

class PortalRepositoryImpl implements PortalRepository {
  PortalRepositoryImpl(this._api);

  final ApiClient _api;

  List<Issue> _issues(Map<String, dynamic> j) =>
      ((j['items'] ?? const []) as List).map((e) => Issue.fromJson(Map<String, dynamic>.from(e as Map))).toList();

  @override
  Future<AdminDashboard> adminDashboard() async => AdminDashboard.fromJson(await _api.get('/admin/dashboard'));

  @override
  Future<List<Issue>> adminIssues({String? status, String? q, bool? escalated, String? category, String sort = 'default'}) async =>
      _issues(await _api.get('/admin/issues', query: {
        'status': status,
        if (q != null && q.isNotEmpty) 'q': q,
        if (escalated == true) 'escalated': 1,
        'category': category,
        if (sort != 'default') 'sort': sort,
      }));

  @override
  Future<ActionResult> authorityUpdate(int id, {required String status, String? note, String? assignedTo, List<String> media = const []}) async =>
      ActionResult.fromJson(await _api.post('/issues/$id/authority-update', {
        'status': status,
        if (note != null && note.isNotEmpty) 'note': note,
        if (assignedTo != null && assignedTo.isNotEmpty) 'assignedTo': assignedTo,
        if (media.isNotEmpty) 'media': media,
      }));

  @override
  Future<List<FoundationRow>> foundations(String status) async =>
      ((await _api.get('/admin/foundations', query: {'status': status}))['items'] as List)
          .map((e) => FoundationRow.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

  @override
  Future<void> verifyFoundation(int id, bool approve, {String? note}) async {
    await _api.post('/admin/foundations/$id/verify', {'approve': approve, if (note != null && note.isNotEmpty) 'note': note});
  }

  @override
  Future<NetaDashboard> netaDashboard() async => NetaDashboard.fromJson(await _api.get('/neta/dashboard'));

  @override
  Future<List<Issue>> netaFeed({String? status, String sort = 'top'}) async =>
      _issues(await _api.get('/neta/feed', query: {'status': status, 'sort': sort}));

  @override
  Future<ActionResult> escalate(int id, String note) async =>
      ActionResult.fromJson(await _api.post('/issues/$id/escalate', {'note': note}));

  @override
  Future<ActionResult> withdrawEscalation(int id) async => ActionResult.fromJson(await _api.delete('/issues/$id/escalate'));

  @override
  Future<ActionResult> netaResponse(int id, String note) async =>
      ActionResult.fromJson(await _api.post('/issues/$id/neta-response', {'note': note}));
}
