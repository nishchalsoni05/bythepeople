import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/app/needs_di.dart';
import 'package:by_the_people/domain/entities/need.dart';
import 'package:by_the_people/domain/repositories/needs_repository.dart';
import 'package:by_the_people/presentation/providers/gathering_providers.dart';

/// The needs board for one status filter: open | closed | all.
final needsProvider = FutureProvider.family<List<Need>, String>((ref, status) {
  ref.watch(welfareTickProvider);
  return ref.read(needsRepositoryProvider).list(status: status);
});

/// User-initiated need mutations. Each bumps the welfare tick so every needs list refreshes.
class NeedActions {
  NeedActions(this.ref);
  final Ref ref;

  NeedsRepository get _repo => ref.read(needsRepositoryProvider);

  void _changed() => ref.read(welfareTickProvider.notifier).bump();

  Future<Need> create(NeedDraft draft) async {
    final need = await _repo.create(draft);
    _changed();
    return need;
  }

  Future<Need> pledge(int id, {String? note}) async {
    final need = await _repo.pledge(id, note: note);
    _changed();
    return need;
  }

  Future<Need> unpledge(int id) async {
    final need = await _repo.unpledge(id);
    _changed();
    return need;
  }

  Future<Need> close(int id) async {
    final need = await _repo.close(id);
    _changed();
    return need;
  }
}

final needActionsProvider = Provider<NeedActions>((ref) => NeedActions(ref));
