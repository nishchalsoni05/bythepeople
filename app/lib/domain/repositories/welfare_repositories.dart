import 'package:by_the_people/domain/entities/club.dart';
import 'package:by_the_people/domain/entities/comment.dart';
import 'package:by_the_people/domain/entities/donation.dart';
import 'package:by_the_people/domain/entities/foundation.dart';
import 'package:by_the_people/domain/entities/gathering.dart';
import 'package:by_the_people/domain/entities/query.dart';

/// Gatherings, clubs and the calendar.
abstract class GatheringRepository {
  /// `when`: upcoming | past | mine | proposed. `sort`: soon | near | popular.
  Future<List<Gathering>> list({String when = 'upcoming', String? type, int? clubId, String sort = 'soon', String? query, GeoPoint? at});
  Future<Gathering> detail(int id, {GeoPoint? at});
  Future<Outcome<Gathering>> create(GatheringDraft draft);
  Future<Outcome<Gathering>> rsvp(int id);
  Future<Outcome<Gathering>> unrsvp(int id);
  Future<Outcome<Gathering>> vote(int id);
  Future<Outcome<Gathering>> unvote(int id);
  Future<Outcome<Gathering>> checkIn(int id, GeoPoint at);
  Future<Outcome<Gathering>> complete(int id, String note);
  Future<Outcome<Gathering>> cancel(int id);
  Future<Outcome<Gathering>> like(int id);
  Future<Outcome<Gathering>> unlike(int id);
  Future<List<Comment>> comments(int id);
  Future<void> addComment(int id, String body);
  Future<ShareInfo> share(int id);

  /// `month` as `2026-11`. Keys of the result are `2026-11-24`.
  Future<Map<String, List<GatheringLite>>> calendar(String month);

  Future<List<Club>> clubs();
  Future<ClubDetail> club(int id);
  Future<Club> createClub(String name, String description, String category);
  Future<void> joinClub(int id);
  Future<void> leaveClub(int id);
}

abstract class DonationRepository {
  /// `status`: available | claimed | history | mine. `sort`: expiring | new | near.
  Future<List<Donation>> list({String? kind, String status = 'available', String sort = 'expiring', GeoPoint? at});
  Future<Donation> detail(int id, {GeoPoint? at});
  Future<Outcome<Donation>> create(DonationDraft draft);
  Future<Outcome<Donation>> claim(int id, int etaMinutes);
  Future<Outcome<Donation>> release(int id);
  Future<Outcome<Donation>> pickup(int id);
  Future<Outcome<Donation>> distribute(int id, {required String note, required int beneficiaries, List<String> media = const []});
  Future<Outcome<Donation>> cancel(int id);
  Future<Outcome<Donation>> like(int id);
  Future<Outcome<Donation>> unlike(int id);
  Future<List<Comment>> comments(int id);
  Future<void> addComment(int id, String body);
  Future<ShareInfo> share(int id);
  Future<List<Donation>> mine();
}

abstract class FoundationRepository {
  Future<List<Foundation>> list({String? query, String? need});
  Future<Foundation> detail(int id);
  Future<FoundationDashboard> dashboard();
}

abstract class MediaRepository {
  /// Uploads a photo and returns its URL path (e.g. `/uploads/ab12.jpg`).
  Future<String> upload(List<int> bytes, String mime);
}
