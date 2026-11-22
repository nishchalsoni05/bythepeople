import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'api.dart';
import 'models.dart';

final apiProvider = Provider<ApiClient>((ref) => ApiClient());

/// Bump to refetch every data provider after a mutation.
class Tick extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final tickProvider = NotifierProvider<Tick, int>(Tick.new);

// ---------- auth ----------
class AuthState {
  final bool ready;
  final UserProfile? user;
  final int unread;
  const AuthState({this.ready = false, this.user, this.unread = 0});
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Any 401 while signed in (expired/reset session) returns to the sign-in screen.
    ref.read(apiProvider).onUnauthorized = () {
      ref.read(apiProvider).saveToken(null);
      state = const AuthState(ready: true);
    };
    return const AuthState();
  }

  ApiClient get _api => ref.read(apiProvider);

  Future<void> init() async {
    await _api.loadToken();
    if (_api.token == null) {
      state = const AuthState(ready: true);
      return;
    }
    try {
      await refreshMe();
      state = AuthState(ready: true, user: state.user, unread: state.unread);
    } on ApiException catch (e) {
      if (e.status == 401) await _api.saveToken(null);
      state = const AuthState(ready: true);
    }
  }

  Future<void> refreshMe() async {
    final j = await _api.get('/me');
    state = AuthState(ready: true, user: UserProfile.fromJson(j['user']), unread: j['unread'] ?? 0);
  }

  Future<void> _enter(Map<String, dynamic> j) async {
    await _api.saveToken(j['token']);
    state = AuthState(ready: true, user: UserProfile.fromJson(j['user']));
    ref.read(tickProvider.notifier).bump();
    unawaited(refreshMe());
  }

  Future<void> login(String email, String password) async =>
      _enter(await _api.post('/auth/login', {'email': email, 'password': password}));

  Future<void> register(String name, String email, String password) async =>
      _enter(await _api.post('/auth/register', {'name': name, 'email': email, 'password': password}));

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {}
    await _api.saveToken(null);
    state = const AuthState(ready: true);
  }

  Future<void> patch(Map<String, dynamic> body) async {
    final j = await _api.patch('/me', body);
    state = AuthState(ready: true, user: UserProfile.fromJson(j['user']), unread: state.unread);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

// ---------- connection ----------
/// null = checking, true = backend reachable, false = offline.
class ConnectionNotifier extends Notifier<bool?> {
  @override
  bool? build() => null;

  Future<void> check() async {
    final was = state;
    try {
      await ref.read(apiProvider).get('/health');
      state = true;
      if (was == false) ref.read(tickProvider.notifier).bump(); // recovered: refetch everything
    } catch (_) {
      state = false;
    }
  }
}

final connectionProvider = NotifierProvider<ConnectionNotifier, bool?>(ConnectionNotifier.new);

// ---------- location ----------
class LocState {
  final double? lat, lng;
  final bool fallback; // true when using the debug fallback position
  final String? error;
  const LocState({this.lat, this.lng, this.fallback = false, this.error});
  bool get has => lat != null && lng != null;
}

// Demo area centre, used ONLY in debug builds if the device gives no location.
const _debugFallback = (21.2514, 81.6296);

class LocationNotifier extends Notifier<LocState> {
  @override
  LocState build() => const LocState();

  Future<void> refresh() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'Location services are turned off';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw 'Location permission denied';
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
      );
      final changed = !state.has || (state.lat! - p.latitude).abs() > 0.0003 || (state.lng! - p.longitude).abs() > 0.0003;
      state = LocState(lat: p.latitude, lng: p.longitude);
      if (changed) ref.read(tickProvider.notifier).bump();
    } catch (e) {
      if (kDebugMode && !state.has) {
        state = LocState(lat: _debugFallback.$1, lng: _debugFallback.$2, fallback: true, error: '$e');
        ref.read(tickProvider.notifier).bump();
      } else if (!state.has) {
        state = LocState(error: '$e');
      }
    }
  }
}

final locationProvider = NotifierProvider<LocationNotifier, LocState>(LocationNotifier.new);

// ---------- geography scope ----------
/// kind: city | state | region. areaId null means "the one I am in".
class ScopeState {
  final String kind;
  final int? areaId;
  const ScopeState(this.kind, [this.areaId]);
}

