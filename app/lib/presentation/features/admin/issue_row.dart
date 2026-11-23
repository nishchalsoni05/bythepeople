import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/core/utils/media.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/presentation/features/admin/authority_sheet.dart';
import 'package:by_the_people/presentation/features/detail/issue_detail_screen.dart';
import 'package:by_the_people/presentation/features/neta_portal/neta_sheets.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/presentation/widgets/media.dart';
import 'package:by_the_people/presentation/widgets/social.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Compact issue card for the admin queue and the neta lists, with role actions.
class IssueRow extends ConsumerWidget {
  final Issue issue;
  final bool adminActions, netaActions;
  const IssueRow({super.key, required this.issue, this.adminActions = false, this.netaActions = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = issue;
    final accent = authorityStatusColor(i.authorityStatus);
    return TapScale(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => IssueDetailScreen(id: i.id))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 6, color: i.escalated ? C.ember : accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (i.media.isNotEmpty && !isVideoPath(i.media.first))
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(width: 56, height: 56, child: NetImage(i.media.first))),
                      ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(categoryIcons[i.category] ?? Icons.circle, size: 14, color: C.inkSoft),
                          const SizedBox(width: 5),
                          Flexible(child: Text(i.categoryLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(12, color: C.inkSoft, w: 650))),
                          Text('  ·  ${relative(i.createdAt)}', style: ui(12, color: C.inkSoft)),
                        ]),
                        const SizedBox(height: 4),
                        Text(i.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(15, w: 700, h: 1.25)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (i.escalated) const EscalatedBadge(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(14)),
                      child: Text(authorityStatusLabel(i.authorityStatus), style: ui(11.5, w: 700)),
                    ),
                    if ((i.assignedTo ?? '').isNotEmpty)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(color: C.muted, borderRadius: BorderRadius.circular(14)),
                          child: Text('→ ${i.assignedTo}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(11.5, w: 650)),
                        ),
                      ),
                    SeverityChip(i.severity),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.thumb_up_alt_outlined, size: 15, color: C.inkSoft),
                    Text(' ${i.supportCount}', style: ui(12.5, color: C.inkSoft, w: 700)),
                    const SizedBox(width: 12),
                    const Icon(Icons.favorite_border_rounded, size: 15, color: C.inkSoft),
                    Text(' ${i.likeCount}', style: ui(12.5, color: C.inkSoft, w: 700)),
                    const SizedBox(width: 12),
                    const Icon(Icons.mode_comment_outlined, size: 15, color: C.inkSoft),
                    Text(' ${i.commentCount}', style: ui(12.5, color: C.inkSoft, w: 700)),
                    const Spacer(),
                    if (adminActions && i.status != 'closed')
                      _MiniBtn(label: 'Update', icon: Icons.edit_note_rounded, onTap: () => showAuthoritySheet(context, i)),
                  ]),
                  if (netaActions) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _MiniBtn(label: 'Respond', icon: Icons.campaign_rounded, onTap: () => showNetaResponseSheet(context, i))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: i.escalated
                            ? _MiniBtn(label: 'Withdraw', icon: Icons.undo_rounded, onTap: () => _withdraw(context, ref))
                            : _MiniBtn(label: 'Escalate', icon: Icons.trending_up_rounded, hot: true, onTap: () => showEscalateSheet(context, i)),
                      ),
                    ]),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(actionsProvider).withdrawEscalation(issue.id);
      if (context.mounted) showToast(context, 'Escalation withdrawn');
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.message, error: true);
    }
  }
}

class _MiniBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool hot;
  const _MiniBtn({required this.label, required this.icon, required this.onTap, this.hot = false});
  @override
  Widget build(BuildContext context) => TapScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: hot ? C.ember : C.ink, borderRadius: BorderRadius.circular(18)),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 15, color: Colors.white),
            const SizedBox(width: 5),
            Text(label, style: ui(12.5, color: Colors.white, w: 700)),
          ]),
        ),
      );
}
