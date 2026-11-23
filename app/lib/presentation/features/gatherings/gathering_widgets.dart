import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/domain/entities/gathering.dart';
import 'package:by_the_people/domain/entities/models.dart' show Person;
import 'package:by_the_people/presentation/widgets/map.dart' show MapItem;
import 'package:by_the_people/presentation/features/gatherings/welfare_common.dart';
import 'package:by_the_people/presentation/providers/gathering_providers.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Look of each gathering type: icon and a two-colour gradient.
class GatheringStyle {
  final IconData icon;
  final Color a, b;
  final String label;
  const GatheringStyle(this.icon, this.a, this.b, this.label);
}

const gatheringTypes = <String, GatheringStyle>{
  'plantation': GatheringStyle(Icons.park_rounded, Color(0xFFD9F0E3), Color(0xFFA6D9B6), 'Plantation'),
  'animal_care': GatheringStyle(Icons.pets_rounded, Color(0xFFFFE0BD), Color(0xFFFFB98A), 'Animal care'),
  'shelter': GatheringStyle(Icons.home_rounded, Color(0xFFD8D0F0), Color(0xFFA99BD6), 'Shelter'),
  'marathon': GatheringStyle(Icons.directions_run_rounded, Color(0xFFD6ECFA), Color(0xFF8CC8F0), 'Run'),
  'health': GatheringStyle(Icons.health_and_safety_rounded, Color(0xFFFAD3D8), Color(0xFFF4B8C0), 'Health'),
  'cleanup': GatheringStyle(Icons.cleaning_services_rounded, Color(0xFFE4EEB8), Color(0xFFC8DB7A), 'Clean-up'),
  'blood': GatheringStyle(Icons.bloodtype_rounded, Color(0xFFFFC9BD), Color(0xFFFF8E78), 'Blood'),
  'food_drive': GatheringStyle(Icons.restaurant_rounded, Color(0xFFFFE6A8), Color(0xFFFFC48A), 'Food drive'),
  'other': GatheringStyle(Icons.volunteer_activism_rounded, Color(0xFFE6E4DE), Color(0xFFCFCBC0), 'Other'),
};

GatheringStyle styleOf(String type) => gatheringTypes[type] ?? gatheringTypes['other']!;

String gatheringWhen(Gathering g) {
  final end = g.endAt;
  return '${fmtDateLong(g.startAt)} · ${fmtTime(g.startAt)}${end != null ? ' to ${fmtTime(end)}' : ''}';
}

/// "12 of 30 going" bar, or just a count when there is no cap.
class CapacityBar extends StatelessWidget {
  const CapacityBar(this.g, {super.key});
  final Gathering g;
  @override
  Widget build(BuildContext context) {
    final cap = g.capacity;
    if (cap == null || cap <= 0) {
      return Text('${g.goingCount} going', style: ui(12.5, color: C.inkSoft));
    }
    final left = g.spotsLeft ?? (cap - g.goingCount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HatchedProgress(
          value: g.goingCount / cap,
          fill: g.isFull ? C.ember : C.ink,
          track: C.muted,
          hatch: const Color(0x44FFFFFF),
          height: 6,
        ),
        const SizedBox(height: 5),
        Text(
          g.isFull ? 'Full, ${g.goingCount} going' : '${g.goingCount} of $cap going · $left spots left',
          style: ui(12, color: C.inkSoft),
        ),
      ],
    );
  }
}

/// Vote progress for a proposed campaign.
class VoteBar extends StatelessWidget {
  const VoteBar(this.g, {super.key});
  final Gathering g;
  @override
  Widget build(BuildContext context) {
    final needed = g.votesNeeded <= 0 ? 1 : g.votesNeeded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HatchedProgress(
          value: g.voteCount / needed,
          fill: const Color(0xFF7D6BC0),
          track: C.muted,
          hatch: const Color(0x55FFFFFF),
          height: 6,
        ),
        const SizedBox(height: 6),
        Text(
          g.voteCount >= needed ? 'Goal reached' : '${g.voteCount} of $needed votes · ${needed - g.voteCount} more to go live',
          style: ui(12, color: C.inkSoft),
        ),
      ],
    );
  }
}

extension GatheringCopy on Gathering {
  Gathering copyWith({bool? goingByMe, int? goingCount, bool? votedByMe, int? voteCount, bool? likedByMe, int? likeCount, int? commentCount, int? shareCount}) {
    final going = goingCount ?? this.goingCount;
    return Gathering(
      id: id, title: title, description: description, type: type, typeLabel: typeLabel, lat: lat, lng: lng, address: address,
      startAt: startAt, endAt: endAt, status: status, organizer: organizer, club: club, capacity: capacity, media: media,
      goingCount: going, spotsLeft: capacity == null ? spotsLeft : capacity! - going, goingByMe: goingByMe ?? this.goingByMe,
      checkedInByMe: checkedInByMe, voteCount: voteCount ?? this.voteCount, votesNeeded: votesNeeded,
      votedByMe: votedByMe ?? this.votedByMe, likeCount: likeCount ?? this.likeCount, likedByMe: likedByMe ?? this.likedByMe,
      commentCount: commentCount ?? this.commentCount, shareCount: shareCount ?? this.shareCount, shareText: shareText,
      publicUrl: publicUrl, distanceKm: distanceKm, attendees: attendees, impact: impact,
    );
  }
}

