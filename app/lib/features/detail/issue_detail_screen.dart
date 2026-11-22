import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/state.dart';
import '../../core/tokens.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/celebrate.dart';
import '../../core/widgets/radar.dart';
import '../../core/widgets/ui.dart';
import '../neta/neta_screen.dart';

class IssueDetailScreen extends ConsumerStatefulWidget {
  final int id;
  const IssueDetailScreen({super.key, required this.id});
  @override
  ConsumerState<IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends ConsumerState<IssueDetailScreen> {
  bool _busy = false;

  Future<void> _run(Future<ActionResult> Function() fn, {String? ok, bool confetti = false, String Function(ActionResult)? headline}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await fn();
      if (!mounted) return;
      celebrate(context, rewards: r.rewards, headline: headline?.call(r) ?? ok, confetti: confetti || r.converted || r.outcome == 'closed');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
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
          loading: () => const SafeArea(child: LoadingOrb()),
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
    final dark = p.bg == C.inkCard;
    final steps = ['Issue', 'Event', 'In progress', 'Verified'];
    final stepIndex = {'open': 0, 'event': 1, 'in_progress': 2, 'pending_verification': 2, 'closed': 3}[i.status]!;

    return Stack(children: [
      ListView(
        padding: EdgeInsets.fromLTRB(16, pad.top + 8, 16, 140),
        children: [
          Row(children: [
            CircleBtn(icon: Icons.arrow_back_rounded, onTap: () => Navigator.of(context).pop()),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(30), boxShadow: softShadow),
              child: Text(statusLabel(i.status), style: ui(13, w: 700)),
            ),
          ]),
          const SizedBox(height: 14),
          // hero card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(R.card)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: p.soft, shape: BoxShape.circle),
                  child: Icon(categoryIcons[i.category], size: 18, color: p.fg),
                ),
                const SizedBox(width: 10),
                Text(i.categoryLabel, style: ui(13.5, color: p.fg, w: 700)),
                const Spacer(),
                SeverityChip(i.severity, onDark: dark),
              ]),
              const SizedBox(height: 18),
              Text(i.title, style: ui(21, color: p.fg, w: 700, h: 1.25, ls: -0.2)),
              if (i.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(i.description, style: ui(14.5, color: p.fg.withValues(alpha: 0.8), h: 1.5)),
              ],
              const SizedBox(height: 18),
              Row(children: [
                Avatar(i.reporter, size: 28, ring: p.bg),
                const SizedBox(width: 8),
                Expanded(child: Text('${i.reporter.name} · ${relative(i.createdAt)}', style: ui(12.5, color: p.fg.withValues(alpha: 0.75), w: 600))),
                if (i.distanceKm != null) Text(km(i.distanceKm), style: ui(12.5, color: p.fg, w: 750)),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          // progress
          _Card(
            child: i.phase == 'issue'
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      RollingNumber(i.supportCount, style: ui(26, w: 750)),
                      Text(' / ${i.threshold}', style: ui(17, color: C.inkSoft, w: 600)),
                      const Spacer(),
                      Text('supporters', style: ui(13, color: C.inkSoft, w: 600)),
                    ]),
                    const SizedBox(height: 12),
                    HatchedProgress(value: i.supportCount / i.threshold, fill: p.bar, track: C.muted, hatch: const Color(0x55FFFFFF), height: 16),
                    const SizedBox(height: 10),
                    Text(
                      '${i.threshold - i.supportCount} more supporter${i.threshold - i.supportCount == 1 ? ' turns' : 's turn'} this into an event'
                      '${i.linkedCount > 0 ? '  ·  ${i.linkedCount} matching report${i.linkedCount == 1 ? '' : 's'} raise its severity' : ''}',
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
                  Expanded(child: _Vote(label: 'Not fixed', n: i.verification!.rejections, need: i.verification!.needed, color: C.ember)),
                ]),
              ]),
            ),
          ],
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
                          ? 'You are ${km(i.distanceKm)} away, inside the ${i.radiusKm % 1 == 0 ? i.radiusKm.toInt() : i.radiusKm} km range'
                          : 'You are ${km(i.distanceKm)} away. Supporting needs you within ${i.radiusKm % 1 == 0 ? i.radiusKm.toInt() : i.radiusKm} km',
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
        ],
      ),
      Positioned(left: 16, right: 16, bottom: pad.bottom + 14, child: _actions(i, me)),
    ]);
  }

  // ----- actions -----
  Widget _actions(Issue i, UserProfile? me) {
    final a = ref.read(actionsProvider);
    Widget bar(Widget child) => FrostedPanel(padding: const EdgeInsets.all(10), radius: 38, child: child);

    if (i.status == 'open') {
      if (i.supportedByMe) {
        return bar(Row(children: [
          const Expanded(child: PillButton(label: 'You support this', icon: Icons.check_rounded, color: C.lime, fg: C.ink, onPressed: null)),
          if (!i.reportedByMe) ...[
            const SizedBox(width: 8),
            PillButton(label: 'Withdraw', expand: false, color: C.muted, fg: C.ink, loading: _busy, onPressed: () => _run(() => a.withdraw(i.id), ok: 'Support withdrawn')),
          ],
        ]));
      }
      if (i.inRange == false) {
        return bar(PillButton(label: 'Too far · ${km(i.distanceKm)} away (max ${i.radiusKm % 1 == 0 ? i.radiusKm.toInt() : i.radiusKm} km)', icon: Icons.lock_outline_rounded, onPressed: null));
      }
      return bar(PillButton(
        label: 'Support this issue', icon: Icons.thumb_up_alt_rounded, color: C.ember, loading: _busy,
        onPressed: () => _run(() => a.support(i.id), ok: 'Thanks for backing your neighbours', headline: (r) => r.converted ? 'This is now an Event!' : 'Support added'),
      ));
    }

    if (i.status == 'event' || i.status == 'in_progress') {
      if (i.volunteeringByMe) {
        return bar(Row(children: [
          if (i.status == 'in_progress')
            Expanded(child: PillButton(label: 'Mark resolved', icon: Icons.done_all_rounded, color: C.ink, loading: _busy, onPressed: () => _resolve(i))),
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
            } on ApiException catch (e) {
              if (mounted) showToast(context, e.message, error: true);
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
          Expanded(child: PillButton(label: 'Not fixed', icon: Icons.close_rounded, color: C.muted, fg: C.ink, onPressed: _busy ? null : () => _run(() => a.verify(i.id, false), ok: 'Reported as not fixed'))),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: PillButton(label: 'Looks fixed', icon: Icons.check_rounded, color: C.ink, loading: _busy, onPressed: () => _run(() => a.verify(i.id, true), headline: (r) => r.outcome == 'closed' ? 'Verified and closed!' : 'Vote counted'))),
        ]));
      }
      return bar(const PillButton(label: 'Waiting for supporters to verify', icon: Icons.hourglass_top_rounded, onPressed: null));
    }
    return bar(const PillButton(label: 'Resolved and verified', icon: Icons.verified_rounded, color: C.mintDeep, fg: C.ink, onPressed: null));
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
            Text('What was done?', style: ui(20, w: 750)),
            const SizedBox(height: 6),
            Text('Neighbours who backed this issue will be asked to confirm.', style: ui(13.5, color: C.inkSoft)),
            const SizedBox(height: 14),
            TextField(
              controller: ctl, maxLines: 3, autofocus: true, style: ui(15),
              decoration: InputDecoration(
                hintText: 'e.g. Potholes filled and road levelled', filled: true, fillColor: C.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
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
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(R.card), boxShadow: softShadow),
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

class _TimelineRow extends StatelessWidget {
  final TimelineEntry entry;
  final bool last;
  const _TimelineRow({required this.entry, required this.last});
  @override
  Widget build(BuildContext context) {
    final color = const {
      'open': C.lime, 'event': C.lavender, 'in_progress': C.lavender, 'pending_verification': C.sky, 'closed': Color(0xFF6FBF8A),
    }[entry.status]!;
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
              Text(entry.note ?? statusLabel(entry.status), style: ui(13.5, w: 650, h: 1.35)),
              const SizedBox(height: 2),
              Text('${fmtDate(entry.createdAt)} · ${fmtTime(entry.createdAt)}', style: ui(12, color: C.inkSoft)),
            ]),
          ),
        ),
      ]),
    );
  }
}
