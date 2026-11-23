import 'package:flutter/material.dart';
import 'package:by_the_people/presentation/features/reminders/reminder_sheet.dart';
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

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
String dayKey(DateTime d) => '${monthKey(d)}-${d.day.toString().padLeft(2, '0')}';

/// Weekly strip of seven day pills (dot under days with events) above the selected day's events.
class CalendarView extends ConsumerStatefulWidget {
  const CalendarView({super.key});
  @override
  ConsumerState<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends ConsumerState<CalendarView> {
  late DateTime _selected = DateUtils.dateOnly(DateTime.now());

  DateTime get _weekStart => DateTime(_selected.year, _selected.month, _selected.day - (_selected.weekday - 1));

  void _shiftWeek(int by) => setState(() => _selected = DateTime(_selected.year, _selected.month, _selected.day + 7 * by));

  @override
  Widget build(BuildContext context) {
    final ws = _weekStart;
    final week = [for (var i = 0; i < 7; i++) DateTime(ws.year, ws.month, ws.day + i)];
    final monthKeys = {monthKey(week.first), monthKey(week.last)};
    final asyncs = [for (final k in monthKeys) ref.watch(calendarProvider(k))];
    final days = <String, List<GatheringLite>>{};
    for (final a in asyncs) {
      final v = a.asData?.value;
      if (v != null) days.addAll(v);
    }
    final loading = asyncs.any((a) => a.isLoading);
    final failed = asyncs.any((a) => a.hasError);
    final today = DateUtils.dateOnly(DateTime.now());
    final selectedEvents = [...(days[dayKey(_selected)] ?? const <GatheringLite>[])]..sort((a, b) => a.startAt.compareTo(b.startAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlatCard(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: Column(
            children: [
              Row(
                children: [
                  TopBarAction(icon: Icons.chevron_left_rounded, onTap: () => _shiftWeek(-1)),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        '${_monthNames[ws.month - 1]} ${ws.year}',
                        key: ValueKey('${ws.year}-${ws.month}'),
                        textAlign: TextAlign.center,
                        style: ui(15, w: 600),
                      ),
                    ),
                  ),
                  TopBarAction(icon: Icons.chevron_right_rounded, onTap: () => _shiftWeek(1)),
                ],
              ),
              const SizedBox(height: 10),
              Row(children: [for (final d in week) Expanded(child: _dayPill(d, days, today))]),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(minHeight: 2, color: C.ink, backgroundColor: C.muted),
                ),
            ],
          ),
        ),
        if (failed)
          ErrorState(
            error: asyncs.firstWhere((a) => a.hasError).error!,
            onRetry: () {
              for (final k in monthKeys) {
                ref.invalidate(calendarProvider(k));
              }
            },
          ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: SectionTitle(
              DateUtils.isSameDay(_selected, today) ? 'Today' : '${_selected.day} ${_monthNames[_selected.month - 1]}',
            ),
          ),
          TapScale(
            onTap: () => showReminderSheet(context),
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('Set reminder', style: ui(13, color: C.ink, w: 600)),
            ),
          ),
        ]),
        if (loading && days.isEmpty)
          const RowListSkeleton(count: 2)
        else if (selectedEvents.isEmpty)
          FlatCard(
            padding: const EdgeInsets.all(R.cardInset),
            child: Text('Nothing planned for this day. Tap + to start something.', style: bodyStyle(color: C.inkSoft)),
          )
        else
          for (var i = 0; i < selectedEvents.length; i++) Enter(index: i, child: _EventRow(selectedEvents[i])),
      ],
    );
  }

  Widget _dayPill(DateTime d, Map<String, List<GatheringLite>> days, DateTime today) {
    final events = days[dayKey(d)] ?? const <GatheringLite>[];
    final selected = DateUtils.isSameDay(d, _selected);
    final isToday = DateUtils.isSameDay(d, today);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        key: ValueKey('day-${d.day}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = d),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 82,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? C.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _weekdayShort[d.weekday - 1],
                style: metaStyle(color: selected ? Colors.white70 : C.inkSoft),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? Colors.white : Colors.transparent,
                  border: !selected && isToday ? Border.all(color: C.ink, width: 1.2) : null,
                ),
                child: Text('${d.day}', style: numStyle(15, color: C.ink, w: 650)),
              ),
              const SizedBox(height: 5),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(shape: BoxShape.circle, color: events.isEmpty ? Colors.transparent : C.danger),
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
      child: FlatCard(
        margin: const EdgeInsets.only(bottom: R.unit),
        padding: const EdgeInsets.all(R.cardInset),
        child: Row(
          children: [
            IconChip(s.icon, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: titleStyle()),
                  const SizedBox(height: 2),
                  Text('${s.label} · ${fmtTime(e.startAt)}', style: metaStyle()),
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