class GatheringOverlay extends OptimisticStore<Gathering> {}

final gatheringOverlayProvider = NotifierProvider<GatheringOverlay, Map<int, (Gathering, int)>>(GatheringOverlay.new);

/// [g] with any in-flight or just-confirmed optimistic change applied.
Gathering effective(WidgetRef ref, Gathering g) {
  ref.watch(gatheringOverlayProvider);
  return ref.read(gatheringOverlayProvider.notifier).fresh(g.id) ?? g;
}

final _inflight = <String>{};

/// Runs [change] optimistically on gathering [g]: shows [next] now, confirms with the server value, rolls back on error.
Future<void> _mutate(
  BuildContext context,
  WidgetRef ref,
  Gathering g, {
  required String key,
  required Gathering Function(Gathering cur) next,
  required Future<Done<Gathering>> Function(GatheringActions a) call,
  String? ok,
  String? failMessage,
}) async {
  final tag = '$key:${g.id}';
  if (_inflight.contains(tag)) return;
  _inflight.add(tag);
  final store = ref.read(gatheringOverlayProvider.notifier);
  final actions = ref.read(gatheringActionsProvider);
  final before = store.fresh(g.id) ?? g;
  final r = await optimisticRun<Done<Gathering>>(
    context,
    apply: () => store.put(g.id, next(before)),
    rollback: () => store.put(g.id, before),
    run: () => call(actions),
    failMessage: failMessage,
  );
  _inflight.remove(tag);
  if (r == null) return;
  store.put(g.id, r.value);
  if (context.mounted && (ok != null || r.rewards != null)) cheer(context, r.rewards, ok ?? '');
}

Future<void> toggleRsvp(BuildContext context, WidgetRef ref, Gathering g) {
  final cur = ref.read(gatheringOverlayProvider.notifier).fresh(g.id) ?? g;
  final on = !cur.goingByMe;
  return _mutate(
    context, ref, g,
    key: 'rsvp',
    next: (c) => c.copyWith(goingByMe: on, goingCount: (c.goingCount + (on ? 1 : -1)).clamp(0, 1 << 30)),
    call: (a) => a.rsvp(g.id, on: on),
    ok: on ? 'You are going' : 'RSVP cancelled',
    failMessage: on ? 'Could not RSVP. Please try again.' : 'Could not cancel your RSVP. Please try again.',
  );
}

Future<void> toggleVote(BuildContext context, WidgetRef ref, Gathering g) {
  final cur = ref.read(gatheringOverlayProvider.notifier).fresh(g.id) ?? g;
  final on = !cur.votedByMe;
  return _mutate(
    context, ref, g,
    key: 'vote',
    next: (c) => c.copyWith(votedByMe: on, voteCount: (c.voteCount + (on ? 1 : -1)).clamp(0, 1 << 30)),
    call: (a) => a.vote(g.id, on: on),
    ok: on ? 'Vote counted' : 'Vote withdrawn',
    failMessage: 'Could not record your vote. Please try again.',
  );
}

Future<void> toggleGatheringLike(BuildContext context, WidgetRef ref, Gathering g) {
  final cur = ref.read(gatheringOverlayProvider.notifier).fresh(g.id) ?? g;
  final on = !cur.likedByMe;
  return _mutate(
    context, ref, g,
    key: 'like',
    next: (c) => c.copyWith(likedByMe: on, likeCount: (c.likeCount + (on ? 1 : -1)).clamp(0, 1 << 30)),
    call: (a) => a.like(g.id, on: on),
    failMessage: 'Could not update your like. Please try again.',
  );
}

Future<void> openGatheringComments(BuildContext context, WidgetRef ref, Gathering g) {
  final actions = ref.read(gatheringActionsProvider);
  final store = ref.read(gatheringOverlayProvider.notifier);
  return showCommentsSheet(
    context,
    comments: gatheringCommentsProvider(g.id),
    onSend: (b) async {
      await actions.addComment(g.id, b);
      final cur = store.fresh(g.id) ?? g;
      store.put(g.id, cur.copyWith(commentCount: cur.commentCount + 1));
    },
  );
}

Future<void> shareGathering(BuildContext context, WidgetRef ref, Gathering g) async {
  final actions = ref.read(gatheringActionsProvider);
  await guarded(context, () => actions.share(g.id));
}

