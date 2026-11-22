import 'package:flutter/material.dart';
import '../format.dart';
import '../models.dart';
import '../tokens.dart';
import 'ui.dart';

class CardPalette {
  final Color bg, fg, soft, bar;
  const CardPalette(this.bg, this.fg, this.soft, this.bar);
}

CardPalette paletteFor(Issue i) {
  switch (i.status) {
    case 'closed':
      return const CardPalette(C.mintDeep, C.ink, Color(0x33FFFFFF), Color(0xFF6FBF8A));
    case 'pending_verification':
      return const CardPalette(C.sky, C.ink, Color(0x40FFFFFF), Color(0xFF4FA3DA));
    case 'event':
    case 'in_progress':
      return const CardPalette(C.lavender, C.ink, Color(0x40FFFFFF), Color(0xFF7D6BC0));
  }
  switch (i.severity) {
    case 'critical':
      return const CardPalette(C.inkCard, Colors.white, Color(0x22FFFFFF), C.lime);
    case 'high':
      return const CardPalette(C.amber, C.ink, Color(0x40FFFFFF), C.ember);
    case 'medium':
      return const CardPalette(C.lime, C.ink, Color(0x40FFFFFF), Color(0xFF8FA83A));
    default:
      return const CardPalette(C.mint, C.ink, Color(0x66FFFFFF), Color(0xFF6FBF8A));
  }
}

class IssueCard extends StatelessWidget {
  final Issue issue;
  final VoidCallback onTap;
  const IssueCard({super.key, required this.issue, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = paletteFor(issue);
    final isIssue = issue.phase == 'issue';
    final dark = p.bg == C.inkCard;
    final progress = isIssue
        ? issue.supportCount / issue.threshold
        : issue.status == 'closed'
            ? 1.0
            : issue.status == 'pending_verification'
                ? 0.85
                : issue.status == 'in_progress'
                    ? 0.5
                    : 0.15;
    final label = isIssue
        ? '${issue.supportCount} of ${issue.threshold} supports'
        : issue.status == 'closed'
            ? 'Resolved'
            : statusLabel(issue.status);
    return TapScale(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
        decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(R.card)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(categoryIcons[issue.category] ?? Icons.circle, size: 15, color: p.fg.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Flexible(child: Text(issue.categoryLabel, style: ui(12.5, color: p.fg.withValues(alpha: 0.7), w: 650), overflow: TextOverflow.ellipsis)),
                  if (issue.distanceKm != null) ...[
                    Text('  ·  ', style: ui(12.5, color: p.fg.withValues(alpha: 0.5))),
                    Text(km(issue.distanceKm), style: ui(12.5, color: p.fg.withValues(alpha: 0.7), w: 650)),
                  ],
                ]),
                const SizedBox(height: 8),
                Text(issue.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(17, color: p.fg, w: 650, h: 1.25, ls: -0.2)),
              ]),
            ),
            const SizedBox(width: 12),
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const Icon(Icons.north_east_rounded, size: 18, color: C.ink),
            ),
          ]),
          const SizedBox(height: 14),
          HatchedProgress(
            value: progress,
            fill: p.bar,
            track: dark ? const Color(0x33FFFFFF) : const Color(0x22000000),
            hatch: const Color(0x44FFFFFF),
            label: label,
            height: 28,
            labelColor: C.ink,
          ),
          const SizedBox(height: 14),
          Row(children: [
            if (isIssue)
              AvatarStack(people: issue.supporters, total: issue.supportCount, ring: p.bg)
            else
              AvatarStack(people: issue.volunteers, total: issue.volunteerCount, ring: p.bg),
            if (!isIssue && issue.volunteerCount == 0)
              Text('Be the first to volunteer', style: ui(12.5, color: p.fg.withValues(alpha: 0.75), w: 600)),
            if (!isIssue && issue.volunteerCount > 0) ...[
              const SizedBox(width: 8),
              Text('${issue.volunteerCount} volunteering', style: ui(12.5, color: p.fg.withValues(alpha: 0.75), w: 600)),
            ],
            const Spacer(),
            if (isIssue)
              SeverityChip(issue.severity, onDark: dark)
            else if (issue.scheduledAt != null && !issue.isClosed)
              _Pill(icon: Icons.schedule_rounded, text: whenLabel(issue.scheduledAt!), fg: p.fg)
            else if (issue.isClosed)
              _Pill(icon: Icons.check_rounded, text: issue.closedAt != null ? fmtDate(issue.closedAt!) : 'Done', fg: p.fg),
          ]),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color fg;
  const _Pill({required this.icon, required this.text, required this.fg});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: fg.withValues(alpha: 0.35), width: 1.2)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(text, style: ui(12, color: fg, w: 650)),
        ]),
      );
}
