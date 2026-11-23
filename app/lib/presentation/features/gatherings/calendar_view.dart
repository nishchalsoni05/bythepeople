import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/domain/entities/gathering.dart';
import 'package:by_the_people/presentation/features/gatherings/gathering_detail_screen.dart';
import 'package:by_the_people/presentation/features/gatherings/gathering_widgets.dart';
import 'package:by_the_people/presentation/features/gatherings/welfare_common.dart';
import 'package:by_the_people/presentation/providers/gathering_providers.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
String dayKey(DateTime d) => '${monthKey(d)}-${d.day.toString().padLeft(2, '0')}';

/// Month grid with a dot per event type; tapping a day lists its gatherings.
class CalendarView extends ConsumerStatefulWidget {
  const CalendarView({super.key});
  @override
  ConsumerState<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends ConsumerState<CalendarView> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = DateTime.now();

  void _shift(int by) => setState(() {
    _month = DateTime(_month.year, _month.month + by);
    _selected = DateTime(_month.year, _month.month, 1);
  });

  @override
  Widget build(BuildContext context) {
    final key = monthKey(_month);
    final async = ref.watch(calendarProvider(key));
    final days = async.asData?.value ?? const <String, List<GatheringLite>>{};
    final first = DateTime(_month.year, _month.month, 1);
    final lead = first.weekday - 1; // Monday first
    final count = DateUtils.getDaysInMonth(_month.year, _month.month);
    final rows = ((lead + count) / 7).ceil();
    final today = DateTime.now();
    final selectedEvents = [...(days[dayKey(_selected)] ?? const <GatheringLite>[])]..sort((a, b) => a.startAt.compareTo(b.startAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WCard(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
          child: Column(
            children: [
              Row(
                children: [
                  TopBarAction(icon: Icons.chevron_left_rounded, onTap: () => _shift(-1)),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        '${_monthNames[_month.month - 1]} ${_month.year}',
                        key: ValueKey(key),
                        textAlign: TextAlign.center,
                        style: ui(17, w: 600),
                      ),
                    ),
                  ),
                  TopBarAction(icon: Icons.chevron_right_rounded, onTap: () => _shift(1)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final l in dayLetters)
                    Expanded(
                      child: Center(
                        child: Text(l, style: ui(11.5, color: C.inkSoft, w: 600)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (var r = 0; r < rows; r++) Row(children: [for (var c = 0; c < 7; c++) _cell(r * 7 + c - lead + 1, count, days, today)]),
              if (async.isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2, color: C.ink, backgroundColor: C.muted),
                ),
            ],
          ),
        ),
        if (async.hasError) ErrorState(error: async.error!, onRetry: () => ref.invalidate(calendarProvider(key))),
        const SizedBox(height: 18),
        SectionTitle(
          _selected.day == today.day && _selected.month == today.month && _selected.year == today.year
              ? 'Today'
              : '${_selected.day} ${_monthNames[_selected.month - 1]}',
        ),
        if (async.isLoading && days.isEmpty)
          const RowListSkeleton(count: 2)
        else if (selectedEvents.isEmpty)
          WCard(
            child: Text('Nothing planned for this day. Tap + to start something.', style: ui(14, color: C.inkSoft, h: 1.4)),
          )
        else
          for (var i = 0; i < selectedEvents.length; i++) Enter(index: i, child: _EventRow(selectedEvents[i])),
      ],
    );
  }

  Widget _cell(int day, int count, Map<String, List<GatheringLite>> days, DateTime today) {
    if (day < 1 || day > count) return const Expanded(child: SizedBox(height: 46));
    final d = DateTime(_month.year, _month.month, day);
    final events = days[dayKey(d)] ?? const <GatheringLite>[];
    final selected = DateUtils.isSameDay(d, _selected);
    final isToday = DateUtils.isSameDay(d, today);
    final types = events.map((e) => e.type).toSet().take(3).toList();
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = d),
        child: Container(
          key: ValueKey('day-$day'),
          height: 46,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: selected ? C.ink : (isToday ? C.lime.withValues(alpha: 0.5) : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: ui(14, color: selected ? Colors.white : C.ink, w: selected || isToday ? 600 : 500),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final t in types)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(color: selected ? C.lime : styleOf(t).b, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.e);
  final GatheringLite e;
  @override
  Widget build(BuildContext context) {
    final s = styleOf(e.type);
    return TapScale(
      onTap: () => openGathering(context, e.id),
      child: WCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: C.muted, borderRadius: BorderRadius.circular(12)),
              child: Icon(s.icon, size: 20, color: C.inkSoft),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(14, w: 600, h: 1.25)),
                  const SizedBox(height: 2),
                  Text('${s.label} · ${fmtTime(e.startAt)}', style: ui(12.5, color: C.inkSoft)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: C.inkSoft),
          ],
        ),
      ),
    );
  }
}
