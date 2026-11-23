import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/domain/entities/query.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/widgets/celebrate.dart';
import 'package:by_the_people/presentation/widgets/map.dart';
import 'package:by_the_people/presentation/widgets/radar.dart' show metersBetween;
import 'package:by_the_people/presentation/widgets/media.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';
import 'package:by_the_people/presentation/features/detail/issue_detail_screen.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});
  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  final _page = PageController();
  int _step = 0;
  CategoryInfo? _cat;
  ({double lat, double lng})? _pin;
  final _title = TextEditingController(), _desc = TextEditingController();
  final _media = MediaAttachController(max: 4);
  List<Issue> _similar = [];
  bool _loadingSimilar = false, _busy = false;

  @override
  void dispose() {
    _page.dispose();
    _title.dispose();
    _desc.dispose();
    _media.dispose();
    super.dispose();
  }

  Future<void> _pick(LocState loc) async {
    final r = await showLocationPicker(
      context,
      initial: _pin == null ? LatLng(loc.lat!, loc.lng!) : LatLng(_pin!.lat, _pin!.lng),
      limitCenter: LatLng(loc.lat!, loc.lng!),
      radiusKm: _cat?.radiusKm,
      title: 'Where is the issue?',
    );
    if (r != null) setState(() => _pin = (lat: r.lat, lng: r.lng));
  }

  bool get _canNext {
    switch (_step) {
      case 0:
        return _cat != null;
      case 1:
        return _pin != null;
      case 2:
        return _title.text.trim().length >= 4;
      default:
        return true;
    }
  }

  Future<void> _go(int s) async {
    setState(() => _step = s);
    await _page.animateToPage(s, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    if (_step == 2) {
      setState(() => _loadingSimilar = true);
      try {
        _similar = await ref.read(actionsProvider).similar(GeoPoint(_pin!.lat, _pin!.lng), _cat!.key);
      } catch (_) {
        _similar = [];
      }
      if (mounted) setState(() => _loadingSimilar = false);
    }
    if (_step < 3) {
      await _go(_step + 1);
    } else {
      await _submit();
    }
  }

  Future<void> _submit({int? linkTo}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final a = ref.read(actionsProvider);
      final urls = _media.items.isEmpty ? <String>[] : await _media.upload(a.uploadMedia);
      final r = await a.report(ReportDraft(
            media: urls,
            title: _title.text.trim(),
            category: _cat!.key,
            description: _desc.text.trim(),
            location: GeoPoint(_pin!.lat, _pin!.lng),
            linkTo: linkTo,
          ));
      if (!mounted) return;
      celebrate(context,
          rewards: r.rewards,
          headline: r.linked ? 'Added to the existing issue' : 'Reported and routed to your representative',
          confetti: true);
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => IssueDetailScreen(id: r.issue!.id)));
    } on ApiException catch (e) {
      if (mounted) {
        showToast(context, e.message, error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(metaProvider);
    final loc = ref.watch(locationProvider);
    final pad = MediaQuery.of(context).padding;
    final titles = ['What is wrong?', 'Where exactly?', 'Tell us more', 'Review'];
    return Scaffold(
      body: PageBackdrop(
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, pad.top + 8, 16, 0),
            child: Row(children: [
              CircleBtn(icon: _step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded, onTap: () => _step == 0 ? Navigator.pop(context) : _go(_step - 1)),
              const SizedBox(width: 14),
              Expanded(
                child: Row(children: [
                  for (var s = 0; s < 4; s++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(color: s <= _step ? C.ink : C.line, borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: 14),
              Text('${_step + 1}/4', style: ui(13, color: C.inkSoft, w: 700)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
            child: Align(alignment: Alignment.centerLeft, child: Text(titles[_step], style: ui(20, w: 750))),
          ),
          Expanded(
            child: PageView(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // 1. category
                cats.when(
                  loading: () => const ChipRowSkeleton(),
                  error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(metaProvider)),
                  data: (list) => GridView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 112),
                    children: [
                      for (final c in list)
                        TapScale(
                          onTap: () => setState(() => _cat = c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _cat?.key == c.key ? C.ink : C.surface,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: softShadow,
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Icon(categoryIcons[c.key], size: 26, color: _cat?.key == c.key ? C.lime : C.ink),
                              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(c.label, style: ui(14.5, color: _cat?.key == c.key ? Colors.white : C.ink, w: 700, h: 1.2)),
                                Text('within ${c.radiusKm % 1 == 0 ? c.radiusKm.toInt() : c.radiusKm} km', style: ui(11.5, color: _cat?.key == c.key ? Colors.white70 : C.inkSoft)),
                              ]),
                            ]),
                          ),
                        ),
                    ],
                  ),
                ),
                // 2. where
                ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
                  Text(
                    'Drop the pin on the problem. You can only report within ${_cat == null ? '' : '${_cat!.radiusKm % 1 == 0 ? _cat!.radiusKm.toInt() : _cat!.radiusKm} km'} of where you stand.',
                    style: ui(14, color: C.inkSoft, h: 1.45),
                  ),
                  const SizedBox(height: 14),
                  if (!loc.has)
                    const EmptyState(title: 'Need your location', body: 'Allow location access so we can verify you are close to the issue.')
                  else if (_cat != null) ...[
                    if (_pin != null)
                      MapPreview(
                        lat: _pin!.lat, lng: _pin!.lng, height: 200, label: 'Issue location',
                        onTap: () => _pick(loc),
                      )
                    else
                      GestureDetector(
                        onTap: () => _pick(loc),
                        child: Container(
                          height: 140,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: C.muted, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.add_location_alt_outlined, size: 28, color: C.inkSoft),
                            const SizedBox(height: 6),
                            Text('Choose on map', style: ui(14, w: 600)),
                          ]),
                        ),
                      ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _pick(loc),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: Text(_pin == null ? 'Pick location' : 'Change location'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    Icon(_pin == null ? Icons.touch_app_rounded : Icons.place_rounded, size: 18, color: _pin == null ? C.inkSoft : C.ember),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_pin == null ? 'Drag the map to the problem' : 'Pin set ${_pinDistance(loc)} from you', style: ui(13.5, w: 600))),
                  ]),
                ]),
                // 3. details
                ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
                  _Input(controller: _title, hint: 'Short title, e.g. Deep pothole near the bus stop', onChanged: (_) => setState(() {}), maxLength: 80),
                  const SizedBox(height: 12),
                  _Input(controller: _desc, hint: 'What is happening and who does it affect? (optional)', lines: 5, maxLength: 400),
                  const SizedBox(height: 18),
                  Text('Photos or video', style: ui(14.5, w: 750)),
                  const SizedBox(height: 4),
                  Text('Evidence gets issues fixed faster. Up to 4 files.', style: ui(12.5, color: C.inkSoft)),
                  const SizedBox(height: 8),
                  MediaAttachStrip(controller: _media),
                ]),
                // 4. review
                ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
                  if (_loadingSimilar)
                    const LoadingOrb()
                  else if (_similar.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFFFFF0D8), borderRadius: BorderRadius.circular(24)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.content_copy_rounded, size: 18, color: C.ember),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Already reported nearby', style: ui(14.5, w: 750))),
                        ]),
                        const SizedBox(height: 4),
                        Text('Backing an existing issue makes it count for more.', style: ui(13, color: C.inkSoft)),
                        const SizedBox(height: 10),
                        for (final s in _similar.take(3))
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(s.title, style: ui(14, w: 700), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  Text('${km(s.distanceKm)} away · ${s.supportCount} supporters', style: ui(12, color: C.inkSoft)),
                                ]),
                              ),
                              const SizedBox(width: 8),
                              PillButton(label: 'Add mine', expand: false, color: C.ink, onPressed: _busy ? null : () => _submit(linkTo: s.id)),
                            ]),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(R.card), boxShadow: softShadow),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(categoryIcons[_cat?.key], size: 18, color: C.inkSoft),
                        const SizedBox(width: 8),
                        Text(_cat?.label ?? '', style: ui(13, color: C.inkSoft, w: 700)),
                      ]),
                      const SizedBox(height: 10),
                      Text(_title.text.trim(), style: ui(18, w: 700, h: 1.3)),
                      if (_desc.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(_desc.text.trim(), style: ui(14, color: C.inkSoft, h: 1.45)),
                      ],
                      if (_media.items.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(children: [
                          const Icon(Icons.perm_media_rounded, size: 16, color: C.inkSoft),
                          const SizedBox(width: 6),
                          Text('${_media.items.length} attachment${_media.items.length == 1 ? '' : 's'}', style: ui(13, color: C.inkSoft, w: 650)),
                        ]),
                      ],
                      const SizedBox(height: 14),
                      Text('It will be routed to the councillor whose ward covers this spot and tagged to the responsible authority. Reaching 5 supporters turns it into an event.', style: ui(12.5, color: C.inkSoft, h: 1.45)),
                    ]),
                  ),
                ]),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, pad.bottom + 16),
            child: PillButton(
              label: _step == 3 ? (_similar.isNotEmpty ? 'Report as new issue' : 'Submit report') : 'Continue',
              icon: _step == 3 ? Icons.campaign_rounded : null,
              color: _step == 3 ? C.ember : C.ink,
              loading: _busy || _loadingSimilar || _media.uploading,
              onPressed: _canNext ? _next : null,
            ),
          ),
        ]),
      ),
    );
  }

  String _pinDistance(LocState loc) {
    if (_pin == null || !loc.has) return '';
    final o = metersBetween(loc.lat!, loc.lng!, _pin!.lat, _pin!.lng);
    return km(math.sqrt(o.dx * o.dx + o.dy * o.dy) / 1000);
  }
}

class _Input extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int lines, maxLength;
  final ValueChanged<String>? onChanged;
  const _Input({required this.controller, required this.hint, this.lines = 1, this.onChanged, this.maxLength = 100});
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        minLines: lines,
        maxLines: lines + 1,
        maxLength: maxLength,
        onChanged: onChanged,
        textCapitalization: TextCapitalization.sentences,
        style: ui(16, w: 600),
        decoration: InputDecoration(
          hintText: hint, hintStyle: ui(15, color: C.inkSoft), filled: true, fillColor: C.surface, counterText: '',
          contentPadding: const EdgeInsets.all(20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
        ),
      );
}
