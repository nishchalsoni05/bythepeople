import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/domain/entities/gathering.dart';
import 'package:by_the_people/presentation/features/gatherings/gathering_widgets.dart';
import 'package:by_the_people/presentation/features/gatherings/welfare_common.dart';
import 'package:by_the_people/presentation/providers/gathering_providers.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart';
import 'package:by_the_people/presentation/widgets/map.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Opens the gathering detail screen.
Future<void> openGathering(BuildContext context, int id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GatheringDetailScreen(id: id)));

class GatheringDetailScreen extends ConsumerStatefulWidget {
  const GatheringDetailScreen({super.key, required this.id});
  final int id;
  @override
  ConsumerState<GatheringDetailScreen> createState() => _GatheringDetailScreenState();
}

class _GatheringDetailScreenState extends ConsumerState<GatheringDetailScreen> with PollingState {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    startPolling(const Duration(seconds: 30), () => ref.invalidate(gatheringProvider(widget.id)));
  }

  Future<void> _run(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    await fn();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _checkIn(Gathering g) => _run(() async {
    final r = await guarded(context, () => ref.read(gatheringActionsProvider).checkIn(g.id));
    // ignore: use_build_context_synchronously
    if (r != null) cheer(context, r.rewards, 'Checked in. Thank you for showing up!', confetti: true);
  });

  Future<void> _complete(Gathering g) async {
    final note = TextEditingController();
    final ok = await showWelfareSheet<bool>(
      context,
      builder: (ctx) => SheetBody(
        title: 'Wrap it up',
        subtitle: 'Share what the group achieved. Everyone who checked in gets a thank-you.',
        children: [
          WField(
            label: 'Impact note',
            controller: note,
            lines: 4,
            hint: 'e.g. 60 saplings planted along the canal',
            maxLength: 400,
            fieldKey: const Key('impact-note'),
          ),
          const SizedBox(height: 18),
          PillButton(label: 'Mark as completed', icon: Icons.flag_rounded, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (ok != true || !mounted) return;
    if (text.length < 3) return showToast(context, 'Add a short impact note.', error: true);
    await _run(() async {
      final r = await guarded(context, () => ref.read(gatheringActionsProvider).complete(g.id, text));
      // ignore: use_build_context_synchronously
      if (r != null) cheer(context, r.rewards, 'Marked as completed', confetti: true);
    });
  }

  Future<void> _cancel(Gathering g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.canvas,
        title: Text('Cancel this gathering?', style: ui(18, w: 600)),
        content: Text('Everyone who RSVP\'d will be notified.', style: ui(14, color: C.inkSoft)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep it', style: ui(14, w: 600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancel gathering', style: ui(14, color: C.ember, w: 600)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      final r = await guarded(context, () => ref.read(gatheringActionsProvider).cancel(g.id));
      if (r != null && mounted) showToast(context, 'Event cancelled', icon: Icons.event_busy_rounded);
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(gatheringProvider(widget.id));
    final me = ref.watch(authProvider).user;
    return Scaffold(
      body: PageBackdrop(
        child: async.when(
          skipLoadingOnReload: true,
          loading: () => const SafeArea(child: DetailSkeleton()),
          error: (e, _) => SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: WHeader(title: 'Event'),
                ),
                ErrorState(error: e, onRetry: () => ref.invalidate(gatheringProvider(widget.id))),
              ],
            ),
          ),
          data: (g) => _content(g, me?.id),
        ),
      ),
    );
  }

  Widget _content(Gathering fetched, int? meId) {
    final g = effective(ref, fetched);
    final s = styleOf(g.type);
    final pad = MediaQuery.paddingOf(context);
    final mine = g.organisedBy(meId);
    final started = DateTime.now().millisecondsSinceEpoch >= g.startAt;
    final canCheckIn = g.goingByMe && !g.checkedInByMe && g.checkInOpenNow;

    return RefreshIndicator(
      color: C.ember,
      onRefresh: () async {
        ref.invalidate(gatheringProvider(g.id));
        await ref.read(gatheringProvider(g.id).future);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, pad.top + 4, 16, pad.bottom + 110),
        children: [
          WHeader(
            title: 'Event',
            trailing: g.isProposed ? const Tag('Campaign proposal', icon: Icons.how_to_vote_rounded) : null,
          ),
          const SizedBox(height: 8),
          if (g.media.isNotEmpty)
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: g.media.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => NetPhoto(g.media[i], height: 200, width: g.media.length == 1 ? MediaQuery.sizeOf(context).width - 32 : 280, radius: 14, fallbackIcon: s.icon),
              ),
            ),
          if (g.media.isNotEmpty) const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Tag(g.typeLabel, icon: s.icon),
              if (g.isCancelled) const Tag('Cancelled', bg: C.ink, fg: Colors.white),
              if (g.isCompleted) const Tag('Completed', icon: Icons.check_circle_rounded),
              if (g.isOngoing) const Tag('Happening now', icon: Icons.circle, bg: C.ink, fg: C.lime),
            ],
          ),
          const SizedBox(height: 10),
          Text(g.title, style: ui(20, w: 600, h: 1.3)),
          if (g.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(g.description, style: ui(14, color: C.ink.withValues(alpha: 0.85), h: 1.5)),
          ],
          const SizedBox(height: 14),
          WCard(
            child: Column(
              children: [
                _InfoRow(Icons.event_rounded, gatheringWhen(g)),
                const SizedBox(height: 10),
                _InfoRow(
                  Icons.place_outlined,
                  [if (g.address.isNotEmpty) g.address, if (g.distanceKm != null) km(g.distanceKm)].join(' · '),
                ),
                if (g.club != null) ...[const SizedBox(height: 10), _InfoRow(Icons.groups_outlined, 'Hosted by ${g.club!.name}')],
                const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, color: C.line)),
                PersonLine(g.organizer, sub: 'Organiser'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          MapPreview(lat: g.lat, lng: g.lng, label: g.title, height: 150),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => openInMaps(g.lat, g.lng, label: g.title, directions: true),
              icon: const Icon(Icons.directions_rounded, size: 18),
              label: const Text('Directions'),
              style: OutlinedButton.styleFrom(foregroundColor: C.ink, side: const BorderSide(color: C.line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            ),
          ),
          const SizedBox(height: 12),
          WCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (g.isProposed) ...[
                  Text('Community vote', style: ui(14, w: 600)),
                  const SizedBox(height: 8),
                  VoteBar(g),
                ] else if (!g.isCancelled) ...[
                  Text(g.isCompleted ? 'Turnout' : 'Who is coming', style: ui(14, w: 600)),
                  const SizedBox(height: 8),
                  CapacityBar(g),
                ],
                if (!g.isCancelled && !g.isCompleted) ...[const SizedBox(height: 12), GatheringPrimaryButton(g)],
                if (canCheckIn) ...[
                  const SizedBox(height: 8),
                  PillButton(
                    label: 'I am here, check in',
                    icon: Icons.location_on_rounded,
                    color: C.lime,
                    fg: C.ink,
                    loading: _busy,
                    onPressed: () => _checkIn(g),
                  ),
                  const SizedBox(height: 6),
                  Text('You must be within 500 m of the venue.', textAlign: TextAlign.center, style: ui(11.5, color: C.inkSoft)),
                ] else if (g.checkedInByMe) ...[
                  const SizedBox(height: 8),
                  const Center(child: Tag('You checked in', icon: Icons.verified_rounded, bg: C.mint)),
                ] else if (g.goingByMe && g.isOpen) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Check-in opens 30 minutes before the start, at the venue.',
                    textAlign: TextAlign.center,
                    style: ui(12, color: C.inkSoft, h: 1.35),
                  ),
                ],
              ],
            ),
          ),
          if (g.isCompleted && g.impact != null) ...[
            const SizedBox(height: 12),
            WCard(
              color: C.mint.withValues(alpha: 0.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Impact: ${g.impact!.checkedIn} people showed up', style: ui(14, w: 600))),
                    ],
                  ),
                  if (g.impact!.note.isNotEmpty) ...[const SizedBox(height: 6), Text(g.impact!.note, style: ui(14, h: 1.45))],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          WCard(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: EngagementBar(
              likes: g.likeCount,
              comments: g.commentCount,
              shares: g.shareCount,
              liked: g.likedByMe,
              onLike: () => toggleGatheringLike(context, ref, g),
              onComment: () => openGatheringComments(context, ref, g),
              onShare: () => shareGathering(context, ref, g),
            ),
          ),
          if (g.attendees.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 8),
              child: Text('Going (${g.goingCount})', style: ui(14, w: 600)),
            ),
            WCard(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final a in g.attendees)
                    SizedBox(
                      width: 56,
                      child: Column(
                        children: [
                          PersonAvatar(a.asRef, size: 40),
                          const SizedBox(height: 4),
                          Text(a.name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(11.5, color: C.inkSoft)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (mine && !g.isCancelled && !g.isCompleted) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 8),
              child: Text('Organiser tools', style: ui(14, w: 600)),
            ),
            WCard(
              child: Column(
                children: [
                  PillButton(
                    label: 'Mark completed',
                    icon: Icons.flag_rounded,
                    color: started ? C.ink : C.muted,
                    fg: started ? Colors.white : C.inkSoft,
                    onPressed: started ? () => _complete(g) : () => showToast(context, 'You can wrap up once it has started.', error: true),
                  ),
                  const SizedBox(height: 8),
                  PillButton(label: 'Cancel gathering', icon: Icons.event_busy_rounded, color: C.muted, fg: C.ember, onPressed: () => _cancel(g)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: C.inkSoft),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: ui(14, h: 1.35))),
      ],
    );
  }
}
