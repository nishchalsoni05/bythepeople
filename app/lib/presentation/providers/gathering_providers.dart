import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/app/welfare_di.dart';
import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/domain/entities/club.dart';
import 'package:by_the_people/domain/entities/comment.dart';
import 'package:by_the_people/domain/entities/gathering.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/domain/entities/query.dart';
import 'package:by_the_people/domain/repositories/welfare_repositories.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart';

/// Bump to refetch every gathering, club and calendar provider after a mutation.
class WelfareTick extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final welfareTickProvider = NotifierProvider<WelfareTick, int>(WelfareTick.new);

/// Gathering list query: (when, type, sort, clubId).
typedef GatheringQ = (String when, String? type, String sort, int? clubId);

GeoPoint? _at(Ref ref) => ref.read(locationProvider).point;

final gatheringsProvider = FutureProvider.family<List<Gathering>, GatheringQ>((ref, q) {
  ref.watch(welfareTickProvider);
  ref.watch(locationProvider.select((s) => s.point?.coarseKey));
  return ref.read(gatheringRepositoryProvider).list(when: q.$1, type: q.$2, sort: q.$3, clubId: q.$4, at: _at(ref));
});

final gatheringProvider = FutureProvider.family<Gathering, int>((ref, id) {
  ref.watch(welfareTickProvider);
  return ref.read(gatheringRepositoryProvider).detail(id, at: _at(ref));
});

final gatheringCommentsProvider = FutureProvider.family<List<Comment>, int>((ref, id) {
  ref.watch(welfareTickProvider);
  return ref.read(gatheringRepositoryProvider).comments(id);
});

/// Month key like `2026-11`.
final calendarProvider = FutureProvider.family<Map<String, List<GatheringLite>>, String>((ref, month) {
  ref.watch(welfareTickProvider);
  return ref.read(gatheringRepositoryProvider).calendar(month);
});

final clubsProvider = FutureProvider<List<Club>>((ref) {
  ref.watch(welfareTickProvider);
  return ref.read(gatheringRepositoryProvider).clubs();
});

final clubDetailProvider = FutureProvider.family<ClubDetail, int>((ref, id) {
  ref.watch(welfareTickProvider);
  return ref.read(gatheringRepositoryProvider).club(id);
});

/// What a mutation returned: the fresh object and any rewards for the UI to celebrate.
class Done<T> {
  final T value;
  final Rewards? rewards;
  const Done(this.value, this.rewards);
}

Rewards? parseRewards(Map<String, dynamic>? j) {
  if (j == null) return null;
  try {
    return Rewards.fromJson(j);
  } catch (_) {
    return null;
  }
}

/// User-initiated gathering mutations. Each refreshes the data providers on success.
class GatheringActions {
  GatheringActions(this.ref);
  final Ref ref;

  GatheringRepository get _repo => ref.read(gatheringRepositoryProvider);

  Done<Gathering> _done(Outcome<Gathering> o) {
    ref.read(welfareTickProvider.notifier).bump();
    unawaited(ref.read(authProvider.notifier).refreshMe().catchError((_) {}));
    return Done(o.value, parseRewards(o.rewards));
  }

  Future<GeoPoint> here() async {
    var loc = ref.read(locationProvider);
    if (!loc.has) {
      await ref.read(locationProvider.notifier).refresh();
      loc = ref.read(locationProvider);
    }
    final p = loc.point;
    if (p == null) throw const ApiException('We could not get your location. Enable location access to take part.', 'NO_LOCATION', 0);
    return p;
  }

  Future<Done<Gathering>> create(GatheringDraft d) async => _done(await _repo.create(d));
  Future<Done<Gathering>> rsvp(int id, {required bool on}) async => _done(on ? await _repo.rsvp(id) : await _repo.unrsvp(id));
  Future<Done<Gathering>> vote(int id, {required bool on}) async => _done(on ? await _repo.vote(id) : await _repo.unvote(id));
  Future<Done<Gathering>> like(int id, {required bool on}) async => _done(on ? await _repo.like(id) : await _repo.unlike(id));
  Future<Done<Gathering>> checkIn(int id) async => _done(await _repo.checkIn(id, await here()));
  Future<Done<Gathering>> complete(int id, String note) async => _done(await _repo.complete(id, note));
  Future<Done<Gathering>> cancel(int id) async => _done(await _repo.cancel(id));

  Future<void> addComment(int id, String body) async {
    await _repo.addComment(id, body);
    ref.read(welfareTickProvider.notifier).bump();
  }

  Future<void> share(int id) async {
    final info = await _repo.share(id);
    await ref.read(welfarePlatformProvider).share(info.shareText.isEmpty ? (info.publicUrl ?? '') : info.shareText);
    ref.read(welfareTickProvider.notifier).bump();
  }

  Future<void> joinClub(int id, {required bool on}) async {
    on ? await _repo.joinClub(id) : await _repo.leaveClub(id);
    ref.read(welfareTickProvider.notifier).bump();
  }

  Future<Club> createClub(String name, String description, String category) async {
    final c = await _repo.createClub(name, description, category);
    ref.read(welfareTickProvider.notifier).bump();
    return c;
  }

  /// Uploads a photo and returns its URL path.
  Future<String> upload(PickedPhoto p) => ref.read(mediaRepositoryProvider).upload(p.bytes, p.mime);
}

final gatheringActionsProvider = Provider<GatheringActions>((ref) => GatheringActions(ref));
