import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/widgets/cards.dart';
import 'package:by_the_people/presentation/widgets/neta_card.dart';
import 'package:by_the_people/presentation/widgets/neta_deck.dart';
import 'package:by_the_people/presentation/widgets/scope_bar.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';
import 'package:by_the_people/presentation/features/detail/issue_detail_screen.dart';

/// Neta tab: the same light, soft surface as the rest of the app. The deck fills
/// whatever height is left, so it fits every phone without scrolling.
class NetaScreen extends ConsumerStatefulWidget {
  const NetaScreen({super.key});
  @override
  ConsumerState<NetaScreen> createState() => _NetaScreenState();
}

class _NetaScreenState extends ConsumerState<NetaScreen> {
  int _mode = 0; // 0 deck, 1 tree
  String? _party;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final pad = mq.padding;
    final scope = ref.watch(scopeProvider);
    final list = ref.watch(netasProvider);
    final tree = ref.watch(netaTreeProvider);
    final summary = ref.watch(scopeSummaryProvider);
    final tall = mq.size.height >= 780;
    final compact = mq.size.height < 700;
    final navSpace = pad.bottom + navClearance(context) + 6;

    ref.listen(scopeProvider, (_, __) => setState(() => _party = null));

    return Padding(
      padding: EdgeInsets.fromLTRB(20, pad.top + (compact ? 8 : 12), 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Neta cards', style: ui(20, w: 650))),
          _ModeSwitch(index: _mode, onChanged: (i) => setState(() => _mode = i)),
        ]),
        SizedBox(height: compact ? 8 : 12),
        const ScopeBar(),
        SizedBox(height: compact ? 2 : 6),
        if (!compact) summary.when(
          loading: () => const SizedBox(height: 18),
          error: (_, __) => const SizedBox(height: 18),
          data: (s) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '${s.reported} reported  ·  ${s.resolved} fixed  ·  ${s.events} events  ·  ${s.rate == null ? 'no rate yet' : '${(s.rate! * 100).round()}% resolved'}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: ui(12.5, color: C.inkSoft, w: 600),
            ),
          ),
        ),
        if (_mode == 0 && tall) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 42,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              Padding(padding: const EdgeInsets.only(right: 8), child: AppChip(label: 'All parties', selected: _party == null, onTap: () => setState(() => _party = null))),
              for (final p in list.asData?.value.parties ?? <String>[])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AppChip(label: p, selected: _party == p, onTap: () => setState(() => _party = _party == p ? null : p)),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: _mode == 0
              ? list.when(
                  loading: () => const NetaDeckSkeleton(),
                  error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(netasProvider)),
                  data: (data) {
                    var items = data.items.toList();
                    if (_party != null) items = items.where((n) => n.party == _party).toList();
                    // best performers on top; unrated last
                    items.sort((a, b) => (b.stats.rate ?? -1).compareTo(a.stats.rate ?? -1));
                    if (items.isEmpty) {
                      return const SingleChildScrollView(child: EmptyState(title: 'No leaders here', body: 'Nobody is registered for this area yet.'));
                    }
                    return LayoutBuilder(builder: (context, c) {
                      final avail = c.maxHeight - navSpace;
                      final cw = deckCardWidth(maxWidth: c.maxWidth, maxHeight: avail, compact: compact);
                      return Align(
                        alignment: Alignment.topCenter,
                        child: NetaDeck(
                          // new key per scope/filter so the deck restarts from the best card
                          key: ValueKey('${scope.kind}-${scope.areaId}-$_party'),
                          items: items,
                          cardWidth: cw,
                          compact: compact,
                          onOpen: (n) => _open(n.id),
                        ),
                      );
                    });
                  },
                )
              : tree.when(
                  loading: () => const RowListSkeleton(count: 4),
                  error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(netaTreeProvider)),
                  data: (roots) => roots.isEmpty
                      ? const SingleChildScrollView(child: EmptyState(title: 'No leaders here', body: 'Nobody is registered for this area yet.'))
                      : ListView(padding: EdgeInsets.only(bottom: navSpace + 8, top: 4), children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                            child: Text('Issues go to the ward councillor for the spot. Scores roll up to the MLA, MP and Minister above.',
                                style: ui(13, color: C.inkSoft, h: 1.45)),
                          ),
                          for (final r in roots) _TreeNode(neta: r, depth: 0, onTap: _open),
                        ]),
                ),
        ),
      ]),
    );
  }

  void _open(int id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NetaDetailScreen(id: id)));
}

class _ModeSwitch extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _ModeSwitch({required this.index, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    Widget b(int i, IconData icon, String label) => Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 42,
              height: 36,
              decoration: BoxDecoration(color: index == i ? C.ink : Colors.transparent, borderRadius: BorderRadius.circular(20)),
              child: Icon(icon, size: 19, color: index == i ? Colors.white : C.inkSoft),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: C.muted, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [b(0, Icons.style_rounded, 'Card deck'), b(1, Icons.account_tree_rounded, 'Tree')]),
    );
  }
}

