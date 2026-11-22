import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../state.dart';
import '../tokens.dart';
import 'ui.dart';

const _kinds = ['city', 'state', 'region'];
const _kindLabels = ['City', 'State', 'Region'];

/// Chooses how wide the app looks: my city, my state or my region, or any other
/// area of that kind (tap the place name).
class ScopeBar extends ConsumerWidget {
  final bool dark;
  const ScopeBar({super.key, this.dark = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sc = ref.watch(scopeProvider);
    final label = ref.watch(scopeLabelProvider);
    final fg = dark ? Colors.white : C.ink;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedToggle(
        dark: dark,
        labels: _kindLabels,
        index: _kinds.indexOf(sc.kind),
        onChanged: (i) => ref.read(scopeProvider.notifier).setKind(_kinds[i]),
      ),
      const SizedBox(height: 8),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _pick(context, ref, sc.kind),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.place_rounded, size: 15, color: dark ? Colors.white70 : C.ember),
            const SizedBox(width: 5),
            Text('Showing ', style: ui(13, color: dark ? Colors.white70 : C.inkSoft, w: 600)),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(13, color: fg, w: 750))),
            if (sc.areaId != null) Text('  (not your ${sc.kind})', style: ui(12, color: dark ? Colors.white60 : C.inkSoft)),
            Icon(Icons.expand_more_rounded, size: 18, color: fg),
          ]),
        ),
      ),
    ]);
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, String kind) async {
    HapticFeedback.selectionClick();
    final areas = ref.read(areasProvider).asData?.value ?? const <Area>[];
    final options = areas.where((a) => a.kind == kind).toList();
    final byId = {for (final a in areas) a.id: a};
    final mine = ref.read(hereProvider).asData?.value?[kind]?['name'];
    final current = ref.read(scopeProvider);
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: const BoxDecoration(color: C.canvas, borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 16),
          Text('Choose a ${kind}', style: ui(18, w: 750)),
          const SizedBox(height: 12),
          _Option(
            title: mine == null ? 'My $kind' : 'My $kind · $mine',
            sub: 'Follows your location',
            selected: current.areaId == null,
            onTap: () => Navigator.pop(ctx, -1),
          ),
          for (final a in options)
            _Option(
              title: a.name,
              sub: a.parentId == null ? '' : (byId[a.parentId]?.name ?? ''),
              selected: current.areaId == a.id,
              onTap: () => Navigator.pop(ctx, a.id),
            ),
        ]),
      ),
    );
    if (chosen == null) return;
    ref.read(scopeProvider.notifier).pick(kind, chosen == -1 ? null : chosen);
  }
}

class _Option extends StatelessWidget {
  final String title, sub;
  final bool selected;
  final VoidCallback onTap;
  const _Option({required this.title, required this.sub, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => TapScale(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: selected ? C.ink : C.surface, borderRadius: BorderRadius.circular(22)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: ui(15, color: selected ? Colors.white : C.ink, w: 700)),
                if (sub.isNotEmpty) Text(sub, style: ui(12, color: selected ? Colors.white70 : C.inkSoft)),
              ]),
            ),
            if (selected) const Icon(Icons.check_rounded, color: C.lime),
          ]),
        ),
      );
}
