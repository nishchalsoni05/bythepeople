import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/features/activity/activity_screen.dart';
import 'package:by_the_people/presentation/features/insights/insights_screen.dart';
import 'package:by_the_people/presentation/features/reminders/reminders_screen.dart';
import 'package:by_the_people/presentation/widgets/layout.dart';
import 'package:by_the_people/presentation/features/neta/neta_screen.dart';
import 'package:by_the_people/presentation/providers/locale_provider.dart';
import 'package:by_the_people/presentation/widgets/sheets.dart';
import 'package:by_the_people/presentation/widgets/stacked_card.dart';
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
      padding: EdgeInsets.fromLTRB(16, pad.top + 12, 16, 130),
      children: [
        // identity card
        StackedCard(
          layers: 2,
          offset: 6,
          inset: 10,
          child: Column(children: [
            Row(children: [
              if (u.isCitizen || u.isFoundation) _Chip(icon: Icons.bolt_rounded, text: '${u.points} pts') else _Chip(icon: _roleIcon(u.role), text: u.roleLabel),
              const Spacer(),
              if (u.badges.isNotEmpty) _Chip(icon: Icons.emoji_events_outlined, text: '${u.badges.where((b) => b.earned).length}/${u.badges.length} badges'),
            ]),
            const SizedBox(height: R.cardInset),
            Avatar(u.asPerson, size: 64),
            const SizedBox(height: R.unit),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: Text(u.displayName, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: ui(20, w: 650, h: 1.25))),
              if (u.isFoundation && u.verified) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.verified_rounded, size: 20, color: C.ink)),
            ]),
            const SizedBox(height: 2),
            Text(
              switch (u.role) {
                'admin' => u.departmentName ?? 'Platform admin',
                'neta' => u.designation ?? 'Coordinator',
                'foundation' => u.verified ? 'Verified foundation' : 'Verification pending',
                _ => 'Volunteer · ${r.name}',
              },
              textAlign: TextAlign.center,
              style: bodyStyle(color: C.inkSoft),
            ),
            if (u.isFoundation) ...[
              const SizedBox(height: R.unit),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: u.verified ? C.ink : C.muted, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(u.verified ? Icons.verified_rounded : Icons.hourglass_top_rounded, size: 14, color: u.verified ? Colors.white : C.inkSoft),
                  const SizedBox(width: 5),
                  Text(u.verified ? 'Verified' : 'Pending verification', style: ui(12.5, w: 700, color: u.verified ? Colors.white : C.inkSoft)),
                ]),
              ),
            ],
            if (u.isCitizen) ...[
              const SizedBox(height: R.cardInset),
              HatchedProgress(
                value: r.progress, fill: C.lime, track: C.muted, hatch: const Color(0x66FFFFFF), height: 30,
                label: r.next == null ? 'Top rank reached' : '${r.nextAt! - u.points} pts to ${r.next}',
              ),
            ],
          ]),
        ),
        const SizedBox(height: R.cardInset),
        if (u.isCitizen || u.isFoundation) ...[
          _ImpactCard(meals: u.stats['meals'] ?? u.stats['mealsServed'] ?? u.stats['closedHelped'] ?? 0, foundation: u.isFoundation),
          const SizedBox(height: R.unit),
          Row(children: [
            _Stat('${u.stats['given'] ?? u.stats['claimed'] ?? u.stats['closedHelped'] ?? 0}', u.isFoundation ? 'Claimed' : 'Items given'),
            const SizedBox(width: R.unit),
            _Stat('${u.stats['joins'] ?? u.stats['distributed'] ?? 0}', u.isFoundation ? 'Distributed' : 'Events joined'),
            const SizedBox(width: R.unit),
            _Stat('${u.badges.where((b) => b.earned).length}', 'Badges'),
          ]),
          const SizedBox(height: R.cardInset),
        ],
        _Link(
          icon: Icons.insights_rounded,
          label: 'Insights',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InsightsScreen())),
        ),
        const SizedBox(height: R.unit),
        _Link(
          icon: Icons.notifications_active_outlined,
          label: 'Reminders',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PushedPage(title: 'Reminders', child: RemindersScreen()))),
        ),
        if (u.isFoundation && !u.verified) ...[
          const SizedBox(height: R.cardInset),
          Container(
            padding: const EdgeInsets.all(R.cardInset),
            decoration: BoxDecoration(color: const Color(0xFFFFF0D8), borderRadius: BorderRadius.circular(R.card)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.hourglass_top_rounded, color: C.ember),
              const SizedBox(width: 10),
              Expanded(child: Text('Our team is reviewing your registration. You can browse surplus now and claim it once you are verified.', style: ui(13, color: C.inkSoft, h: 1.4, w: 600))),
            ]),
          ),
        ],
        if (u.isCitizen) ...[
        const SizedBox(height: R.cardInset),
        Column(children: [
          _Link(icon: Icons.hub_rounded, label: 'Coordinators', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PushedPage(title: 'Coordinators', child: NetaScreen())))),
          const SizedBox(height: R.unit),
          _Link(icon: Icons.history_rounded, label: 'My activity', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PushedPage(title: 'My activity', child: ActivityScreen())))),
        ]),
        const SizedBox(height: R.cardInset),
        // settings
        FlatCard(
          padding: const EdgeInsets.fromLTRB(R.cardInset, R.unit, R.cardInset, R.unit),
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
              padding: const EdgeInsets.symmetric(vertical: R.unit + 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Alert radius', style: titleStyle())),
                  Text('${radius.round()} km', style: numStyle(15, w: 700)),
                ]),
                Text('Events within this distance can reach you and be joined', style: metaStyle()),
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
          const SizedBox(height: R.cardInset),
          _FoundationEditor(u: u, patch: _patch),
        ],
        if (u.isAdmin || u.isNeta) ...[
          const SizedBox(height: R.cardInset),
          FlatCard(
            padding: const EdgeInsets.all(R.cardInset),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Info(Icons.mail_outline_rounded, 'Email', u.email),
              if (u.isAdmin && (u.departmentName ?? '').isNotEmpty) _Info(Icons.account_balance_rounded, 'Department', u.departmentName!),
              if (u.isNeta && (u.designation ?? '').isNotEmpty) _Info(Icons.hub_rounded, 'Role', u.designation!),
              _Info(Icons.badge_outlined, 'Account type', u.roleLabel),
            ]),
          ),
        ],
        if (u.badges.isNotEmpty && (u.isCitizen || u.isFoundation)) ...[
        const SizedBox(height: R.cardInset),
        const SectionTitle('Badges'),
        GridView(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: R.unit, crossAxisSpacing: R.unit, mainAxisExtent: 118),
          children: [for (final b in u.badges) _Badge(b)],
        ),
        ],
        const SizedBox(height: R.cardInset),
        FlatCard(
          padding: const EdgeInsets.symmetric(horizontal: R.cardInset),
          child: _Row(
            title: tr(ref, 'profile_language'), sub: 'Show the app in English or Hindi',
            trailing: SizedBox(
              width: 150,
              child: SegmentedToggle(
                labels: [tr(ref, 'language_english'), tr(ref, 'language_hindi')],
                index: ref.watch(localeProvider) == 'hi' ? 1 : 0,
                onChanged: (i) => ref.read(localeProvider.notifier).setLocale(i == 1 ? 'hi' : 'en'),
              ),
            ),
          ),
        ),
        const SizedBox(height: R.cardInset + R.unit),
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
      'neta' => Icons.hub_rounded,
      'foundation' => Icons.volunteer_activism_rounded,
      _ => Icons.person_rounded,
    };

