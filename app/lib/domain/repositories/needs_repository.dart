import 'package:by_the_people/domain/entities/need.dart';

/// Needs posted by verified foundations, and pledges toward them.
abstract class NeedsRepository {
  /// `status`: open | closed | all.
  Future<List<Need>> list({String status = 'open'});
  /// Verified foundations only.
  Future<Need> create(NeedDraft draft);
  Future<Need> pledge(int id, {String? note});
  Future<Need> unpledge(int id);
  /// Owner only.
  Future<Need> close(int id);
}
