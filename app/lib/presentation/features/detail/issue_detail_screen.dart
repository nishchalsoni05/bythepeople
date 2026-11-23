import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/core/utils/media.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/widgets/cards.dart';
import 'package:by_the_people/presentation/widgets/celebrate.dart';
import 'package:by_the_people/presentation/widgets/map.dart';
import 'package:by_the_people/presentation/widgets/radar.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';
import 'package:by_the_people/presentation/features/neta/neta_screen.dart';
import 'package:by_the_people/presentation/features/admin/authority_sheet.dart';
import 'package:by_the_people/presentation/features/detail/comments_section.dart';
import 'package:by_the_people/presentation/features/neta_portal/neta_sheets.dart';
import 'package:by_the_people/presentation/widgets/media.dart';
import 'package:by_the_people/presentation/widgets/social.dart';

class IssueDetailScreen extends ConsumerStatefulWidget {
  final int id;
  const IssueDetailScreen({super.key, required this.id});
  @override
  ConsumerState<IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends ConsumerState<IssueDetailScreen> {
  bool _busy = false;

  /// Optimistic 'I support this' state, shown instantly and rolled back when the call fails.
  bool? _optSupport;

  Future<void> _run(Future<ActionResult> Function() fn, {String? ok, bool confetti = false, String Function(ActionResult)? headline}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await fn();
      if (!mounted) return;
      celebrate(context, rewards: r.rewards, headline: headline?.call(r) ?? ok, confetti: confetti || r.converted || r.outcome == 'closed');
    } catch (e) {
      if (mounted) {
        _optSupport = null;
        toastError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(issueProvider(widget.id));
    final me = ref.watch(authProvider).user;
    return Scaffold(
      body: PageBackdrop(
        child: async.when(
          loading: () => const SafeArea(child: DetailSkeleton()),
          error: (e, _) => SafeArea(child: ErrorState(error: e, onRetry: () => ref.invalidate(issueProvider(widget.id)))),
          data: (i) => _content(i, me),
        ),
      ),
    );
  }

  Widget _content(Issue i, UserProfile? me) {
    final p = paletteFor(i);
    final loc = ref.watch(locationProvider);
    final pad = MediaQuery.of(context).padding;
    if (_optSupport != null && _optSupport == i.supportedByMe) _optSupport = null;
    final steps = ['Need', 'Event', 'In progress', 'Fulfilled'];
    final stepIndex = {'open': 0, 'event': 1, 'in_progress': 2, 'pending_verification': 2, 'closed': 3}[i.status]!;

    return Stack(children: [
      ListView(
        padding: EdgeInsets.fromLTRB(16, pad.top + 8, 16, 140),
        children: [
          Row(children: [
            CircleBtn(icon: Icons.arrow_back_rounded, onTap: () => Navigator.of(context).pop()),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: p.bar.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
              child: Text(statusLabel(i.status), style: ui(12.5, w: 650, color: p.bar)),
            ),
          ]),
          const SizedBox(height: 14),
          if (i.media.isNotEmpty) ...[
            MediaGallery(media: i.media, height: 220, radius: R.card, fallbackIcon: categoryIcons[i.category]),
            const SizedBox(height: 14),
          ],
          // hero card
          _Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Avatar(i.reporter, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(i.reporter.shownName, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(13.5, w: 650))),
                      RoleTag(i.reporter.role),
                    ]),
                    Text([relative(i.createdAt), if (issueWhere(i).isNotEmpty) issueWhere(i)].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(12, color: C.inkSoft)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Text(i.title, style: ui(20, w: 650, h: 1.3)),
              if (i.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(i.description, style: ui(14.5, color: C.ink.withValues(alpha: 0.82), h: 1.5)),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                TagChip(i.categoryLabel, icon: categoryIcons[i.category]),
                SeverityChip(i.severity),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          _Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                UpvoteButton(
                  large: true,
                  active: i.likedByMe,
                  count: i.likeCount,
                  onToggle: (next) async {
                    await ref.read(actionsProvider).toggleLike(i.id, !next);
                  },
                ),
                const SizedBox(width: 10),
                CountAction(icon: Icons.mode_comment_outlined, count: i.commentCount),
                const SizedBox(width: 10),
                CountAction(icon: Icons.ios_share_rounded, count: i.shareCount, onTap: () => shareIssue(context, ref, i)),
                const Spacer(),
                if (i.escalated) const EscalatedBadge(),
              ]),
              if (i.authority != null) ...[
                const Divider(height: 22, color: C.line),
                _AuthorityBlock(issue: i),
              ],
              if (i.escalated && i.escalatedBy != null) ...[
                const Divider(height: 22, color: C.line),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.trending_up_rounded, size: 18, color: C.ember),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Escalated by ${i.escalatedBy!.name}${(i.escalationNote ?? '').isNotEmpty ? ': “${i.escalationNote}”' : ''}',
                      style: ui(13, color: C.inkSoft, h: 1.4, w: 600),
                    ),
                  ),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          // progress
          _Card(
            child: i.phase == 'issue'
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      RollingNumber(i.supportCount + ((_optSupport == true && !i.supportedByMe) ? 1 : 0), style: ui(26, w: 650)),
                      Text(' / ${i.threshold}', style: ui(17, color: C.inkSoft, w: 600)),
                      const Spacer(),
                      Text('backers', style: ui(13, color: C.inkSoft, w: 600)),
                    ]),
                    const SizedBox(height: 12),
                    HatchedProgress(value: i.supportCount / i.threshold, fill: p.bar, track: C.muted, height: 8),
                    const SizedBox(height: 10),
                    Text(
                      '${i.threshold - i.supportCount} more backer${i.threshold - i.supportCount == 1 ? ' turns' : 's turn'} this into an event'
                      '${i.linkedCount > 0 ? '  ·  ${i.linkedCount} similar post${i.linkedCount == 1 ? '' : 's'} raise its urgency' : ''}',
                      style: ui(13, color: C.inkSoft, h: 1.4),
                    ),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      for (var s = 0; s < steps.length; s++) ...[
                        Expanded(
                          child: Column(children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              height: 8,
                              decoration: BoxDecoration(color: s <= stepIndex ? p.bar : C.muted, borderRadius: BorderRadius.circular(8)),
                            ),
                            const SizedBox(height: 8),
                            Text(steps[s], style: ui(11.5, color: s <= stepIndex ? C.ink : C.inkSoft, w: s == stepIndex ? 750 : 550)),
                          ]),
                        ),
                        if (s < steps.length - 1) const SizedBox(width: 6),
                      ],
                    ]),
                    if (i.scheduledAt != null && !i.isClosed) ...[
                      const SizedBox(height: 16),
                      Row(children: [
                        const Icon(Icons.event_rounded, size: 20, color: C.ink),
                        const SizedBox(width: 10),
                        Expanded(child: Text(whenLabel(i.scheduledAt!), style: ui(15, w: 700))),
                        if (i.isOrganiser && i.status != 'pending_verification')
                          TapScale(
                            onTap: _busy ? null : () => _reschedule(i),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(color: C.muted, borderRadius: BorderRadius.circular(20)),
                              child: Text('Reschedule', style: ui(12.5, w: 700)),
                            ),
                          ),
                      ]),
                    ],
                  ]),
          ),
          if (i.status == 'pending_verification' && i.verification != null) ...[
            const SizedBox(height: 14),
            _Card(
              tint: const Color(0xFFE6F3FC),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.fact_check_rounded, color: Color(0xFF2F80ED)),
                  const SizedBox(width: 8),
                  Text('Volunteers say it is fixed', style: ui(15, w: 750)),
                ]),
                if ((i.resolutionNote ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('“${i.resolutionNote}”', style: ui(14, color: C.inkSoft, h: 1.4)),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _Vote(label: 'Confirmed', n: i.verification!.approvals, need: i.verification!.needed, color: const Color(0xFF6FBF8A))),
                  const SizedBox(width: 10),
                  Expanded(child: _Vote(label: 'Not met', n: i.verification!.rejections, need: i.verification!.needed, color: C.ember)),
                ]),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          MapPreview(lat: i.lat, lng: i.lng, label: i.title),
          const SizedBox(height: 14),
          // where
          if (loc.has)
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RadarMap(
                userLat: loc.lat!, userLng: loc.lng!, radiusKm: i.radiusKm,
                pins: [RadarPin(i.lat, i.lng, p.bar == C.lime ? const Color(0xFF8FA83A) : p.bar, big: true)],
                height: 220,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                child: Row(children: [
                  Icon(i.inRange == true ? Icons.check_circle_rounded : Icons.do_not_disturb_on_rounded, size: 18, color: i.inRange == true ? const Color(0xFF3FA66A) : C.ember),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      i.inRange == true
                          ? (km(i.distanceKm).isEmpty ? 'You are inside the support range' : 'You are ${km(i.distanceKm)} away, inside the ${i.radiusKm % 1 == 0 ? i.radiusKm.toInt() : i.radiusKm} km range')
                          : (km(i.distanceKm).isEmpty ? 'You are outside the ${i.radiusKm % 1 == 0 ? i.radiusKm.toInt() : i.radiusKm} km support range' : 'You are ${km(i.distanceKm)} away. Supporting needs you within ${i.radiusKm % 1 == 0 ? i.radiusKm.toInt() : i.radiusKm} km'),
                      style: ui(13, color: C.inkSoft, w: 600),
                    ),
                  ),
                ]),
              ),
            ]),
          const SizedBox(height: 14),
          if (i.politician != null)
            TapScale(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NetaDetailScreen(id: i.politician!.id))),
              child: _Card(
                child: Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: hueColor(i.politician!.hue, l: 0.72)),
                    child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Responsible', style: ui(12, color: C.inkSoft, w: 650)),
                      Text(i.politician!.name, style: ui(16, w: 750)),
                      Text('${i.politician!.constituency} · ${i.politician!.party}', style: ui(12.5, color: C.inkSoft)),
                      if (i.area.line.isNotEmpty) Text('${i.area.line} · ${i.area.region ?? ''}', style: ui(12, color: C.inkSoft)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: C.inkSoft),
                ]),
              ),
            ),
          const SizedBox(height: 14),
          _Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Supporters', style: ui(15, w: 750)),
              const SizedBox(height: 10),
              Row(children: [
                AvatarStack(people: i.supporters, total: i.supportCount, size: 34, max: 6),
                const SizedBox(width: 10),
                Text('${i.supportCount} neighbour${i.supportCount == 1 ? '' : 's'}', style: ui(13, color: C.inkSoft, w: 600)),
              ]),
              if (i.phase != 'issue') ...[
                const SizedBox(height: 18),
                Text('Volunteers', style: ui(15, w: 750)),
                const SizedBox(height: 10),
                if (i.volunteerCount == 0)
                  Text('No volunteers yet. Be the first!', style: ui(13, color: C.inkSoft))
                else
                  Row(children: [
                    AvatarStack(people: i.volunteers, total: i.volunteerCount, size: 34, max: 6),
                    const SizedBox(width: 10),
                    Text('${i.volunteerCount} volunteering', style: ui(13, color: C.inkSoft, w: 600)),
                  ]),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          _Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Timeline', style: ui(15, w: 750)),
              const SizedBox(height: 12),
              for (var t = i.timeline.length - 1; t >= 0; t--) _TimelineRow(entry: i.timeline[t], last: t == 0),
            ]),
          ),
          const SizedBox(height: 14),
          _Card(child: CommentsSection(issueId: i.id)),
        ],
      ),
      if (MediaQuery.of(context).viewInsets.bottom == 0)
        Positioned(left: 12, right: 12, bottom: pad.bottom + 10, child: _actions(i, me)),
    ]);
  }

  // ----- actions -----
  Widget _actions(Issue i, UserProfile? me) {
    final a = ref.read(actionsProvider);
    Widget bar(Widget child) => Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line), boxShadow: const [BoxShadow(color: Color(0x1417181A), blurRadius: 12, offset: Offset(0, 3))]),
          child: child,
        );

    if (me?.isAdmin == true) {
      return bar(PillButton(
        label: i.authorityStatus == 'resolved' || i.status == 'closed' ? 'View status (${authorityStatusLabel(i.authorityStatus)})' : 'Update status',
        icon: Icons.edit_note_rounded,
        color: C.ink,
        onPressed: i.status == 'closed' ? null : () => showAuthoritySheet(context, i),
      ));
    }
    if (me?.isNeta == true) {
      return bar(Row(children: [
        Expanded(child: PillButton(label: 'Respond', icon: Icons.campaign_rounded, color: C.ink, onPressed: () => showNetaResponseSheet(context, i))),
        const SizedBox(width: 8),
        Expanded(
          child: i.escalated
              ? PillButton(
                  label: 'Withdraw', icon: Icons.undo_rounded, color: C.muted, fg: C.ink, loading: _busy,
                  onPressed: () => _run(() => a.withdrawEscalation(i.id), ok: 'Escalation withdrawn'),
                )
              : PillButton(label: 'Escalate', icon: Icons.trending_up_rounded, color: C.ember, onPressed: () => showEscalateSheet(context, i)),
        ),
      ]));
    }
    if (me?.isFoundation == true) {
      return bar(PillButton(label: 'Share this need', icon: Icons.ios_share_rounded, color: C.ink, onPressed: () => shareIssue(context, ref, i)));
    }

    if (i.status == 'open') {
      if (_optSupport ?? i.supportedByMe) {
        return bar(Row(children: [
          const Expanded(child: PillButton(label: 'You are backing this', icon: Icons.check_rounded, color: C.muted, fg: C.ink, onPressed: null)),
          if (!i.reportedByMe && i.supportedByMe) ...[
            const SizedBox(width: 8),
            PillButton(label: 'Withdraw', expand: false, color: C.muted, fg: C.ink, loading: _busy, onPressed: () => _run(() => a.withdraw(i.id), ok: 'Support withdrawn')),
          ],
        ]));
      }
      if (i.inRange == false) {
        return bar(PillButton(label: 'Too far to help (max ${i.radiusKm % 1 == 0 ? i.radiusKm.toInt() : i.radiusKm} km)', icon: Icons.lock_outline_rounded, onPressed: null));
      }
      return bar(PillButton(
        label: 'I can help', icon: Icons.pan_tool_alt_outlined, color: C.ember, loading: _busy,
        onPressed: () {
          setState(() => _optSupport = true);
          _run(() => a.support(i.id), ok: 'Thanks for backing this need', headline: (r) => r.converted ? 'This is now an Event!' : 'Support added');
        },
      ));
    }

    if (i.status == 'event' || i.status == 'in_progress') {
      if (i.volunteeringByMe) {
        return bar(Row(children: [
          if (i.status == 'in_progress')
            Expanded(child: PillButton(label: 'Mark fulfilled', icon: Icons.done_all_rounded, color: C.ink, loading: _busy, onPressed: () => _resolve(i))),
          if (i.status == 'in_progress') const SizedBox(width: 8),
          PillButton(label: 'Leave', expand: false, color: C.muted, fg: C.ink, onPressed: _busy ? null : () => _run(() => a.leave(i.id), ok: 'You left the event')),
        ]));
      }
      if (me?.volunteer != true) {
        return bar(PillButton(
          label: 'Turn on volunteer mode to join', icon: Icons.volunteer_activism_rounded, color: C.lavender, fg: C.ink, loading: _busy,
          onPressed: () async {
            setState(() => _busy = true);
            try {
              await ref.read(authProvider.notifier).patch({'volunteer': true});
              if (mounted) showToast(context, 'Volunteer mode on. Tap again to join.');
            } catch (e) {
              if (mounted) toastError(context, e);
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
        ));
      }
      return bar(PillButton(
        label: 'Join as volunteer', icon: Icons.volunteer_activism_rounded, color: C.ink, loading: _busy,
        onPressed: () => _run(() => a.join(i.id), headline: (r) => 'You are in! See you there'),
      ));
    }

    if (i.status == 'pending_verification') {
      if (i.verifiedByMe) {
        return bar(const PillButton(label: 'Thanks, your vote is in', icon: Icons.check_rounded, color: C.lime, fg: C.ink, onPressed: null));
      }
      if (i.supportedByMe && !i.volunteeringByMe) {
        return bar(Row(children: [
          Expanded(child: PillButton(label: 'Not met', icon: Icons.close_rounded, color: C.muted, fg: C.ink, onPressed: _busy ? null : () => _run(() => a.verify(i.id, false), ok: 'Marked as not met'))),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: PillButton(label: 'Need met', icon: Icons.check_rounded, color: C.ink, loading: _busy, onPressed: () => _run(() => a.verify(i.id, true), headline: (r) => r.outcome == 'closed' ? 'Fulfilled and closed!' : 'Vote counted'))),
        ]));
      }
      return bar(const PillButton(label: 'Waiting for backers to confirm', icon: Icons.hourglass_top_rounded, onPressed: null));
    }
    return bar(const PillButton(label: 'Fulfilled and confirmed', icon: Icons.verified_rounded, color: C.mintDeep, fg: C.ink, onPressed: null));
  }

  Future<void> _resolve(Issue i) async {
    final ctl = TextEditingController();
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(color: C.canvas, borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('What was done?', style: ui(20, w: 650)),
            const SizedBox(height: 6),
            Text('People who backed this need will be asked to confirm it was met.', style: ui(13.5, color: C.inkSoft)),
            const SizedBox(height: 14),
            TextField(
              controller: ctl, maxLines: 3, autofocus: true, style: ui(15),
              decoration: InputDecoration(
                hintText: 'e.g. 40 school bags delivered to the children', filled: true, fillColor: C.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            PillButton(label: 'Submit for verification', onPressed: () => Navigator.pop(ctx, ctl.text.trim())),
          ]),
        ),
      ),
    );
    if (note == null || !mounted) return;
    await _run(() => ref.read(actionsProvider).resolve(i.id, note), ok: 'Sent to neighbours for verification');
  }

  Future<void> _reschedule(Issue i) async {
    final d = await showDatePicker(
      context: context,
      initialDate: i.scheduledAt != null && dt(i.scheduledAt!).isAfter(DateTime.now()) ? dt(i.scheduledAt!) : DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 10, minute: 0));
    if (t == null || !mounted) return;
    final at = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    await _run(() => ref.read(actionsProvider).schedule(i.id, at), ok: 'Event rescheduled. Volunteers notified');
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final Color tint;
  const _Card({required this.child, this.tint = C.surface});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(R.card), border: Border.all(color: C.line)),
        child: child,
      );
}

