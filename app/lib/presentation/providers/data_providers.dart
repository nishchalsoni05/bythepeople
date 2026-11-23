import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/app/di.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/domain/entities/portal.dart';
import 'package:by_the_people/domain/entities/query.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart';

/// Feed query: (phase, sort, category, search text).
typedef FeedQ = (String phase, String sort, String? category, String query);

/// The user's position, only when we have one.
GeoPoint? _position(Ref ref) => ref.read(locationProvider).point;

final areasProvider = FutureProvider<List<Area>>((ref) => ref.read(geoRepositoryProvider).areas());

/// Where I am right now: city / state / region names resolved on the server.
/// Keyed on a coarse position so GPS jitter does not refetch.
final hereProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final key = ref.watch(locationProvider.select((s) => s.point?.coarseKey));
  if (key == null) return null;
  final at = _position(ref);
  if (at == null) return null;
  return ref.read(geoRepositoryProvider).resolve(at);
});

/// Name shown for the active scope, e.g. "Bengaluru".
final scopeLabelProvider = Provider<String>((ref) {
  final scope = ref.watch(scopeProvider);
  final areas = ref.watch(areasProvider).asData?.value ?? const <Area>[];
  if (scope.areaId != null) {
    final match = areas.where((a) => a.id == scope.areaId);
    if (match.isNotEmpty) return match.first.name;
  }
  final here = ref.watch(hereProvider).asData?.value;
  final mine = here?[scope.kind]?['name'];
  if (mine != null) return mine as String;
  if (!ref.watch(locationProvider).has) return 'Locating…';
  // Outside city coverage the backend falls back to the whole state.
  final state = here?['state']?['name'];
  if (state != null) return state as String;
  return 'Chhattisgarh';
});

final metaProvider = FutureProvider<List<CategoryInfo>>((ref) => ref.read(catalogRepositoryProvider).categories());

final scopeSummaryProvider = FutureProvider<ScopeSummary>((ref) {
  ref.watch(tickProvider);
  final scope = ref.watch(scopeProvider);
  return ref.read(geoRepositoryProvider).summary(scope, at: _position(ref));
});

final feedProvider = FutureProvider.family<List<Issue>, FeedQ>((ref, q) {
  ref.watch(tickProvider);
  final scope = ref.watch(scopeProvider);
  return ref.read(issueRepositoryProvider).feed(
        scope: scope,
        phase: q.$1,
        sort: q.$2,
        category: q.$3,
        query: q.$4,
        at: _position(ref),
      );
});

final issueProvider = FutureProvider.family<Issue, int>((ref, id) {
  ref.watch(tickProvider);
  return ref.read(issueRepositoryProvider).detail(id, at: _position(ref));
});

final activityProvider = FutureProvider.family<List<Issue>, String>((ref, type) {
  ref.watch(tickProvider);
  return ref.read(issueRepositoryProvider).activity(type, at: _position(ref));
});

final netasProvider = FutureProvider<NetaList>((ref) {
  ref.watch(tickProvider);
  final scope = ref.watch(scopeProvider);
  return ref.read(netaRepositoryProvider).list(scope);
});

final netaTreeProvider = FutureProvider<List<Neta>>((ref) {
  ref.watch(tickProvider);
  final scope = ref.watch(scopeProvider);
  return ref.read(netaRepositoryProvider).tree(scope);
});

final netaDetailProvider = FutureProvider.family<NetaDetail, int>((ref, id) {
  ref.watch(tickProvider);
  return ref.read(netaRepositoryProvider).detail(id);
});

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) {
  ref.watch(tickProvider);
  return ref.read(notificationRepositoryProvider).list();
});

final commentsProvider = FutureProvider.family<List<IssueComment>, int>((ref, id) {
  ref.watch(tickProvider);
  return ref.read(issueRepositoryProvider).comments(id);
});

// ---------- admin portal ----------
/// Admin queue query: (status, search, escalatedOnly, category, sort).
typedef AdminQ = (String? status, String q, bool escalated, String? category, String sort);

final adminDashboardProvider = FutureProvider<AdminDashboard>((ref) {
  ref.watch(tickProvider);
  return ref.read(portalRepositoryProvider).adminDashboard();
});

final adminIssuesProvider = FutureProvider.family<List<Issue>, AdminQ>((ref, q) {
  ref.watch(tickProvider);
  return ref.read(portalRepositoryProvider).adminIssues(status: q.$1, q: q.$2, escalated: q.$3, category: q.$4, sort: q.$5);
});

final adminFoundationsProvider = FutureProvider.family<List<FoundationRow>, String>((ref, status) {
  ref.watch(tickProvider);
  return ref.read(portalRepositoryProvider).foundations(status);
});

// ---------- neta portal ----------
final netaDashboardProvider = FutureProvider<NetaDashboard>((ref) {
  ref.watch(tickProvider);
  return ref.read(portalRepositoryProvider).netaDashboard();
});

/// Neta locality feed: (status, sort).
final netaFeedProvider = FutureProvider.family<List<Issue>, (String? status, String sort)>((ref, q) {
  ref.watch(tickProvider);
  return ref.read(portalRepositoryProvider).netaFeed(status: q.$1, sort: q.$2);
});
