import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/features/activity/activity_screen.dart';
import 'package:by_the_people/presentation/features/neta/neta_screen.dart';
import 'package:by_the_people/presentation/widgets/layout.dart';
import 'package:by_the_people/presentation/widgets/sheets.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

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
          radius: 14,
          child: Column(children: [
            Row(children: [
              if (u.isCitizen || u.isFoundation) _Chip(icon: Icons.bolt_rounded, text: '${u.points} pts') else _Chip(icon: _roleIcon(u.role), text: u.roleLabel),
              const Spacer(),
              if (u.badges.isNotEmpty) _Chip(icon: Icons.emoji_events_outlined, text: '${u.badges.where((b) => b.earned).length}/${u.badges.length} badges'),
            ]),
            const SizedBox(height: 14),
            Avatar(u.asPerson, size: 64),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: Text(u.displayName, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: ui(20, w: 650))),
              if (u.isFoundation && u.verified) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.verified_rounded, size: 20, color: Color(0xFF2F80ED))),
            ]),
            const SizedBox(height: 2),
            Text(
              switch (u.role) {
                'admin' => u.departmentName ?? 'Authority officer',
                'neta' => u.designation ?? 'Neta',
                'foundation' => u.verified ? 'Verified foundation' : 'Verification pending',
                _ => 'Elder Scout · ${r.name}',
              },
              textAlign: TextAlign.center,
              style: ui(14, color: C.inkSoft, w: 650),
            ),
            if (u.isCitizen) ...[
              const SizedBox(height: 18),
              HatchedProgress(
                value: r.progress, fill: C.lime, track: C.muted, hatch: const Color(0x66FFFFFF), height: 30,
                label: r.next == null ? 'Top rank reached' : '${r.nextAt! - u.points} pts to ${r.next}',
              ),
            ],
          ]),
        ),
        if (u.isFoundation && !u.verified) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFFFF0D8), borderRadius: BorderRadius.circular(14)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.hourglass_top_rounded, color: C.ember),
              const SizedBox(width: 10),
              Expanded(child: Text('An admin is reviewing your registration. You can browse donations now and claim them once verified.', style: ui(13, color: C.inkSoft, h: 1.4, w: 600))),
            ]),
          ),
        ],
        if (u.isCitizen) ...[
        const SizedBox(height: 14),
        Row(children: [
          _Stat('${u.stats['reports'] ?? 0}', 'Reports'),
          const SizedBox(width: 10),
          _Stat('${u.stats['supports'] ?? 0}', 'Supports'),
          const SizedBox(width: 10),
          _Stat('${u.stats['joins'] ?? 0}', 'Events'),
          const SizedBox(width: 10),
          _Stat('${u.stats['closedHelped'] ?? 0}', 'Fixed'),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _Link(icon: Icons.shield_moon_rounded, label: 'Leaders', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PushedPage(title: 'Leaders', child: NetaScreen()))))),
          const SizedBox(width: 10),
          Expanded(child: _Link(icon: Icons.history_rounded, label: 'My activity', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PushedPage(title: 'My activity', child: ActivityScreen()))))),
        ]),
        const SizedBox(height: 18),
        // settings
        Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          decoration: BoxDecoration(color: C.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(R.card), border: Border.all(color: C.line)),
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
        ],
        if (u.isFoundation) ...[
          const SizedBox(height: 18),
          _FoundationEditor(u: u, patch: _patch),
        ],
        if (u.isAdmin || u.isNeta) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: C.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(R.card), border: Border.all(color: C.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Info(Icons.mail_outline_rounded, 'Email', u.email),
              if (u.isAdmin && (u.departmentName ?? '').isNotEmpty) _Info(Icons.account_balance_rounded, 'Department', u.departmentName!),
              if (u.isNeta && (u.designation ?? '').isNotEmpty) _Info(Icons.how_to_vote_rounded, 'Designation', u.designation!),
              _Info(Icons.badge_outlined, 'Account type', u.roleLabel),
            ]),
          ),
        ],
        if (u.badges.isNotEmpty && (u.isCitizen || u.isFoundation)) ...[
        const SizedBox(height: 22),
        const SectionTitle('Merit badges'),
        GridView(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 118),
          children: [for (final b in u.badges) _Badge(b)],
        ),
        ],
        const SizedBox(height: 22),
        PillButton(
          label: 'Sign out', icon: Icons.logout_rounded, color: C.muted, fg: C.ink,
          onPressed: () => ref.read(authProvider.notifier).logout(),
        ),
      ],
    );
  }
}

