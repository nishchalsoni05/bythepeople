import 'dart:typed_data';

import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/domain/entities/portal.dart';
import 'package:by_the_people/domain/entities/query.dart';

/// Abstract data access. The UI depends only on these; `data/` provides the implementations.

class AuthSession {
  final String token;
  final UserProfile user;
  const AuthSession(this.token, this.user);
}

class CurrentUser {
  final UserProfile user;
  final int unread;
  const CurrentUser(this.user, this.unread);
}

abstract interface class AuthRepository {
  /// Activates a stored session. Returns false when there is none.
  Future<bool> restoreSession();
  Future<AuthSession> login(String email, String password, {String? role});
  Future<AuthSession> register(Map<String, dynamic> body);
  Future<CurrentUser> currentUser();
  Future<UserProfile> updateProfile(Map<String, dynamic> changes);
  /// Tells the server, then always clears the local session.
  Future<void> logout();
  /// Clears the local session only (used when the server says the session is gone).
  Future<void> clearSession();
}

abstract interface class GeoRepository {
  Future<List<Area>> areas();
  Future<Map<String, dynamic>?> resolve(GeoPoint at);
  Future<ScopeSummary> summary(ScopeFilter scope, {GeoPoint? at});
}

abstract interface class CatalogRepository {
  Future<List<CategoryInfo>> categories();
}

abstract interface class IssueRepository {
  Future<List<Issue>> feed({
    required ScopeFilter scope,
    required String phase,
    required String sort,
    String? category,
    String query = '',
    GeoPoint? at,
  });
  Future<Issue> detail(int id, {GeoPoint? at});
  Future<List<Issue>> activity(String type, {GeoPoint? at});
  Future<List<Issue>> similar(GeoPoint at, String category);
  Future<ActionResult> support(int id, GeoPoint at);
  Future<ActionResult> withdraw(int id);
  Future<ActionResult> join(int id, GeoPoint at);
  Future<ActionResult> leave(int id);
  Future<ActionResult> resolve(int id, GeoPoint at, String note);
  Future<ActionResult> verify(int id, GeoPoint at, bool approve);
  Future<ActionResult> schedule(int id, DateTime at);
  Future<ActionResult> report(ReportDraft draft, GeoPoint userAt);
  Future<Issue> like(int id);
  Future<Issue> unlike(int id);
  Future<List<IssueComment>> comments(int id);
  Future<void> addComment(int id, String body, {List<String> media = const []});
  Future<ShareInfo> share(int id);
}

abstract interface class MediaUploadRepository {
  /// Uploads an image or video (POST /media, base64) and returns its URL path, e.g. `/uploads/ab12.jpg`.
  Future<String> upload(Uint8List bytes, String mime);
}

/// Admin (authority) and Neta portals.
abstract interface class PortalRepository {
  Future<AdminDashboard> adminDashboard();
  Future<List<Issue>> adminIssues({String? status, String? q, bool? escalated, String? category, String sort = 'default'});
  Future<ActionResult> authorityUpdate(int id, {required String status, String? note, String? assignedTo, List<String> media = const []});
  Future<List<FoundationRow>> foundations(String status);
  Future<void> verifyFoundation(int id, bool approve, {String? note});
  Future<NetaDashboard> netaDashboard();
  Future<List<Issue>> netaFeed({String? status, String sort = 'top'});
  Future<ActionResult> escalate(int id, String note);
  Future<ActionResult> withdrawEscalation(int id);
  Future<ActionResult> netaResponse(int id, String note);
}

abstract interface class NetaRepository {
  Future<NetaList> list(ScopeFilter scope);
  Future<List<Neta>> tree(ScopeFilter scope);
  Future<NetaDetail> detail(int id);
}

abstract interface class NotificationRepository {
  Future<List<AppNotification>> list();
  /// Marks every alert as read on the server.
  Future<void> markAllRead();
}

abstract interface class SystemRepository {
  /// Throws when the backend cannot be reached.
  Future<void> ping();
}