/// The main button for a gathering: Vote, RSVP, or state. Reads the optimistic state.
class GatheringPrimaryButton extends ConsumerWidget {
  const GatheringPrimaryButton(this.g, {super.key, this.compact = false});
  final Gathering g;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = effective(ref, this.g);
    final h = compact ? 34.0 : 44.0;
    Widget btn(String label, IconData icon, {VoidCallback? onTap, Color bg = C.ink, Color fg = Colors.white}) => TapScale(
      onTap: onTap,
      child: Container(
        height: h,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: onTap == null ? C.muted : bg, borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!compact) ...[Icon(icon, size: 16, color: onTap == null ? C.inkSoft : fg), const SizedBox(width: 6)],
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(13, color: onTap == null ? C.inkSoft : fg, w: 600)),
            ),
          ],
        ),
      ),
    );

    if (g.isCancelled) return btn('Cancelled', Icons.block_rounded);
    if (g.isCompleted) return btn('Completed', Icons.check_circle_rounded);
    if (g.isProposed) {
      return g.votedByMe
          ? btn('Voted', Icons.how_to_vote_rounded, bg: C.lime, fg: C.ink, onTap: () => toggleVote(context, ref, g))
          : btn('Vote to back it', Icons.how_to_vote_outlined, onTap: () => toggleVote(context, ref, g));
    }
    if (g.goingByMe) return btn('Going', Icons.check_rounded, bg: C.lime, fg: C.ink, onTap: () => toggleRsvp(context, ref, g));
    if (g.isFull) return btn('Full', Icons.event_busy_rounded);
    return btn('RSVP', Icons.event_available_rounded, onTap: () => toggleRsvp(context, ref, g));
  }
}

/// Marker colour per gathering type for maps.
MapItem gatheringMapItem(Gathering g) {
  final s = styleOf(g.type);
  return MapItem(
    id: '${g.id}',
    title: g.title,
    lat: g.lat,
    lng: g.lng,
    typeLabel: g.typeLabel,
    subtitle: '${fmtDateLong(g.startAt)} · ${fmtTime(g.startAt)}',
    color: Color.lerp(s.b, C.ink, 0.35)!,
    icon: s.icon,
    data: g,
  );
}

class GatheringCard extends ConsumerWidget {
  const GatheringCard({super.key, required this.g, required this.onTap});
  final Gathering g;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = effective(ref, this.g);
    final s = styleOf(g.type);
    final people = g.attendees.map((a) => Person(a.id, a.name, a.hue)).toList();
    final status = g.isProposed
        ? const CoverBadge('Proposed', icon: Icons.how_to_vote_rounded)
        : g.isCancelled
        ? const CoverBadge('Cancelled', bg: C.ink, fg: Colors.white)
        : g.isOngoing
        ? const CoverBadge('Happening now', icon: Icons.circle, bg: C.ink, fg: C.lime)
        : CoverBadge(g.typeLabel, icon: s.icon);
    return FeedCardShell(
      onTap: onTap,
      dim: g.isCancelled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverImage(media: g.media, icon: s.icon, height: g.media.isEmpty ? 96 : 150, badge: status),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PersonLine(g.organizer, size: 22, sub: g.club != null ? 'Hosted by ${g.club!.name}' : null),
                const SizedBox(height: 10),
                Text(g.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(16, w: 600, h: 1.3)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    InfoChip(Icons.event_rounded, '${fmtDateLong(g.startAt)} · ${fmtTime(g.startAt)}'),
                    if (g.address.isNotEmpty || g.distanceKm != null)
                      InfoChip(Icons.place_outlined, [if (g.address.isNotEmpty) g.address, if (g.distanceKm != null) km(g.distanceKm)].join(' · ')),
                  ],
                ),
                const SizedBox(height: 10),
                if (g.isProposed) VoteBar(g) else if (!g.isCancelled) CapacityBar(g),
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 6), child: Divider(height: 1, color: C.line)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            child: Row(
              children: [
                if (people.isNotEmpty) ...[AvatarStack(people: people, total: g.goingCount, size: 22), const SizedBox(width: 12)],
                ActionBtn(
                  icon: g.likedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  count: g.likeCount,
                  color: g.likedByMe ? C.ember : null,
                  onTap: () => toggleGatheringLike(context, ref, g),
                ),
                ActionBtn(icon: Icons.chat_bubble_outline_rounded, count: g.commentCount, onTap: () => openGatheringComments(context, ref, g)),
                const Spacer(),
                Flexible(flex: 2, child: GatheringPrimaryButton(g, compact: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GatheringListSkeleton extends StatelessWidget {
  const GatheringListSkeleton({super.key, this.count = 3});
  final int count;
  @override
  Widget build(BuildContext context) => Skeleton(
    child: Column(
      children: [
        for (var i = 0; i < count; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14)),
            clipBehavior: Clip.antiAlias,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 140, radius: 0),
                Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 120, height: 12),
                      SizedBox(height: 10),
                      SkeletonBox(height: 16),
                      SizedBox(height: 8),
                      SkeletonBox(width: 180, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
