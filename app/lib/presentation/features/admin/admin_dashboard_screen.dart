import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/domain/entities/portal.dart';
import 'package:by_the_people/presentation/features/admin/charts.dart';
import 'package:by_the_people/presentation/features/admin/issue_row.dart';
import 'package:by_the_people/presentation/features/notifications/notifications_screen.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Admin tab 1: city-wide numbers, charts, top issues and pending foundation verifications.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(adminDashboardProvider);
    final user = ref.watch(authProvider).user;
    final unread = ref.watch(authProvider.select((s) => s.unread));
    final pad = MediaQuery.of(context).padding;
    return RefreshIndicator(
      color: C.ember,
      onRefresh: () async {
        ref.read(tickProvider.notifier).bump();
        await ref.read(adminDashboardProvider.future);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, pad.top + 12, 20, 140),
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Overview', style: ui(20, w: 650)),
                const SizedBox(height: 2),
                Text(user?.departmentName ?? 'SevaLink admin', style: ui(13.5, color: C.inkSoft, w: 650), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            CircleBtn(
              icon: Icons.notifications_none_rounded,
              size: 42,
              dot: unread > 0,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
            ),
          ]),
          const SizedBox(height: 18),
          dash.when(
            skipLoadingOnReload: true,
            loading: () => const IssueListSkeleton(),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(adminDashboardProvider)),
            data: (d) => _Body(d: d),
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final AdminDashboard d;
  const _Body({required this.d});

  void _queue(WidgetRef ref, String? status, {bool escalated = false}) {
    ref.read(queueFilterProvider.notifier).set(status, escalated: escalated);
    ref.read(shellTabProvider.notifier).go(1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = d.count('open') + d.count('acknowledged') + d.count('inProgress') + d.count('pendingVerification') + d.count('closed');
    final segs = [
      Segment('Open', d.count('open').toDouble(), C.ember),
      Segment('Acknowledged', d.count('acknowledged').toDouble(), C.sky),
      Segment('In progress', d.count('inProgress').toDouble(), C.lavender),
      Segment('Verifying', d.count('pendingVerification').toDouble(), C.amber),
      Segment('Closed', d.count('closed').toDouble(), const Color(0xFF6FBF8A)),
    ];
    final tiles = [
      ('Open', d.count('open'), C.amber, 'open', false),
      ('Acknowledged', d.count('acknowledged'), C.sky, 'acknowledged', false),
      ('In progress', d.count('inProgress'), C.lavender, 'in_progress', false),
      ('Verifying', d.count('pendingVerification'), C.mintDeep, 'pending_verification', false),
      ('Closed', d.count('closed'), C.lime, 'closed', false),
      ('Escalated', d.count('escalated'), C.ember, null, true),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (d.pendingFoundations > 0)
        TapScale(
          onTap: () => ref.read(shellTabProvider.notifier).go(2),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFFFE6D5), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: const BoxDecoration(color: C.ember, shape: BoxShape.circle),
                child: const Icon(Icons.verified_user_rounded, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${d.pendingFoundations} foundation${d.pendingFoundations == 1 ? '' : 's'} awaiting verification', style: ui(14.5, w: 750)),
                  Text('They cannot claim donations until verified.', style: ui(12.5, color: C.inkSoft)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: C.inkSoft),
            ]),
          ),
        ),
      // headline card
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: C.inkCard, borderRadius: BorderRadius.circular(R.card)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Avg. resolution time', style: ui(12.5, color: Colors.white70, w: 650)),
              const SizedBox(height: 6),
              Text(
                d.avgResolutionHours == null ? 'No data yet' : d.avgResolutionHours! >= 48 ? '${(d.avgResolutionHours! / 24).toStringAsFixed(1)} days' : '${d.avgResolutionHours!.toStringAsFixed(1)} hrs',
                style: display(30, color: Colors.white, w: 600),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _Pill('${d.count('open') + d.count('acknowledged') + d.count('inProgress')} active', Colors.white24),
                if (d.count('escalated') > 0) _Pill('${d.count('escalated')} escalated', C.ember),
              ]),
            ]),
          ),
          const SizedBox(width: 12),
          RingGauge(value: total == 0 ? 0 : d.count('closed') / total, label: total == 0 ? '0%' : '${(d.count('closed') / total * 100).round()}%'),
        ]),
      ),
      const SizedBox(height: 14),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 88,
        children: [
          for (final t in tiles)
            TapScale(
              onTap: () => _queue(ref, t.$4, escalated: t.$5),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
                decoration: BoxDecoration(color: t.$3, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  RollingNumber(t.$2, style: ui(26, w: 750, color: t.$3 == C.ember ? Colors.white : C.ink)),
                  Text(t.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(11.5, w: 700, color: t.$3 == C.ember ? Colors.white : C.ink.withValues(alpha: 0.75))),
                ]),
              ),
            ),
        ],
      ),
      const SizedBox(height: 22),
      const SectionTitle('Status mix'),
      _Panel(
        child: Row(children: [
          DonutChart(segments: segs, size: 128, centerTop: '$total', centerBottom: 'issues'),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final s in segs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(12.5, w: 600))),
                    Text('${s.value.round()}', style: ui(12.5, w: 750)),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
      if (d.byCategory.isNotEmpty) ...[
        const SizedBox(height: 18),
        const SectionTitle('By category'),
        _Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            HorizontalBars(rows: [for (final c in d.byCategory) BarRow(c.label.split(' & ').first, c.count, c.open)]),
            const SizedBox(height: 8),
            Row(children: [
              Container(width: 10, height: 10, decoration: const BoxDecoration(color: C.ember, shape: BoxShape.circle)),
              Text('  Open   ', style: ui(11.5, color: C.inkSoft, w: 600)),
              Container(width: 10, height: 10, decoration: const BoxDecoration(color: C.lime, shape: BoxShape.circle)),
              Text('  All reported', style: ui(11.5, color: C.inkSoft, w: 600)),
            ]),
          ]),
        ),
      ],
      if (d.topIssues.isNotEmpty) ...[
        const SizedBox(height: 18),
        SectionTitle('Top issues', action: 'Open queue', onAction: () => _queue(ref, null)),
        for (final i in d.topIssues) IssueRow(issue: i, adminActions: true),
      ],
      if (d.recent.isNotEmpty) ...[
        const SizedBox(height: 18),
        const SectionTitle('Recent activity'),
        _Panel(
          child: Column(children: [
            for (var k = 0; k < d.recent.take(6).length; k++) _RecentRow(e: d.recent[k], last: k == d.recent.take(6).length - 1),
          ]),
        ),
      ],
    ]);
  }
}

class _RecentRow extends StatelessWidget {
  final TimelineEntry e;
  final bool last;
  const _RecentRow({required this.e, required this.last});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 9, height: 9,
            decoration: BoxDecoration(color: e.kind == 'neta' ? C.emberLight : e.kind == 'authority' ? C.sky : C.lime, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.note ?? statusLabel(e.status), maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(13, w: 650, h: 1.3)),
              Text(relative(e.createdAt), style: ui(11.5, color: C.inkSoft)),
            ]),
          ),
        ]),
      );
}

class _Pill extends StatelessWidget {
  final String text;
  final Color bg;
  const _Pill(this.text, this.bg);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Text(text, style: ui(11.5, color: Colors.white, w: 700)),
      );
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(R.card), border: Border.all(color: C.line)),
        child: child,
      );
}
