import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/app/welfare_di.dart';
import 'package:by_the_people/domain/entities/comment.dart';
import 'package:by_the_people/domain/entities/donation.dart';
import 'package:by_the_people/domain/entities/foundation.dart';
import 'package:by_the_people/domain/entities/query.dart';
import 'package:by_the_people/domain/repositories/welfare_repositories.dart';
import 'package:by_the_people/presentation/providers/gathering_providers.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart';

/// Donation list query: (kind, status, sort).
typedef DonationQ = (String? kind, String status, String sort);

GeoPoint? _at(Ref ref) => ref.read(locationProvider).point;

final donationsProvider = FutureProvider.family<List<Donation>, DonationQ>((ref, q) {
  ref.watch(welfareTickProvider);
  ref.watch(locationProvider.select((s) => s.point?.coarseKey));
  return ref.read(donationRepositoryProvider).list(kind: q.$1, status: q.$2, sort: q.$3, at: _at(ref));
});

final donationProvider = FutureProvider.family<Donation, int>((ref, id) {
  ref.watch(welfareTickProvider);
  return ref.read(donationRepositoryProvider).detail(id, at: _at(ref));
});

final donationCommentsProvider = FutureProvider.family<List<Comment>, int>((ref, id) {
  ref.watch(welfareTickProvider);
  return ref.read(donationRepositoryProvider).comments(id);
});

final myDonationsProvider = FutureProvider<List<Donation>>((ref) {
  ref.watch(welfareTickProvider);
  return ref.read(donationRepositoryProvider).mine();
});

final foundationsProvider = FutureProvider.family<List<Foundation>, (String, String?)>((ref, q) {
  ref.watch(welfareTickProvider);
  return ref.read(foundationRepositoryProvider).list(query: q.$1, need: q.$2);
});

final foundationProvider = FutureProvider.family<Foundation, int>((ref, id) {
  ref.watch(welfareTickProvider);
  return ref.read(foundationRepositoryProvider).detail(id);
});

final foundationDashboardProvider = FutureProvider<FoundationDashboard>((ref) {
  ref.watch(welfareTickProvider);
  return ref.read(foundationRepositoryProvider).dashboard();
});

/// User-initiated donation mutations. Each refreshes the data providers on success.
class DonationActions {
  DonationActions(this.ref);
  final Ref ref;

  DonationRepository get _repo => ref.read(donationRepositoryProvider);

  Done<Donation> _done(Outcome<Donation> o) {
    ref.read(welfareTickProvider.notifier).bump();
    unawaited(ref.read(authProvider.notifier).refreshMe().catchError((_) {}));
    return Done(o.value, parseRewards(o.rewards));
  }

  Future<Done<Donation>> create(DonationDraft d) async => _done(await _repo.create(d));
  Future<Done<Donation>> claim(int id, int etaMinutes) async => _done(await _repo.claim(id, etaMinutes));
  Future<Done<Donation>> release(int id) async => _done(await _repo.release(id));
  Future<Done<Donation>> pickup(int id) async => _done(await _repo.pickup(id));
  Future<Done<Donation>> cancel(int id) async => _done(await _repo.cancel(id));
  Future<Done<Donation>> like(int id, {required bool on}) async => _done(on ? await _repo.like(id) : await _repo.unlike(id));

  Future<Done<Donation>> distribute(int id, {required String note, required int beneficiaries, List<String> media = const []}) async =>
      _done(await _repo.distribute(id, note: note, beneficiaries: beneficiaries, media: media));

  Future<void> addComment(int id, String body) async {
    await _repo.addComment(id, body);
    ref.read(welfareTickProvider.notifier).bump();
  }

  Future<void> share(int id) async {
    final info = await _repo.share(id);
    await ref.read(welfarePlatformProvider).share(info.shareText.isEmpty ? (info.publicUrl ?? '') : info.shareText);
    ref.read(welfareTickProvider.notifier).bump();
  }
}

final donationActionsProvider = Provider<DonationActions>((ref) => DonationActions(ref));