class ScopeNotifier extends Notifier<ScopeState> {
  @override
  ScopeState build() => const ScopeState('city');
  void setKind(String kind) => state = ScopeState(kind);
  void pick(String kind, int? id) => state = ScopeState(kind, id);
}

final scopeProvider = NotifierProvider<ScopeNotifier, ScopeState>(ScopeNotifier.new);

/// Flat list of regions, states and cities.
final areasProvider = FutureProvider<List<Area>>((ref) async {
  final j = await ref.read(apiProvider).get('/geo/areas');
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
});

/// Where I am right now: city / state / region names resolved on the server.
final hereProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final l = ref.watch(locationProvider.select((s) => s.has ? '${s.lat!.toStringAsFixed(3)},${s.lng!.toStringAsFixed(3)}' : ''));
  if (l.isEmpty) return null;
  final parts = l.split(',');
  return ref.read(apiProvider).get('/geo/resolve', query: {'lat': parts[0], 'lng': parts[1]});
});

/// Name shown for the active scope, e.g. "Bengaluru".
final scopeLabelProvider = Provider<String>((ref) {
  final sc = ref.watch(scopeProvider);
  final areas = ref.watch(areasProvider).asData?.value ?? const <Area>[];
  if (sc.areaId != null) {
    final a = areas.where((a) => a.id == sc.areaId);
    if (a.isNotEmpty) return a.first.name;
  }
  final here = ref.watch(hereProvider).asData?.value;
  final mine = here?[sc.kind]?['name'];
  return mine ?? (ref.watch(locationProvider).has ? 'Outside coverage' : 'Locating…');
});

Map<String, dynamic> scopeQuery(Ref ref) {
  final sc = ref.read(scopeProvider);
  return {'scope': sc.kind, if (sc.areaId != null) 'areaId': sc.areaId};
}

final scopeSummaryProvider = FutureProvider<ScopeSummary>((ref) async {
  ref.watch(tickProvider);
  ref.watch(scopeProvider);
  final j = await ref.read(apiProvider).get('/geo/summary', query: {...scopeQuery(ref), ...?_locQuery(ref)});
  return ScopeSummary.fromJson(j);
});

// ---------- data ----------
typedef FeedQ = (String phase, String sort, String? category, String query);

Map<String, dynamic>? _locQuery(Ref ref) {
  final l = ref.read(locationProvider);
  return l.has ? {'lat': l.lat, 'lng': l.lng} : null;
}

final metaProvider = FutureProvider<List<CategoryInfo>>((ref) async {
  final j = await ref.read(apiProvider).get('/meta');
  return (j['categories'] as List).map((e) => CategoryInfo.fromJson(e)).toList();
});

final feedProvider = FutureProvider.family<List<Issue>, FeedQ>((ref, q) async {
  ref.watch(tickProvider);
  ref.watch(scopeProvider);
  final j = await ref.read(apiProvider).get('/issues', query: {
    ...scopeQuery(ref),
    'phase': q.$1,
    'sort': q.$2,
    if (q.$3 != null) 'category': q.$3,
    if (q.$4.isNotEmpty) 'q': q.$4,
    ...?_locQuery(ref),
  });
  return (j['items'] as List).map((e) => Issue.fromJson(e)).toList();
});

final issueProvider = FutureProvider.family<Issue, int>((ref, id) async {
  ref.watch(tickProvider);
  final j = await ref.read(apiProvider).get('/issues/$id', query: _locQuery(ref));
  return Issue.fromJson(j['issue']);
});

final activityProvider = FutureProvider.family<List<Issue>, String>((ref, type) async {
  ref.watch(tickProvider);
  final j = await ref.read(apiProvider).get('/me/activity', query: {'type': type, ...?_locQuery(ref)});
  return (j['items'] as List).map((e) => Issue.fromJson(e)).toList();
});

class NetaList {
  final List<Neta> items;
  final List<String> parties;
  NetaList(this.items, this.parties);
}

