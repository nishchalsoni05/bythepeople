import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/app/di.dart';
import 'package:by_the_people/presentation/providers/data_providers.dart';
import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/domain/entities/portal.dart';
import 'package:by_the_people/domain/entities/query.dart';
import 'package:by_the_people/domain/repositories/repositories.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart';

/// User-initiated mutations. Each one refreshes the data providers when it succeeds.
class Actions {
  Actions(this.ref);

  final Ref ref;

  IssueRepository get _issues => ref.read(issueRepositoryProvider);

  /// The user's position, fetched on demand when it is not known yet.
  Future<GeoPoint> _here() async {
    var loc = ref.read(locationProvider);
    if (!loc.has) {
      await ref.read(locationProvider.notifier).refresh();
      loc = ref.read(locationProvider);
    }
    final point = loc.point;
    if (point == null) {
      throw const ApiException('We could not get your location. Enable location access to take part.', 'NO_LOCATION', 0);
    }
    return point;
  }

  ActionResult _done(ActionResult result) {
    ref.read(tickProvider.notifier).bump();
    unawaited(ref.read(authProvider.notifier).refreshMe().catchError((_) {}));
    return result;
  }

  Future<ActionResult> support(int id) async => _done(await _issues.support(id, await _here()));

  Future<ActionResult> withdraw(int id) async => _done(await _issues.withdraw(id));

  Future<ActionResult> join(int id) async => _done(await _issues.join(id, await _here()));

  Future<ActionResult> leave(int id) async => _done(await _issues.leave(id));

  Future<ActionResult> resolve(int id, String note) async => _done(await _issues.resolve(id, await _here(), note));

  Future<ActionResult> verify(int id, bool approve) async => _done(await _issues.verify(id, await _here(), approve));

  Future<ActionResult> schedule(int id, DateTime at) async => _done(await _issues.schedule(id, at));

  Future<ActionResult> report(ReportDraft draft) async => _done(await _issues.report(draft, await _here()));

  Future<List<Issue>> similar(GeoPoint at, String category) => _issues.similar(at, category);

  // ----- social -----
  /// Likes or unlikes (not location gated). Returns the updated issue.
  Future<Issue> toggleLike(int id, bool currentlyLiked) async {
    final i = currentlyLiked ? await _issues.unlike(id) : await _issues.like(id);
    ref.read(tickProvider.notifier).bump();
    return i;
  }

  Future<void> comment(int id, String body, {List<String> media = const []}) async {
    await _issues.addComment(id, body, media: media);
    ref.invalidate(commentsProvider(id));
    ref.read(tickProvider.notifier).bump();
    unawaited(ref.read(authProvider.notifier).refreshMe().catchError((_) {}));
  }

  Future<ShareInfo> recordShare(int id) async {
    final s = await _issues.share(id);
    ref.read(tickProvider.notifier).bump();
    return s;
  }

  /// Uploads a picked image or video and returns its server path.
  Future<String> uploadMedia(Uint8List bytes, String mime) => ref.read(mediaUploadRepositoryProvider).upload(bytes, mime);

  // ----- authority (admin) -----
  PortalRepository get _portal => ref.read(portalRepositoryProvider);

  Future<ActionResult> authorityUpdate(int id,
          {required String status, String? note, String? assignedTo, List<String> media = const []}) async =>
      _done(await _portal.authorityUpdate(id, status: status, note: note, assignedTo: assignedTo, media: media));

  Future<void> verifyFoundation(int id, bool approve, {String? note}) async {
    await _portal.verifyFoundation(id, approve, note: note);
    ref.read(tickProvider.notifier).bump();
  }

  // ----- neta -----
  Future<ActionResult> escalate(int id, String note) async => _done(await _portal.escalate(id, note));

  Future<ActionResult> withdrawEscalation(int id) async => _done(await _portal.withdrawEscalation(id));

  Future<ActionResult> netaResponse(int id, String note) async => _done(await _portal.netaResponse(id, note));
}

final actionsProvider = Provider<Actions>((ref) => Actions(ref));
