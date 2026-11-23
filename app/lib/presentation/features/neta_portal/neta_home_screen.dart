import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/domain/entities/portal.dart';
import 'package:by_the_people/presentation/features/admin/charts.dart';
import 'package:by_the_people/presentation/features/admin/issue_row.dart';
import 'package:by_the_people/presentation/features/gatherings/gathering_detail_screen.dart';
import 'package:by_the_people/presentation/features/notifications/notifications_screen.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Neta tab 1: dashboard on top, then the locality issue feed with respond / escalate actions.
class NetaHomeScreen extends ConsumerStatefulWidget {
  const NetaHomeScreen({super.key});
  @override
  ConsumerState<NetaHomeScreen> createState() => _NetaHomeScreenState();
}

class _NetaHomeScreenState extends ConsumerState<NetaHomeScreen> {
  int _status = 0;
  String _sort = 'top';
  static const _statuses = <(String?, String)>[(null, 'All'), ('open', 'Open'), ('in_progress', 'In progress'), ('closed', 'Resolved')];

  @override
  Widget build(BuildContext context) {
    final dash = ref.watch(netaDashboardProvider);
    final feed = ref.watch(netaFeedProvider((_statuses[_status].$1, _sort)));
    final unread = ref.watch(authProvider.select((s) => s.unread));
    final pad = MediaQuery.of(context).padding;
    return RefreshIndicator(
      color: C.ember,
      onRefresh: () async {
        ref.read(tickProvider.notifier).bump();
        await ref.read(netaFeedProvider((_statuses[_status].$1, _sort)).future);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, pad.top + 12, 20, 140),
        children: [
          Row(children: [
            Expanded(child: Text('Your locality', style: ui(20, w: 650))),
            CircleBtn(
              icon: Icons.notifications_none_rounded,
              size: 42,
              dot: unread > 0,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
            ),
          ]),
          const SizedBox(height: 16),
          dash.when(
            skipLoadingOnReload: true,
            loading: () => const SkeletonBlock(height: 200),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(netaDashboardProvider)),
            data: (d) => _Dashboard(d: d),
          ),
          const SizedBox(height: 22),
          const SectionTitle('Locality feed'),
          SegmentedToggle(labels: [for (final s in _statuses) s.$2], index: _status, onChanged: (i) => setState(() => _status = i)),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final s in const [('top', 'Top', Icons.local_fire_department_rounded), ('new', 'New', Icons.schedule_rounded)])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AppChip(label: s.$2, icon: s.$3, selected: _sort == s.$1, onTap: () => setState(() => _sort = s.$1)),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          feed.when(
            skipLoadingOnReload: true,
            loading: () => const IssueListSkeleton(),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(netaFeedProvider)),
            data: (items) => items.isEmpty
                ? const EmptyState(title: 'Nothing here yet', body: 'Issues reported in your jurisdiction appear here.')
                : Column(children: [for (final i in items) IssueRow(key: ValueKey(i.id), issue: i, netaActions: true)]),
          ),
        ],
      ),
    );
  }
}

class SkeletonBlock extends StatelessWidget {
  final double height;
  const SkeletonBlock({super.key, required this.height});
  @override
  Widget build(BuildContext context) => Skeleton(child: SkeletonBox(height: height, radius: R.card));
}

class _Dashboard extends ConsumerWidget {
  final NetaDashboard d;
  const _Dashboard({required this.d});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = d.politician;
    final rate = d.resolutionRate ?? (d.count('open') + d.count('inProgress') + d.count('resolved') == 0 ? 0.0 : d.count('resolved') / (d.count('open') + d.count('inProgress') + d.count('resolved')));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(R.card),
          color: C.ink,
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.levelLabel.toUpperCase(), style: ui(11, color: Colors.white70, w: 750, ls: 1)),
              const SizedBox(height: 4),
              Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: display(24, color: Colors.white, w: 600)),
              const SizedBox(height: 4),
              Text([p.constituency, p.party].where((e) => e.isNotEmpty).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(12.5, color: Colors.white70, w: 600)),
            ]),
          ),
          const SizedBox(width: 12),
          RingGauge(value: rate, label: '${(rate * 100).round()}%', color: Colors.white),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        _Kpi('Open', d.count('open'), C.amber),
        const SizedBox(width: 8),
        _Kpi('In progress', d.count('inProgress'), C.lavender),
        const SizedBox(width: 8),
        _Kpi('Resolved', d.count('resolved'), C.lime),
        const SizedBox(width: 8),
        _Kpi('Escalated', d.count('escalated'), C.ember, light: true),
      ]),
      if (d.topIssues.isNotEmpty) ...[
        const SizedBox(height: 22),
        const SectionTitle('Trending in your area'),
        for (final i in d.topIssues.take(3)) IssueRow(issue: i, netaActions: true),
      ],
      if (d.upcomingGatherings.isNotEmpty) ...[
        const SizedBox(height: 14),
        const SectionTitle('Upcoming gatherings'),
        SizedBox(
          height: 112,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final g in d.upcomingGatherings)
              TapScale(
                onTap: () => openGathering(context, g.id),
                child: Container(
                  width: 220,
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: C.lavender, borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(g.typeLabel, style: ui(11.5, w: 700, color: C.ink.withValues(alpha: 0.7))),
                    const SizedBox(height: 4),
                    Text(g.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(15, w: 700, h: 1.2)),
                    const Spacer(),
                    Text('${whenLabel(g.startAt)} · ${g.goingCount} going', maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(12, w: 650)),
                  ]),
                ),
              ),
          ]),
        ),
      ],
    ]);
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final int v;
  final Color bg;
  final bool light;
  const _Kpi(this.label, this.v, this.bg, {this.light = false});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 12, 6, 10),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RollingNumber(v, style: ui(24, w: 750, color: light ? Colors.white : C.ink)),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(10.5, w: 700, color: light ? Colors.white : C.ink.withValues(alpha: 0.75))),
          ]),
        ),
      );
}
