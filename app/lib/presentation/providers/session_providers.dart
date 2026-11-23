import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:by_the_people/app/di.dart';
import 'package:by_the_people/core/logging/app_logger.dart';
import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/domain/entities/query.dart';
import 'package:by_the_people/domain/repositories/repositories.dart';

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
    // Any 401 while signed in (expired or reset session) returns to the sign-in screen.
    ref.read(apiClientProvider).onUnauthorized = () {
      unawaited(ref.read(authRepositoryProvider).clearSession());
      state = const AuthState(ready: true);
    };
    return const AuthState();
  }

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  Future<void> init() async {
    final hasSession = await _auth.restoreSession();
    if (!hasSession) {
      state = const AuthState(ready: true);
      return;
    }
    try {
      await refreshMe();
    } on ApiException catch (e) {
      if (e.status == 401) await _auth.clearSession();
      state = const AuthState(ready: true);
    }
  }

  Future<void> refreshMe() async {
    final me = await _auth.currentUser();
    state = AuthState(ready: true, user: me.user, unread: me.unread);
  }

  void _enter(AuthSession session) {
    state = AuthState(ready: true, user: session.user);
    ref.read(tickProvider.notifier).bump();
    unawaited(refreshMe().catchError((Object e) => appLogger.w('Profile refresh failed after sign-in', error: e)));
  }

  Future<void> login(String email, String password, {String? role}) async =>
      _enter(await _auth.login(email, password, role: role));

  /// [body]: name, email, password, role ('citizen' | 'foundation'), and for foundations orgName, regNo, about, city.
  Future<void> register(Map<String, dynamic> body) async => _enter(await _auth.register(body));

  Future<void> logout() async {
    await _auth.logout();
    state = const AuthState(ready: true);
  }

  Future<void> patch(Map<String, dynamic> changes) async {
    final user = await _auth.updateProfile(changes);
    state = AuthState(ready: true, user: user, unread: state.unread);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// The signed-in account's role: 'citizen' | 'admin' | 'neta' | 'foundation' (citizen when signed out).
final roleProvider = Provider<String>((ref) => ref.watch(authProvider.select((s) => s.user?.role ?? 'citizen')));

/// True for a foundation an admin has verified (only these may claim donations).
final isVerifiedFoundationProvider =
    Provider<bool>((ref) => ref.watch(authProvider.select((s) => s.user?.isVerifiedFoundation ?? false)));

// ---------- connection ----------
/// null = checking, true = backend reachable, false = offline.
class ConnectionNotifier extends Notifier<bool?> {
  @override
  bool? build() => null;

  Future<void> check() async {
    final wasOffline = state == false;
    try {
      await ref.read(systemRepositoryProvider).ping();
      state = true;
      if (wasOffline) ref.read(tickProvider.notifier).bump(); // recovered: refetch everything
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
  GeoPoint? get point => has ? GeoPoint(lat!, lng!) : null;
}

/// Demo area centre, used ONLY in debug builds if the device gives no location.
const _debugFallback = GeoPoint(21.2514, 81.6296);

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
      final moved = !state.has || (state.lat! - p.latitude).abs() > 0.0003 || (state.lng! - p.longitude).abs() > 0.0003;
      state = LocState(lat: p.latitude, lng: p.longitude);
      if (moved) ref.read(tickProvider.notifier).bump();
    } catch (e) {
      if (kDebugMode && !state.has) {
        state = LocState(lat: _debugFallback.lat, lng: _debugFallback.lng, fallback: true, error: '$e');
        ref.read(tickProvider.notifier).bump();
      } else if (!state.has) {
        appLogger.w('Location unavailable: $e');
        state = LocState(error: '$e');
      }
    }
  }
}

final locationProvider = NotifierProvider<LocationNotifier, LocState>(LocationNotifier.new);

// ---------- geography scope ----------
class ScopeNotifier extends Notifier<ScopeFilter> {
  @override
  ScopeFilter build() => const ScopeFilter('city');
  void setKind(String kind) => state = ScopeFilter(kind);
  void pick(String kind, int? id) => state = ScopeFilter(kind, id);
}

final scopeProvider = NotifierProvider<ScopeNotifier, ScopeFilter>(ScopeNotifier.new);

// ---------- shell navigation ----------
/// Selected tab of the role shell. Screens call [go] to jump to another tab (e.g. dashboard -> issue queue).
class ShellTab extends Notifier<int> {
  @override
  int build() => 0;
  void go(int i) => state = i;
}

final shellTabProvider = NotifierProvider<ShellTab, int>(ShellTab.new);

/// Admin queue filter that the dashboard can preset: (status, escalatedOnly).
class QueueFilter extends Notifier<(String? status, bool escalated)> {
  @override
  (String?, bool) build() => (null, false);
  void set(String? status, {bool escalated = false}) => state = (status, escalated);
}

final queueFilterProvider = NotifierProvider<QueueFilter, (String?, bool)>(QueueFilter.new);
