import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/features/detail/comments_section.dart' show RoleTag;
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/presentation/widgets/media.dart';
import 'package:by_the_people/presentation/widgets/social.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Flat, muted status palette: surfaces are always white; only [bar] (progress/status accent) varies.
class CardPalette {
  final Color bg, fg, soft, bar;
  const CardPalette(this.bg, this.fg, this.soft, this.bar);
}

CardPalette paletteFor(Issue i) {
  final bg = switch (i.status) {
    'closed' => C.mintDeep,
    'pending_verification' => C.sky,
    'event' || 'in_progress' => C.lavender,
    _ => switch (i.severity) { 'critical' => C.blush, 'high' => C.amber, 'medium' => C.lime, _ => C.mint },
  };
  final bar = switch (i.status) {
    'closed' => const Color(0xFF3F9A63),
    'pending_verification' => const Color(0xFF3B82C4),
    'event' || 'in_progress' => const Color(0xFF6F62B8),
    _ => C.ember,
  };
  return CardPalette(Color.lerp(bg, Colors.white, 0.45)!, C.ink, C.muted, bar);
}

/// Where the issue is, as a short human line ("Raipur, Chhattisgarh"), plus distance only when near.
String issueWhere(Issue i) {
  final place = placeLine(i.area.city, i.area.state, address: i.address);
  final d = km(i.distanceKm);
  return [if (place.isNotEmpty) place, if (d.isNotEmpty) d].join(' · ');
}

/// Social-feed card: author row, title, 2-line description, 16:9 image, meta chips, action bar.
class IssueCard extends ConsumerWidget {
  final Issue issue;
  final VoidCallback onTap;
  const IssueCard({super.key, required this.issue, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleProvider);
    final isIssue = issue.phase == 'issue';
    final icon = categoryIcons[issue.category] ?? Icons.label_outline_rounded;
    final where = issueWhere(issue);
    final progress = isIssue ? (issue.supportCount / (issue.threshold == 0 ? 1 : issue.threshold)).clamp(0.0, 1.0) : null;
    final bar = paletteFor(issue).bar;
    return FlatCard(
      margin: const EdgeInsets.only(bottom: 14),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Row(children: [
            Avatar(issue.reporter, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(issue.reporter.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(13.5, w: 650))),
                  RoleTag(issue.reporter.role),
                ]),
                Text([relative(issue.createdAt), if (where.isNotEmpty) where].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(12, color: C.inkSoft)),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Text(issue.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(16, w: 650, h: 1.3)),
        ),
        if (issue.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Text(issue.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(13.5, color: C.inkSoft, h: 1.4)),
          ),
        if (issue.media.isNotEmpty) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: LayoutBuilder(
              builder: (context, c) => MediaGallery(media: issue.media, height: c.maxWidth * 9 / 16, radius: 16, tapToOpen: false, fallbackIcon: icon),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            TagChip(issue.categoryLabel, icon: icon),
            TagChip(
              isIssue ? 'Open' : (issue.status == 'closed' ? 'Resolved' : statusLabel(issue.status)),
              color: bar,
              bg: bar.withValues(alpha: 0.10),
            ),
            if (issue.severity == 'critical' || issue.severity == 'high')
              TagChip(issue.severity == 'critical' ? 'Critical' : 'High priority', icon: Icons.priority_high_rounded, color: C.ember, bg: C.ember.withValues(alpha: 0.10)),
            if (issue.escalated) const EscalatedBadge(),
            if (issue.authority != null) ConstrainedBox(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 80), child: AuthorityChip(issue)),
            if (!isIssue && issue.scheduledAt != null && !issue.isClosed) TagChip(whenLabel(issue.scheduledAt!), icon: Icons.schedule_rounded),
          ]),
        ),
        if (progress != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: C.muted, color: bar),
                ),
              ),
              const SizedBox(width: 10),
              Text('${issue.supportCount}/${issue.threshold} support', style: ui(12, color: C.inkSoft, w: 600)),
            ]),
          )
        else if (issue.volunteerCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(children: [
              AvatarStack(people: issue.volunteers, total: issue.volunteerCount, size: 22, max: 3),
              const SizedBox(width: 8),
              Text('${issue.volunteerCount} volunteering', style: ui(12, color: C.inkSoft, w: 600)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Row(children: [
            UpvoteButton(
              active: issue.likedByMe,
              count: issue.likeCount,
              onToggle: (next) async {
                await ref.read(actionsProvider).toggleLike(issue.id, !next);
              },
            ),
            const SizedBox(width: 6),
            CountAction(icon: Icons.mode_comment_outlined, count: issue.commentCount, onTap: onTap),
            const SizedBox(width: 6),
            CountAction(icon: Icons.ios_share_rounded, count: issue.shareCount, onTap: () => shareIssue(context, ref, issue)),
            const Spacer(),
            if (isIssue && issue.status == 'open' && role == 'citizen' && !issue.reportedByMe) SupportChipButton(issue: issue),
          ]),
        ),
      ]),
    );
  }
}