class _Vote extends StatelessWidget {
  final String label;
  final int n, need;
  final Color color;
  const _Vote({required this.label, required this.n, required this.need, required this.color});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$label  $n/$need', style: ui(12.5, w: 700)),
        const SizedBox(height: 6),
        HatchedProgress(value: n / need, fill: color, track: Colors.white, hatch: const Color(0x55FFFFFF), height: 10),
      ]);
}

class _AuthorityBlock extends StatelessWidget {
  final Issue issue;
  const _AuthorityBlock({required this.issue});
  @override
  Widget build(BuildContext context) {
    final a = issue.authority!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Verified by', style: ui(12, color: C.inkSoft, w: 650)),
      const SizedBox(height: 6),
      Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: authorityStatusColor(issue.authorityStatus), shape: BoxShape.circle),
          child: const Icon(Icons.account_balance_rounded, size: 20, color: C.ink),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.name, style: ui(15, w: 750), maxLines: 2, overflow: TextOverflow.ellipsis),
            Text([a.department, a.handle].where((e) => e.isNotEmpty).join(' · '), style: ui(12.5, color: C.inkSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 6, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: authorityStatusColor(issue.authorityStatus), borderRadius: BorderRadius.circular(14)),
          child: Text(authorityStatusLabel(issue.authorityStatus), style: ui(12, w: 700)),
        ),
        if ((issue.assignedTo ?? '').isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: C.muted, borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.assignment_ind_outlined, size: 13, color: C.inkSoft),
              const SizedBox(width: 4),
              Text('Assigned: ${issue.assignedTo}', style: ui(12, w: 650)),
            ]),
          ),
      ]),
    ]);
  }
}

