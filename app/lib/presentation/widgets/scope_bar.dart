import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

const _kinds = ['city', 'state', 'region'];
const _kindLabels = ['City', 'State', 'Region'];

/// One compact chip showing the active place ("Raipur"); tap opens a sheet to change
/// the scope kind (city / state / region) and pick any area. Replaces the old 3-row scope header.
class ScopeChip extends ConsumerWidget {
  const ScopeChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = ref.watch(scopeLabelProvider);
    return FilterButton(
      icon: Icons.place_outlined,
      label: label,
      onTap: () => showScopeSheet(context, ref),
    );
  }
}

/// Compact scope row (one chip). Kept for screens that previously used the big [ScopeBar].
class ScopeBar extends StatelessWidget {
  final bool dark;
  const ScopeBar({super.key, this.dark = false});

  @override
  Widget build(BuildContext context) => const Align(alignment: Alignment.centerLeft, child: ScopeChip());
}

Future<void> showScopeSheet(BuildContext context, WidgetRef ref) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ScopeSheet(),
  );
}

class _ScopeSheet extends ConsumerWidget {
  const _ScopeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sc = ref.watch(scopeProvider);
    final areas = ref.watch(areasProvider).asData?.value ?? const <Area>[];
    final here = ref.watch(hereProvider).asData?.value;
    final kind = sc.kind;
    final options = areas.where((a) => a.kind == kind).toList();
    final byId = {for (final a in areas) a.id: a};
    final mine = here?[kind]?['name'];
    final maxH = MediaQuery.sizeOf(context).height * 0.7;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: const BoxDecoration(color: C.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet))),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 12),
          Text('Show issues from', style: ui(16, w: 650)),
          const SizedBox(height: 10),
          SegmentedToggle(
            labels: _kindLabels,
            index: _kinds.indexOf(kind),
            onChanged: (i) => ref.read(scopeProvider.notifier).setKind(_kinds[i]),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 16), children: [
              _Option(
                title: mine == null ? 'My $kind' : 'My $kind · $mine',
                sub: 'Follows your location',
                selected: sc.areaId == null,
                onTap: () {
                  ref.read(scopeProvider.notifier).pick(kind, null);
                  Navigator.pop(context);
                },
              ),
              for (final a in options)
                _Option(
                  title: a.name,
                  sub: a.parentId == null ? '' : (byId[a.parentId]?.name ?? ''),
                  selected: sc.areaId == a.id,
                  onTap: () {
                    ref.read(scopeProvider.notifier).pick(kind, a.id);
                    Navigator.pop(context);
                  },
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final String title, sub;
  final bool selected;
  final VoidCallback onTap;
  const _Option({required this.title, required this.sub, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: ui(14.5, w: selected ? 650 : 500)),
                if (sub.isNotEmpty) Text(sub, style: ui(12, color: C.inkSoft)),
              ]),
            ),
            if (selected) const Icon(Icons.check_rounded, size: 18, color: C.ember),
          ]),
        ),
      );
}