class RateRing extends StatelessWidget {
  final double? rate;
  final double size;
  final Color color, track;
  const RateRing({super.key, required this.rate, this.size = 46, this.color = C.ink, this.track = C.muted});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: rate ?? 0),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => CustomPaint(size: Size.square(size), painter: _RingPainter(v, color, track)),
          ),
          Text(rate == null ? '—' : '${(rate! * 100).round()}', style: ui(size * 0.29, color: color, w: 800)),
        ]),
      );
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color, track;
  _RingPainter(this.v, this.color, this.track);
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(3, 3, size.width - 6, size.height - 6);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, p..color = track);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v;
}

class _TreeNode extends StatelessWidget {
  final Neta neta;
  final int depth;
  final ValueChanged<int> onTap;
  const _TreeNode({required this.neta, required this.depth, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = neta.stats;
    final sub = neta.level == 'minister' ? neta.jurisdiction : neta.constituency;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TapScale(
        onTap: () => onTap(neta.id),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
          child: Row(children: [
            RateRing(rate: s.rate, size: depth >= 2 ? 40 : 46),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(neta.name, style: ui(15, w: 750), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${neta.levelLabel} · $sub', style: ui(12, color: C.inkSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${s.resolved}/${s.reported}', style: ui(14, w: 750)),
              if (depth < 2) Text('resolved', style: ui(10.5, color: C.inkSoft)),
            ]),
          ]),
        ),
      ),
      if (neta.children.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 8),
          child: Container(
            padding: const EdgeInsets.only(left: 10),
            decoration: const BoxDecoration(border: Border(left: BorderSide(color: C.line, width: 2))),
            child: Column(children: [for (final c in neta.children) _TreeNode(neta: c, depth: depth + 1, onTap: onTap)]),
          ),
        ),
      const SizedBox(height: 8),
    ]);
  }
}

class NetaDetailScreen extends ConsumerStatefulWidget {
  final int id;
  const NetaDetailScreen({super.key, required this.id});
  @override
  ConsumerState<NetaDetailScreen> createState() => _NetaDetailScreenState();
}

class _NetaDetailScreenState extends ConsumerState<NetaDetailScreen> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(netaDetailProvider(widget.id));
    final pad = MediaQuery.of(context).padding;
    final w = MediaQuery.of(context).size.width;
    final cardW = math.min(w * 0.70, 300.0);
    return Scaffold(
      body: PageBackdrop(
        child: async.when(
          loading: () => const SafeArea(child: DetailSkeleton()),
          error: (e, _) => SafeArea(child: ErrorState(error: e, onRetry: () => ref.invalidate(netaDetailProvider(widget.id)))),
          data: (d) {
            final s = d.neta.stats;
            final list = _tab == 0 ? d.open : d.resolved;
            Widget tile(String v, String l) => Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
                    child: Column(children: [
                      Text(v, style: ui(18, w: 650)),
                      Text(l, style: ui(11, color: C.inkSoft, w: 650)),
                    ]),
                  ),
                );
            return ListView(
              padding: EdgeInsets.fromLTRB(16, pad.top + 8, 16, 60),
              children: [
                Row(children: [
                  CircleBtn(icon: Icons.arrow_back_rounded, size: 42, onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 14),
                  Expanded(child: Text(d.neta.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(20, w: 650))),
                ]),
                const SizedBox(height: 12),
                Center(child: HoloNetaCard(neta: d.neta, width: cardW)),
                const SizedBox(height: 10),
                Row(children: [
                  tile('${s.reported}', 'Reported'), const SizedBox(width: 8),
                  tile('${s.resolved}', 'Resolved'), const SizedBox(width: 8),
                  tile('${s.open}', 'Open'), const SizedBox(width: 8),
                  tile(s.avgDays == null ? '—' : s.avgDays!.toStringAsFixed(0), 'Avg days'),
                ]),
                if (!s.sampleOk)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('Not rated yet: needs ${s.minSample} issues so one fix never skews a score.', style: ui(12.5, color: C.inkSoft, h: 1.4)),
                  ),
                if (d.children.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const SectionTitle('Team below'),
                  for (final c in d.children)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TreeNode(
                        neta: Neta(id: c.id, hue: c.hue, name: c.name, party: c.party, constituency: c.constituency, level: c.level, city: c.city, state: c.state, stats: c.stats),
                        depth: 0,
                        onTap: (id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NetaDetailScreen(id: id))),
                      ),
                    ),
                ],
                const SizedBox(height: 18),
                SegmentedToggle(labels: ['Open (${d.open.length})', 'Resolved (${d.resolved.length})'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
                const SizedBox(height: 14),
                if (list.isEmpty)
                  EmptyState(title: _tab == 0 ? 'No open issues' : 'Nothing resolved yet', body: 'Issues routed here will appear in this list.')
                else
                  for (final i in list)
                    IssueCard(issue: i, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => IssueDetailScreen(id: i.id)))),
              ],
            );
          },
        ),
      ),
    );
  }
}
