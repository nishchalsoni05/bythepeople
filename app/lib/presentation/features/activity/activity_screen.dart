import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/widgets/cards.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';
import 'package:by_the_people/presentation/features/detail/issue_detail_screen.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});
  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  int _tab = 2; // default to events
  DateTime? _day;
  static const _types = ['reports', 'supported', 'events'];

  @override
  Widget build(BuildContext context) {
    final type = _types[_tab];
    final async = ref.watch(activityProvider(type));
    final pad = MediaQuery.of(context).padding;
    return RefreshIndicator(
      color: C.ember,
      onRefresh: () async {
        ref.read(tickProvider.notifier).bump();
        await ref.read(activityProvider(type).future);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, pad.top + 12, 20, 140),
        children: [
          Text('My activity', style: ui(20, w: 650)),
          const SizedBox(height: 14),
          SegmentedToggle(labels: const ['My needs', 'Backed', 'My events'], index: _tab, onChanged: (i) => setState(() {
                _tab = i;
                _day = null;
              })),
          const SizedBox(height: 16),
          async.when(
            loading: () => const IssueListSkeleton(),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(activityProvider)),
            data: (items) {
              if (_tab != 2) {
                if (items.isEmpty) {
                  return EmptyState(
                    title: _tab == 0 ? 'No needs posted yet' : 'Nothing backed yet',
                    body: _tab == 0 ? 'Tap the + button to post a need for your foundation.' : 'Back needs from foundations near you in the Home tab.',
                  );
                }
                return Column(children: [
                  for (final i in items)
                    IssueCard(issue: i, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => IssueDetailScreen(id: i.id)))),
                ]);
              }
              return _events(items);
            },
          ),
        ],
      ),
    );
  }

  Widget _events(List<Issue> items) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final days = List.generate(14, (n) => start.add(Duration(days: n)));
    bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    final scheduled = items.where((e) => e.scheduledAt != null && !e.isClosed).toList();
    final shown = _day == null ? items : items.where((e) => e.scheduledAt != null && same(dt(e.scheduledAt!), _day!)).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // calendar strip with event dots
      SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: days.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, n) {
            final d = days[n];
            final sel = _day != null && same(_day!, d);
            final has = scheduled.any((e) => same(dt(e.scheduledAt!), d));
            return TapScale(
              onTap: () => setState(() => _day = sel ? null : d),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                width: 54,
                decoration: BoxDecoration(
                  color: sel ? C.ink : C.surface, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: C.line),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(dayLetters[d.weekday - 1], style: ui(12, color: sel ? Colors.white70 : C.inkSoft, w: 700)),
                  const SizedBox(height: 6),
                  Text('${d.day}', style: ui(19, color: sel ? Colors.white : C.ink, w: 750)),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    width: 7, height: 7,
                    decoration: BoxDecoration(color: has ? (sel ? C.lime : C.ember) : Colors.transparent, shape: BoxShape.circle),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 18),
      if (shown.isEmpty)
        EmptyState(
          title: _day == null ? 'No events joined' : 'Nothing that day',
          body: _day == null ? 'Join events as a volunteer from the Feed. They will appear here with their dates.' : 'Pick another day or clear the filter.',
        )
      else
        for (final e in shown) _EventRow(e: e),
    ]);
  }
}

/// Date rail + coloured bar entry (calendar reference).
class _EventRow extends StatelessWidget {
  final Issue e;
  const _EventRow({required this.e});
  @override
  Widget build(BuildContext context) {
    final p = paletteFor(e);
    final at = e.scheduledAt;
    return TapScale(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => IssueDetailScreen(id: e.id))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 72,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(color: e.isClosed ? C.mint : C.ink, borderRadius: BorderRadius.circular(14)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(at == null ? '—' : fmtDate(at).split(' ')[1], style: ui(12, color: e.isClosed ? C.inkSoft : Colors.white70, w: 700)),
                Text(at == null ? '' : fmtDate(at).split(' ')[0], style: display(30, color: e.isClosed ? C.ink : Colors.white, w: 650)),
                if (at != null) Text(fmtTime(at), style: ui(10.5, color: e.isClosed ? C.inkSoft : Colors.white60, w: 600)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
                child: Row(children: [
                  Container(width: 5, margin: const EdgeInsets.only(right: 12), decoration: BoxDecoration(color: p.bar, borderRadius: BorderRadius.circular(4))),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(statusLabel(e.status), style: ui(12, color: p.bar == C.lime ? C.inkSoft : p.bar, w: 750)),
                      const SizedBox(height: 2),
                      Text(e.title, style: ui(15, w: 700, h: 1.25), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      AvatarStack(people: e.volunteers, total: e.volunteerCount, size: 24, max: 4),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