class _TimelineRow extends StatelessWidget {
  final TimelineEntry entry;
  final bool last;
  const _TimelineRow({required this.entry, required this.last});
  @override
  Widget build(BuildContext context) {
    final color = switch (entry.kind) {
      'authority' => const Color(0xFF4FA3DA),
      'neta' => C.emberLight,
      'system' => C.line,
      _ => const {
            'open': C.lime, 'event': C.lavender, 'in_progress': C.lavender, 'pending_verification': C.sky, 'closed': Color(0xFF6FBF8A),
          }[entry.status] ?? C.lime,
    };
    final who = switch (entry.kind) {
      'authority' => 'Verified',
      'neta' => 'Neta',
      _ => null,
    };
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 22,
          child: Column(children: [
            Container(width: 12, height: 12, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            if (!last) Expanded(child: Container(width: 2, color: C.line)),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (who != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('${who.toUpperCase()}${entry.userName != null ? ' · ${entry.userName}' : ''}', style: ui(10.5, color: C.inkSoft, w: 750, ls: 0.6), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              Text(entry.note ?? statusLabel(entry.status), style: ui(13.5, w: 650, h: 1.35)),
              if (entry.media.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var m = 0; m < entry.media.length; m++)
                    GestureDetector(
                      onTap: () => openMediaViewer(context, entry.media, m),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          width: 84, height: 84,
                          child: isVideoPath(entry.media[m])
                              ? Container(color: C.inkCard, child: const Icon(Icons.play_circle_fill_rounded, color: Colors.white))
                              : NetImage(entry.media[m]),
                        ),
                      ),
                    ),
                ]),
              ],
              const SizedBox(height: 3),
              Text('${fmtDate(entry.createdAt)} · ${fmtTime(entry.createdAt)}', style: ui(12, color: C.inkSoft)),
            ]),
          ),
        ),
      ]),
    );
  }
}