IconData _roleIcon(String role) => switch (role) {
      'admin' => Icons.account_balance_rounded,
      'neta' => Icons.how_to_vote_rounded,
      'foundation' => Icons.volunteer_activism_rounded,
      _ => Icons.person_rounded,
    };

class _Link extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Link({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => TapScale(
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: C.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
          child: Row(children: [
            Icon(icon, size: 19, color: C.ember),
            const SizedBox(width: 8),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(13.5, w: 700))),
            const Icon(Icons.chevron_right_rounded, size: 18, color: C.inkSoft),
          ]),
        ),
      );
}

class _Info extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _Info(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(icon, size: 19, color: C.inkSoft),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: ui(11.5, color: C.inkSoft, w: 650)),
              Text(value, style: ui(14.5, w: 700), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      );
}

const _needKinds = ['food', 'clothes', 'bottles', 'books', 'toys', 'essentials', 'other'];

/// Foundation profile: what the organisation needs (shown to donors) and its public details.
class _FoundationEditor extends StatefulWidget {
  final UserProfile u;
  final Future<void> Function(Map<String, dynamic>) patch;
  const _FoundationEditor({required this.u, required this.patch});
  @override
  State<_FoundationEditor> createState() => _FoundationEditorState();
}

class _FoundationEditorState extends State<_FoundationEditor> {
  Future<void> _edit() async {
    final u = widget.u;
    final org = TextEditingController(text: u.orgName ?? ''), about = TextEditingController(text: u.about ?? ''), addr = TextEditingController(text: u.address ?? '');
    final ok = await showAppSheet<bool>(
      context,
      title: 'Foundation details',
      subtitle: 'Donors and admins see this on your public profile.',
      body: (ctx) => Column(children: [
        AppField(controller: org, hint: 'Organisation name', icon: Icons.apartment_rounded, maxLength: 80),
        const SizedBox(height: 10),
        AppField(controller: addr, hint: 'Address', icon: Icons.place_outlined, maxLength: 160),
        const SizedBox(height: 10),
        AppField(controller: about, hint: 'About your work', lines: 3, maxLength: 400),
        const SizedBox(height: 16),
        PillButton(label: 'Save', icon: Icons.check_rounded, onPressed: () => Navigator.pop(ctx, true)),
      ]),
    );
    if (ok == true) {
      await widget.patch({
        if (org.text.trim().isNotEmpty) 'orgName': org.text.trim(),
        'about': about.text.trim(),
        'address': addr.text.trim(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.u;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: C.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(R.card), border: Border.all(color: C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Our needs', style: ui(16, w: 750))),
          TapScale(
            onTap: _edit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: C.muted, borderRadius: BorderRadius.circular(18)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.edit_rounded, size: 14),
                const SizedBox(width: 5),
                Text('Edit details', style: ui(12.5, w: 700)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Donors see these first. Tap to toggle.', style: ui(12.5, color: C.inkSoft)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in _needKinds)
            AppChip(
              label: k[0].toUpperCase() + k.substring(1),
              selected: u.needs.contains(k),
              onTap: () => widget.patch({
                'needs': u.needs.contains(k) ? (List<String>.of(u.needs)..remove(k)) : [...u.needs, k],
              }),
            ),
        ]),
        if ((u.regNo ?? '').isNotEmpty) ...[
          const SizedBox(height: 14),
          _Info(Icons.badge_outlined, 'Registration no.', u.regNo!),
        ],
        if ((u.address ?? '').isNotEmpty) _Info(Icons.place_outlined, 'Address', u.address!),
        if ((u.about ?? '').isNotEmpty) _Info(Icons.notes_rounded, 'About', u.about!),
      ]),
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
          decoration: BoxDecoration(color: C.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
          child: Column(children: [Text(v, style: ui(20, w: 650)), Text(l, style: ui(11.5, color: C.inkSoft, w: 650))]),
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
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: C.line),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? C.ember : C.muted,
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
