import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/state.dart';
import '../../core/tokens.dart';
import '../../core/widgets/shaders.dart';
import '../../core/widgets/ui.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  double? _radius; // while dragging

  Future<void> _patch(Map<String, dynamic> body) async {
    try {
      await ref.read(authProvider.notifier).patch(body);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = ref.watch(authProvider).user;
    final pad = MediaQuery.of(context).padding;
    if (u == null) return const SizedBox();
    final r = u.rank;
    final radius = _radius ?? u.alertRadiusKm;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, pad.top + 12, 16, 150),
      children: [
        // identity card
        FrostedPanel(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          radius: 30,
          child: Column(children: [
            Row(children: [
              _Chip(icon: Icons.bolt_rounded, text: '${u.points} pts'),
              const Spacer(),
              _Chip(icon: Icons.emoji_events_outlined, text: '${u.badges.where((b) => b.earned).length}/${u.badges.length} badges'),
            ]),
            const SizedBox(height: 14),
            Stack(alignment: Alignment.center, children: [
              const Orb(size: 104),
              Avatar(u.asPerson, size: 56, ring: Colors.white),
            ]),
            const SizedBox(height: 12),
            Text(u.name, style: ui(20, w: 750)),
            const SizedBox(height: 2),
            Text('Elder Scout · ${r.name}', style: ui(14, color: C.inkSoft, w: 650)),
            const SizedBox(height: 18),
            HatchedProgress(
              value: r.progress, fill: C.lime, track: C.muted, hatch: const Color(0x66FFFFFF), height: 30,
              label: r.next == null ? 'Top rank reached' : '${r.nextAt! - u.points} pts to ${r.next}',
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          _Stat('${u.stats['reports']}', 'Reports'),
          const SizedBox(width: 10),
          _Stat('${u.stats['supports']}', 'Supports'),
          const SizedBox(width: 10),
          _Stat('${u.stats['joins']}', 'Events'),
          const SizedBox(width: 10),
          _Stat('${u.stats['closedHelped']}', 'Fixed'),
        ]),
        const SizedBox(height: 18),
        // settings
        Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          decoration: BoxDecoration(color: C.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(R.card), boxShadow: softShadow),
          child: Column(children: [
            _Row(
              title: 'Volunteer mode', sub: 'Get alerted when events start near you',
              trailing: SizedBox(
                width: 118,
                child: SegmentedToggle(labels: const ['Off', 'On'], index: u.volunteer ? 1 : 0, onChanged: (i) => _patch({'volunteer': i == 1})),
              ),
            ),
            const Divider(height: 1, color: C.line),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Alert radius', style: ui(15, w: 700))),
                  Text('${radius.round()} km', style: ui(15, w: 750)),
                ]),
                Text('Events within this distance can reach you and be joined', style: ui(12.5, color: C.inkSoft)),
                Slider(
                  value: radius, min: 1, max: 25, divisions: 24,
                  onChanged: (v) => setState(() => _radius = v),
                  onChangeEnd: (v) async {
                    await _patch({'alertRadiusKm': v});
                    if (mounted) setState(() => _radius = null);
                  },
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        const SectionTitle('Merit badges'),
        GridView(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 118),
          children: [for (final b in u.badges) _Badge(b)],
        ),
        const SizedBox(height: 22),
        PillButton(
          label: 'Sign out', icon: Icons.logout_rounded, color: C.muted, fg: C.ink,
          onPressed: () => ref.read(authProvider.notifier).logout(),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Chip({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: C.ember),
          const SizedBox(width: 5),
          Text(text, style: ui(12.5, w: 700)),
        ]),
      );
}

class _Stat extends StatelessWidget {
  final String v, l;
  const _Stat(this.v, this.l);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(color: C.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(22), boxShadow: softShadow),
          child: Column(children: [Text(v, style: ui(20, w: 750)), Text(l, style: ui(11.5, color: C.inkSoft, w: 650))]),
        ),
      );
}

class _Row extends StatelessWidget {
  final String title, sub;
  final Widget trailing;
  const _Row({required this.title, required this.sub, required this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: ui(15, w: 700)),
              const SizedBox(height: 2),
              Text(sub, style: ui(12.5, color: C.inkSoft, h: 1.35)),
            ]),
          ),
          const SizedBox(width: 10),
          trailing,
        ]),
      );
}

class _Badge extends StatelessWidget {
  final BadgeInfo b;
  const _Badge(this.b);
  @override
  Widget build(BuildContext context) {
    final on = b.earned;
    return GestureDetector(
      onTap: () => showToast(context, on ? '${b.name}: ${b.desc}' : 'Locked. ${b.desc}', icon: on ? Icons.emoji_events_rounded : Icons.lock_outline_rounded),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: on ? C.surface : C.surface.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(24),
          boxShadow: on ? softShadow : null,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: on ? const LinearGradient(colors: [C.emberLight, C.ember], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
              color: on ? null : C.muted,
            ),
            child: Icon(on ? (badgeIcons[b.icon] ?? Icons.star) : Icons.lock_outline_rounded, color: on ? Colors.white : C.inkSoft.withValues(alpha: 0.6), size: 26),
          ),
          const SizedBox(height: 8),
          Text(b.name, textAlign: TextAlign.center, maxLines: 2, style: ui(11.5, color: on ? C.ink : C.inkSoft, w: 700, h: 1.2)),
        ]),
      ),
    );
  }
}