final netasProvider = FutureProvider<NetaList>((ref) async {
  ref.watch(tickProvider);
  ref.watch(scopeProvider);
  final j = await ref.read(apiProvider).get('/netas', query: scopeQuery(ref));
  return NetaList((j['items'] as List).map((e) => Neta.fromJson(e)).toList(), (j['parties'] as List).cast<String>());
});

final netaTreeProvider = FutureProvider<List<Neta>>((ref) async {
  ref.watch(tickProvider);
  ref.watch(scopeProvider);
  final j = await ref.read(apiProvider).get('/netas/tree', query: scopeQuery(ref));
  return (j['roots'] as List).map((e) => Neta.fromJson(e)).toList();
});

class NetaDetail {
  final Neta neta;
  final List<Neta> children;
  final List<Issue> open, resolved;
  NetaDetail(this.neta, this.children, this.open, this.resolved);
}

final netaDetailProvider = FutureProvider.family<NetaDetail, int>((ref, id) async {
  ref.watch(tickProvider);
  final j = await ref.read(apiProvider).get('/netas/$id');
  List<Issue> iss(String k) => (j[k] as List).map((e) => Issue.fromJson(e)).toList();
  return NetaDetail(Neta.fromJson(j['neta']), (j['children'] as List).map((e) => Neta.fromJson(e)).toList(),
      iss('openIssues'), iss('resolvedIssues'));
});

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) async {
  ref.watch(tickProvider);
  final j = await ref.read(apiProvider).get('/notifications');
  return (j['items'] as List).map((e) => AppNotification.fromJson(e)).toList();
});

// ---------- actions ----------
class Actions {
  final Ref ref;
  Actions(this.ref);
  ApiClient get _api => ref.read(apiProvider);

  Future<({double lat, double lng})> _here() async {
    var l = ref.read(locationProvider);
    if (!l.has) {
      await ref.read(locationProvider.notifier).refresh();
      l = ref.read(locationProvider);
    }
    if (!l.has) throw ApiException('We could not get your location. Enable location access to take part.', 'NO_LOCATION', 0);
    return (lat: l.lat!, lng: l.lng!);
  }

  Future<ActionResult> _done(Map<String, dynamic> j) async {
    ref.read(tickProvider.notifier).bump();
    unawaited(ref.read(authProvider.notifier).refreshMe().catchError((_) {}));
    return ActionResult.fromJson(j);
  }

  Future<ActionResult> support(int id) async {
    final h = await _here();
    return _done(await _api.post('/issues/$id/support', {'lat': h.lat, 'lng': h.lng}));
  }

  Future<ActionResult> withdraw(int id) async => _done(await _api.delete('/issues/$id/support'));

  Future<ActionResult> join(int id) async {
    final h = await _here();
    return _done(await _api.post('/events/$id/join', {'lat': h.lat, 'lng': h.lng}));
  }

  Future<ActionResult> leave(int id) async => _done(await _api.delete('/events/$id/join'));

  Future<ActionResult> resolve(int id, String note) async {
    final h = await _here();
    return _done(await _api.post('/events/$id/resolve', {'lat': h.lat, 'lng': h.lng, 'note': note}));
  }

  Future<ActionResult> verify(int id, bool approve) async {
    final h = await _here();
    return _done(await _api.post('/events/$id/verify', {'lat': h.lat, 'lng': h.lng, 'approve': approve}));
  }

  Future<ActionResult> schedule(int id, DateTime at) async =>
      _done(await _api.post('/events/$id/schedule', {'scheduledAt': at.millisecondsSinceEpoch}));

  Future<ActionResult> report({
    required String title, required String category, required String description,
    required double lat, required double lng, int? linkTo, String? address,
  }) async {
    final h = await _here();
    return _done(await _api.post('/issues', {
      'title': title, 'category': category, 'description': description, 'lat': lat, 'lng': lng,
      'userLat': h.lat, 'userLng': h.lng, if (linkTo != null) 'linkTo': linkTo, if (address != null) 'address': address,
    }));
  }

  Future<List<Issue>> similar(double lat, double lng, String category) async {
    final j = await _api.get('/issues/similar', query: {'lat': lat, 'lng': lng, 'category': category});
    return (j['items'] as List).map((e) => Issue.fromJson(e)).toList();
  }
}

final actionsProvider = Provider<Actions>((ref) => Actions(ref));