class _Link extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Link({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => FlatCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: R.unit + 4, vertical: R.unit + 4),
        child: Row(children: [
          IconChip(icon),
          const SizedBox(width: R.unit + 4),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle())),
          const Icon(Icons.chevron_right_rounded, size: 20, color: C.inkSoft),
        ]),
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
              Text(label, style: metaStyle()),
              Text(value, style: bodyStyle(), maxLines: 2, overflow: TextOverflow.ellipsis),
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
      subtitle: 'Givers and admins see this on your public profile.',
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
    return FlatCard(
      padding: const EdgeInsets.all(R.cardInset),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Our needs', style: titleStyle())),
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
        Text('Givers see these first. Tap to toggle.', style: metaStyle()),
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
          const SizedBox(height: R.cardInset),
          _Info(Icons.badge_outlined, 'Registration no.', u.regNo!),
        ],
        if ((u.address ?? '').isNotEmpty) _Info(Icons.place_outlined, 'Address', u.address!),
        if ((u.about ?? '').isNotEmpty) _Info(Icons.notes_rounded, 'About', u.about!),
      ]),
    );
  }
}

class _ImpactCard extends StatelessWidget {
  final int meals;
  final bool foundation;
  const _ImpactCard({required this.meals, required this.foundation});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(R.card), boxShadow: C.shadowSoft),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your impact', style: metaStyle()),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: meals.toDouble()),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Text('${v.round()}', style: display(44, w: 700)),
              ),
              Text(foundation ? 'Meals served to people in need' : 'Meals you helped serve', style: ui(13.5, color: C.inkSoft)),
            ]),
          ),
          Container(
            width: 52, height: 52,
            decoration: const BoxDecoration(color: C.muted, shape: BoxShape.circle),
            child: const Icon(Icons.restaurant_rounded, color: C.ink),
          ),
        ]),
      );
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Chip({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(12), boxShadow: C.shadowSoft),
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
        child: FlatCard(
          padding: const EdgeInsets.symmetric(vertical: R.cardInset - 2, horizontal: R.unit),
          child: Column(children: [Text(v, style: numStyle(20)), const SizedBox(height: 2), Text(l, style: metaStyle())]),
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
              Text(title, style: titleStyle()),
              const SizedBox(height: 2),
              Text(sub, style: metaStyle()),
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
          borderRadius: BorderRadius.circular(R.card - 8),
          boxShadow: on ? C.shadowSoft : null,
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
