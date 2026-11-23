import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/domain/entities/gathering.dart';
import 'package:by_the_people/domain/entities/query.dart' show GeoPoint;
import 'package:by_the_people/presentation/widgets/map.dart' show PickedLocation;
import 'package:by_the_people/presentation/features/gatherings/gathering_widgets.dart';
import 'package:by_the_people/presentation/features/gatherings/welfare_common.dart';
import 'package:by_the_people/presentation/providers/gathering_providers.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Opens the sheet for starting a gathering or proposing a campaign.
Future<void> showCreateGatheringSheet(BuildContext context) =>
    showWelfareSheet<void>(context, builder: (_) => const CreateGatheringSheet());

class CreateGatheringSheet extends ConsumerStatefulWidget {
  const CreateGatheringSheet({super.key});
  @override
  ConsumerState<CreateGatheringSheet> createState() => _CreateGatheringSheetState();
}

class _CreateGatheringSheetState extends ConsumerState<CreateGatheringSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _address = TextEditingController();
  final _capacity = TextEditingController();
  String _type = 'cleanup';
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay? _end;
  bool _proposed = false;
  bool _busy = false;
  int? _clubId;
  List<String> _media = [];
  PickedLocation? _picked;

  @override
  void initState() {
    super.initState();
    // Ask for the position early so the venue pin is ready by the time the form is filled.
    Future.microtask(() {
      if (mounted && !ref.read(locationProvider).has) ref.read(locationProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _address.dispose();
    _capacity.dispose();
    super.dispose();
  }

  DateTime get _startAt => DateTime(_date.year, _date.month, _date.day, _start.hour, _start.minute);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickStart() async {
    final t = await showTimePicker(context: context, initialTime: _start);
    if (t != null) setState(() => _start = t);
  }

  Future<void> _pickEnd() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _end ?? TimeOfDay(hour: (_start.hour + 2) % 24, minute: _start.minute),
    );
    if (t != null) setState(() => _end = t);
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.length < 4) return showToast(context, 'Add a title of at least 4 characters.', error: true);
    if (_address.text.trim().isEmpty) return showToast(context, 'Tell people where to meet.', error: true);
    final start = _startAt;
    if (!start.isAfter(DateTime.now())) return showToast(context, 'Pick a start time in the future.', error: true);
    int? endMs;
    if (_end != null) {
      var end = DateTime(_date.year, _date.month, _date.day, _end!.hour, _end!.minute);
      if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
      endMs = end.millisecondsSinceEpoch;
    }
    final cap = int.tryParse(_capacity.text.trim());
    setState(() => _busy = true);
    final r = await guarded(context, () async {
      final at = _picked != null ? GeoPoint(_picked!.lat, _picked!.lng) : await ref.read(gatheringActionsProvider).here();
      return ref
          .read(gatheringActionsProvider)
          .create(
            GatheringDraft(
              title: title,
              description: _desc.text.trim(),
              type: _type,
              address: _address.text.trim(),
              lat: at.lat,
              lng: at.lng,
              startAt: start.millisecondsSinceEpoch,
              endAt: endMs,
              capacity: cap != null && cap > 0 ? cap : null,
              clubId: _clubId,
              media: _media,
              proposed: _proposed,
            ),
          );
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      Navigator.of(context).pop();
      cheer(context, r.rewards, _proposed ? 'Campaign proposed. Rally votes to take it live.' : 'Gathering created', confetti: !_proposed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clubs = ref.watch(clubsProvider).asData?.value.where((c) => c.joinedByMe).toList() ?? const [];
    return SheetBody(
      title: _proposed ? 'Propose a campaign' : 'New gathering',
      subtitle: _proposed
          ? 'Neighbours vote on it. Once it reaches the goal it goes live automatically.'
          : 'Bring people together for something good.',
      children: [
        Text('What kind?', style: ui(12.5, color: C.inkSoft, w: 600)),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final e in gatheringTypes.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AppChip(
                    label: e.value.label,
                    icon: e.value.icon,
                    selected: _type == e.key,
                    onTap: () => setState(() => _type = e.key),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        WField(label: 'Title', controller: _title, hint: 'e.g. Lakeside clean-up morning', maxLength: 90, fieldKey: const Key('g-title')),
        const SizedBox(height: 14),
        WField(label: 'Details', controller: _desc, lines: 3, hint: 'What to bring, what we will do', maxLength: 600),
        const SizedBox(height: 14),
        Text('When', style: ui(12.5, color: C.inkSoft, w: 600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 5,
              child: _PickTile(icon: Icons.calendar_today_rounded, label: fmtDateLong(_date.millisecondsSinceEpoch), onTap: _pickDate),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: _PickTile(icon: Icons.schedule_rounded, label: _start.format(context), onTap: _pickStart),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _PickTile(
          icon: Icons.timelapse_rounded,
          label: _end == null ? 'Add an end time (optional)' : 'Ends ${_end!.format(context)}',
          onTap: _pickEnd,
          onClear: _end == null ? null : () => setState(() => _end = null),
        ),
        const SizedBox(height: 14),
        WField(label: 'Meeting point', controller: _address, hint: 'Landmark or address', maxLength: 140, fieldKey: const Key('g-address')),
        const SizedBox(height: 8),
        LocationField(value: _picked, onChanged: (v) => setState(() => _picked = v), address: _address, title: 'Where is the venue?'),
        const SizedBox(height: 14),
        WField(
          label: 'Capacity (optional)',
          controller: _capacity,
          hint: 'Leave empty for no limit',
          keyboard: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
          fieldKey: const Key('g-capacity'),
        ),
        if (clubs.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Hosted by a club (optional)', style: ui(12.5, color: C.inkSoft, w: 600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in clubs)
                AppChip(label: c.name, selected: _clubId == c.id, onTap: () => setState(() => _clubId = _clubId == c.id ? null : c.id)),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Text('Photo', style: ui(12.5, color: C.inkSoft, w: 600)),
        const SizedBox(height: 8),
        PhotoPicker(urls: _media, onChanged: (v) => setState(() => _media = v), max: 3),
        const SizedBox(height: 16),
        WCard(
          color: C.surface,
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Propose as campaign', style: ui(14, w: 600)),
                    const SizedBox(height: 2),
                    Text('Let the community vote before it goes live.', style: ui(12, color: C.inkSoft, h: 1.3)),
                  ],
                ),
              ),
              Switch(
                key: const Key('g-propose'),
                value: _proposed,
                activeTrackColor: C.ink,
                onChanged: (v) => setState(() => _proposed = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        PillButton(
          label: _proposed ? 'Propose campaign' : 'Create gathering',
          icon: Icons.check_rounded,
          loading: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _PickTile extends StatelessWidget {
  const _PickTile({required this.icon, required this.label, required this.onTap, this.onClear});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: C.muted, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, size: 18, color: C.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(14)),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close_rounded, size: 18, color: C.inkSoft),
              ),
          ],
        ),
      ),
    );
  }
}
