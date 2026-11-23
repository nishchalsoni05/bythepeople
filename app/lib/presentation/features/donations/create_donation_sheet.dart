import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/domain/entities/donation.dart';
import 'package:by_the_people/presentation/features/donations/donation_widgets.dart';
import 'package:by_the_people/presentation/features/gatherings/welfare_common.dart';
import 'package:by_the_people/presentation/providers/donation_providers.dart';
import 'package:by_the_people/presentation/providers/gathering_providers.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart';
import 'package:by_the_people/domain/entities/query.dart' show GeoPoint;
import 'package:by_the_people/presentation/widgets/map.dart' show PickedLocation;
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Opens the sheet for listing surplus food, clothes and more.
Future<void> showCreateDonationSheet(BuildContext context) => showWelfareSheet<void>(context, builder: (_) => const CreateDonationSheet());

class CreateDonationSheet extends ConsumerStatefulWidget {
  const CreateDonationSheet({super.key});
  @override
  ConsumerState<CreateDonationSheet> createState() => _CreateDonationSheetState();
}

class _CreateDonationSheetState extends ConsumerState<CreateDonationSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _qty = TextEditingController();
  final _servings = TextEditingController();
  final _address = TextEditingController();
  PickedLocation? _picked;
  final _pickup = TextEditingController();

  String _kind = 'food';
  String _veg = 'veg';
  bool _hygiene = false;
  bool _busy = false;
  int _shelfHours = 4;
  int _agoMinutes = 0; // how long ago the food was prepared
  DateTime? _customPrepared;
  List<String> _media = [];

  bool get _food => _kind == 'food';

  DateTime get _prepared => _customPrepared ?? DateTime.now().subtract(Duration(minutes: _agoMinutes));

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted && !ref.read(locationProvider).has) ref.read(locationProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    for (final c in [_title, _desc, _qty, _servings, _address, _pickup]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPreparedTime() async {
    final now = DateTime.now();
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_prepared));
    if (t == null) return;
    final picked = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    if (picked.isAfter(now)) {
      if (mounted) showToast(context, 'Prepared time cannot be in the future.', error: true);
      return;
    }
    setState(() {
      _customPrepared = picked;
      _agoMinutes = -1;
    });
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.length < 3) return showToast(context, 'Add a short title.', error: true);
    if (_address.text.trim().isEmpty) return showToast(context, 'Add the pickup address.', error: true);
    int? servings;
    int? preparedAt;
    if (_food) {
      servings = int.tryParse(_servings.text.trim());
      if (servings == null || servings <= 0) return showToast(context, 'How many servings? Foundations plan around this.', error: true);
      final age = DateTime.now().difference(_prepared);
      if (age > const Duration(hours: 3)) return showToast(context, 'Food prepared more than 3 hours ago cannot be listed.', error: true);
      if (!_hygiene) return showToast(context, 'Please confirm the food was prepared hygienically.', error: true);
      preparedAt = _prepared.millisecondsSinceEpoch;
    }
    setState(() => _busy = true);
    final r = await guarded(context, () async {
      final at = _picked != null ? GeoPoint(_picked!.lat, _picked!.lng) : await ref.read(gatheringActionsProvider).here();
      return ref
          .read(donationActionsProvider)
          .create(
            DonationDraft(
              kind: _kind,
              title: title,
              description: _desc.text.trim(),
              quantity: _qty.text.trim(),
              servings: servings,
              veg: _food ? _veg : null,
              preparedAt: preparedAt,
              shelfHours: _food ? _shelfHours : null,
              lat: at.lat,
              lng: at.lng,
              address: _address.text.trim(),
              pickupNote: _pickup.text.trim(),
              media: _media,
              hygieneAck: _food ? _hygiene : false,
            ),
          );
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      Navigator.of(context).pop();
      cheer(context, r.rewards, 'Listed. Nearby foundations are being alerted.', confetti: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expiry = _food ? _prepared.add(Duration(hours: _shelfHours)) : DateTime.now().add(const Duration(days: 7));
    return SheetBody(
      title: 'List a donation',
      subtitle: 'Surplus food, clothes and more reach people who need them, through verified foundations.',
      children: [
        Text('What are you giving?', style: ui(12.5, color: C.inkSoft, w: 600)),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final e in donationKinds.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AppChip(
                    label: e.value.label,
                    icon: e.value.icon,
                    selected: _kind == e.key,
                    onTap: () => setState(() => _kind = e.key),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        WField(
          label: 'Title',
          controller: _title,
          hint: _food ? 'e.g. Wedding dinner leftovers' : 'e.g. 20 winter jackets',
          maxLength: 80,
          fieldKey: const Key('d-title'),
        ),
        const SizedBox(height: 14),
        WField(
          label: 'Quantity',
          controller: _qty,
          hint: _food ? 'e.g. 3 large trays' : 'e.g. 2 bags',
          maxLength: 60,
          fieldKey: const Key('d-qty'),
        ),
        if (_food) ...[
          const SizedBox(height: 14),
          WField(
            label: 'Servings',
            controller: _servings,
            hint: 'About how many people can it feed?',
            keyboard: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
            fieldKey: const Key('d-servings'),
          ),
          const SizedBox(height: 16),
          Text('Food type', style: ui(12.5, color: C.inkSoft, w: 600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in const [('veg', 'Veg'), ('nonveg', 'Non-veg'), ('mixed', 'Mixed')])
                AppChip(label: v.$2, selected: _veg == v.$1, onTap: () => setState(() => _veg = v.$1)),
            ],
          ),
          const SizedBox(height: 16),
          Text('When was it prepared?', style: ui(12.5, color: C.inkSoft, w: 600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in const [(0, 'Just now'), (30, '30 min ago'), (60, '1 hour ago'), (120, '2 hours ago')])
                AppChip(
                  label: m.$2,
                  selected: _agoMinutes == m.$1 && _customPrepared == null,
                  onTap: () => setState(() {
                    _customPrepared = null;
                    _agoMinutes = m.$1;
                  }),
                ),
              AppChip(
                label: _customPrepared == null ? 'Pick time' : fmtTime(_customPrepared!.millisecondsSinceEpoch),
                icon: Icons.schedule_rounded,
                selected: _customPrepared != null,
                onTap: _pickPreparedTime,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Safe to eat for', style: ui(12.5, color: C.inkSoft, w: 600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in const [2, 3, 4])
                AppChip(label: '$h hours', selected: _shelfHours == h, onTap: () => setState(() => _shelfHours = h)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            key: const Key('expiry-preview'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: C.amber.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(18)),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 19),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Auto-expires at ${fmtTime(expiry.millisecondsSinceEpoch)}. Food is capped at 4 hours after preparation.',
                    style: ui(13, w: 600, h: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            key: const Key('d-hygiene'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _hygiene = !_hygiene),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: _hygiene ? C.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _hygiene ? C.ink : C.inkSoft, width: 1.6),
                  ),
                  child: _hygiene ? const Icon(Icons.check_rounded, size: 18, color: Colors.white) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('I confirm this food was prepared hygienically and is safe to eat.', style: ui(13.5, w: 600, h: 1.35)),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          Text('Listed for 7 days (until ${fmtDate(expiry.millisecondsSinceEpoch)}).', style: ui(12.5, color: C.inkSoft)),
        ],
        const SizedBox(height: 14),
        WField(label: 'Details (optional)', controller: _desc, lines: 2, hint: 'Condition, sizes, anything to know', maxLength: 400),
        const SizedBox(height: 14),
        WField(
          label: 'Pickup address',
          controller: _address,
          hint: 'Where should they come?',
          maxLength: 140,
          fieldKey: const Key('d-address'),
        ),
        const SizedBox(height: 8),
        LocationField(value: _picked, onChanged: (v) => setState(() => _picked = v), address: _address, title: 'Where is the pickup?'),
        const SizedBox(height: 14),
        WField(label: 'Pickup note (optional)', controller: _pickup, hint: 'Gate, floor, who to ask for', maxLength: 140),
        const SizedBox(height: 16),
        Text('Photo', style: ui(12.5, color: C.inkSoft, w: 600)),
        const SizedBox(height: 8),
        PhotoPicker(urls: _media, onChanged: (v) => setState(() => _media = v), max: 3),
        const SizedBox(height: 22),
        PillButton(label: 'List donation', icon: Icons.volunteer_activism_rounded, loading: _busy, onPressed: _submit),
      ],
    );
  }
}
