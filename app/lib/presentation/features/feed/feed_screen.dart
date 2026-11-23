import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/domain/entities/donation.dart';
import 'package:by_the_people/domain/entities/gathering.dart';
import 'package:by_the_people/domain/entities/need.dart';
import 'package:by_the_people/presentation/features/needs/needs_screen.dart';
import 'package:by_the_people/presentation/features/notifications/notifications_screen.dart';
import 'package:by_the_people/presentation/providers/donation_providers.dart';
import 'package:by_the_people/presentation/providers/gathering_providers.dart';
import 'package:by_the_people/presentation/providers/locale_provider.dart';
import 'package:by_the_people/presentation/providers/needs_providers.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/presentation/widgets/media.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// Neutral tint used for icon tiles and stat chips (the system stays monochrome).
const _peach = Color(0xFFF1F1F3);
const _mint = Color(0xFFF1F1F3);
const _lilac = Color(0xFFF1F1F3);
const _sky = Color(0xFFF1F1F3);
const _butter = Color(0xFFF1F1F3);
const _rose = Color(0xFFF1F1F3);

/// Home: greeting, live-impact hero with a progress ring, category shortcuts, the most urgent need,
/// surplus food available now, upcoming events, and the other open needs.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  void _needs(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NeedsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final pad = MediaQuery.of(context).padding;
    final openAsync = ref.watch(needsProvider('open'));
    final doneAsync = ref.watch(needsProvider('closed'));
    final open = [...(openAsync.asData?.value ?? const <Need>[])]
      ..sort((a, b) => a.urgencyRank != b.urgencyRank ? a.urgencyRank.compareTo(b.urgencyRank) : b.createdAt.compareTo(a.createdAt));
    final done = doneAsync.asData?.value ?? const <Need>[];
    final surplus = (ref.watch(donationsProvider((null, 'available', 'new'))).asData?.value ?? const <Donation>[]).take(8).toList();
    final events = (ref.watch(gatheringsProvider(('upcoming', null, 'soon', null))).asData?.value ?? const <Gathering>[]).take(8).toList();
    final pledgedCount = open.where((n) => n.pledgeCount > 0).length;
    final loaded = openAsync.hasValue;
    final name = auth.user?.name ?? '';
    final first = name.split(' ').first;
    final now = DateTime.now();
    final greet = tr(ref, now.hour < 12 ? 'home_good_morning' : (now.hour < 17 ? 'home_good_afternoon' : 'home_good_evening'));
    final dateLine = 'Today, ${_months[now.month - 1]} ${now.day}';
    final total = open.length + done.length;
    final ratio = total == 0 ? 0.0 : done.length / total;

    return RefreshIndicator(
      color: C.ink,
      edgeOffset: pad.top + 20,
      onRefresh: () async {
        ref.read(welfareTickProvider.notifier).bump();
        await ref.read(needsProvider('open').future);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(0, pad.top + 14, 0, navClearance(context) + 12),
            sliver: SliverList.list(children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  _Avatar(name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(first.isEmpty ? '$greet!' : '$greet, $first', maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(22, w: 700, ls: -0.6)),
                      const SizedBox(height: 1),
                      Text(dateLine, style: metaStyle()),
                    ]),
                  ),
                  CircleBtn(
                    icon: Icons.notifications_none_rounded,
                    size: 42,
                    dot: auth.unread > 0,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                  ),
                ]),
              ),
              const SizedBox(height: 18),

              // Hero
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _Hero(
                  ratio: loaded ? ratio : 0,
                  loaded: loaded,
                  counts: [
                    (loaded ? '${open.length}' : '–', 'Open needs', _peach),
                    (loaded ? '$pledgedCount' : '–', 'Pledged', _sky),
                    (loaded ? '${done.length}' : '–', 'Fulfilled', _mint),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // Categories
              SizedBox(
                height: 92,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _Cat(Icons.restaurant_rounded, 'Food', _peach, () => _needs(context)),
                    _Cat(Icons.checkroom_rounded, 'Clothes', _lilac, () => _needs(context)),
                    _Cat(Icons.medication_outlined, 'Medicine', _rose, () => _needs(context)),
                    _Cat(Icons.edit_outlined, 'Stationery', _butter, () => _needs(context)),
                    _Cat(Icons.payments_outlined, 'Money', _mint, () => _needs(context)),
                    _Cat(Icons.groups_rounded, 'Volunteers', _sky, () => _needs(context)),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Urgent need
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _Head(tr(ref, 'home_urgent'), onAll: () => _needs(context)),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: !loaded
                    ? const SizedBox(height: 150, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: C.ink)))
                    : open.isEmpty
                        ? const _EmptyPanel(text: 'No urgent needs right now. Check back soon.')
                        : _Featured(need: open.first, onTap: () => _needs(context)),
              ),

              // Surplus now
              if (surplus.isNotEmpty) ...[
                const SizedBox(height: 26),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _Head('Surplus available now', onAll: () => ref.read(shellTabProvider.notifier).go(2)),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 236,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                    itemCount: surplus.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _SurplusCard(d: surplus[i], onTap: () => ref.read(shellTabProvider.notifier).go(2)),
                  ),
                ),
              ],

              // Events
              if (events.isNotEmpty) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _Head('Upcoming events', onAll: () => ref.read(shellTabProvider.notifier).go(1)),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 236,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                    itemCount: events.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _EventCard(g: events[i], onTap: () => ref.read(shellTabProvider.notifier).go(1)),
                  ),
                ),
              ],

              // More needs
              if (open.length > 1) ...[
                const SizedBox(height: 14),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _Head(tr(ref, 'home_recent_impact'), onAll: () => _needs(context))),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(children: [for (final n in open.skip(1).take(5)) _NeedRow(need: n, onTap: () => _needs(context))]),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar(this.name);
  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty ? 'S' : parts.take(2).map((p) => p[0].toUpperCase()).join();
    return Container(
      width: 46, height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: C.muted,
        boxShadow: C.shadowSoft,
      ),
      child: Text(initials, style: ui(15, w: 700)),
    );
  }
}

class _Head extends StatelessWidget {
  final String title;
  final VoidCallback? onAll;
  const _Head(this.title, {this.onAll});
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(title, style: titleStyle())),
        if (onAll != null)
          TapScale(
            onTap: onAll,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(20), boxShadow: C.shadowSoft),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('See all', style: metaStyle(color: C.ink).copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_forward_rounded, size: 14, color: C.ink),
              ]),
            ),
          ),
      ]);
}

/// Compact impact card: progress ring + headline, then three quiet counts separated by hairlines.
class _Hero extends StatelessWidget {
  final double ratio;
  final bool loaded;
  final List<(String, String, Color)> counts;
  const _Hero({required this.ratio, required this.loaded, required this.counts});

  @override
  Widget build(BuildContext context) {
    final fulfilled = int.tryParse(counts[2].$1) ?? 0;
    final totalNeeds = (int.tryParse(counts[0].$1) ?? 0) + fulfilled;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(22), boxShadow: C.shadowSoft),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          SizedBox(
            width: 52, height: 52,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => CustomPaint(
                painter: _RingPainter(v),
                child: Center(child: Text(loaded ? '${(v * 100).round()}%' : '–', style: numStyle(13, w: 700))),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(loaded ? '$fulfilled of $totalNeeds needs fulfilled' : 'Loading needs…', style: ui(15.5, w: 700, ls: -0.3)),
              const SizedBox(height: 3),
              Row(children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF2FB36B), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('Live in Bhilai-Durg', style: metaStyle()),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Container(height: 1, color: C.line),
        const SizedBox(height: 10),
        Row(children: [
          for (var i = 0; i < counts.length; i++) ...[
            if (i > 0) Container(width: 1, height: 26, color: C.line),
            Expanded(
              child: Column(children: [
                Text(counts[i].$1, style: numStyle(18, w: 700)),
                Text(counts[i].$2, style: metaStyle().copyWith(fontSize: 11.5)),
              ]),
            ),
          ],
        ]),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  _RingPainter(this.value);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 5..color = C.ink.withValues(alpha: 0.08));
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = C.ink;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * math.max(value, 0.015), false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}

/// Pastel rounded category shortcut.
class _Cat extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;
  const _Cat(this.icon, this.label, this.tint, this.onTap);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: TapScale(
          onTap: onTap,
          child: SizedBox(
            width: 64,
            child: Column(children: [
              Container(
                width: 58, height: 58,
                decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(20)),
                child: Icon(icon, size: 24, color: C.ink),
              ),
              const SizedBox(height: 7),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle(color: C.ink).copyWith(fontWeight: FontWeight.w600, fontSize: 11.5)),
            ]),
          ),
        ),
      );
}

/// The most urgent need as one clean card with a single progress line.
class _Featured extends StatelessWidget {
  final Need need;
  final VoidCallback onTap;
  const _Featured({required this.need, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final icon = categoryIcons[need.kind] ?? Icons.volunteer_activism_outlined;
    final hasQty = need.targetQty > 0;
    final progress = hasQty ? (need.pledgedQty / need.targetQty).clamp(0.0, 1.0) : need.progress.clamp(0.0, 1.0);
    final unit = need.unit.isEmpty ? '' : ' ${need.unit}';
    final urgent = need.urgency == 'critical' || need.urgency == 'high';
    return TapScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(24), boxShadow: C.shadowSoft),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: _lilac, borderRadius: BorderRadius.circular(15)),
              child: Icon(icon, size: 21, color: C.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(need.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(17, w: 700, h: 1.2, ls: -0.3)),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(need.foundation.verified ? Icons.verified_rounded : Icons.home_work_outlined, size: 13, color: C.inkSoft),
                  const SizedBox(width: 4),
                  Expanded(child: Text(need.foundation.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle())),
                ]),
              ]),
            ),
            if (urgent) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.bolt_rounded, size: 13, color: Colors.white),
                  const SizedBox(width: 2),
                  Text(need.urgency == 'critical' ? 'Urgent' : 'Soon', style: metaStyle(color: Colors.white).copyWith(fontWeight: FontWeight.w700)),
                ]),
              ),
            ],
          ]),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 8, backgroundColor: C.muted, color: C.ink),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Text(hasQty ? '${need.pledgedQty} of ${need.targetQty}$unit pledged' : '${need.pledgeCount} pledged', style: metaStyle().copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            const Spacer(),
            Text('Help', style: metaStyle(color: C.ink).copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_forward_rounded, size: 14, color: C.ink),
          ]),
        ]),
      ),
    );
  }
}

String _timeLeft(int expiresAt) {
  final m = ((expiresAt - DateTime.now().millisecondsSinceEpoch) / 60000).round();
  if (m <= 0) return 'Expired';
  if (m < 60) return '${m}m left';
  if (m < 60 * 24) return '${(m / 60).floor()}h left';
  return '${(m / 1440).floor()}d left';
}

/// Photo card with a white caption area; the image area falls back to a pastel tile with an icon.
class _PhotoCard extends StatelessWidget {
  final String? image;
  final IconData fallback;
  final Color tint;
  final Widget topLeft;
  final Widget? topRight;
  final String title, meta;
  final Widget footer;
  final VoidCallback onTap;
  const _PhotoCard({
    required this.image, required this.fallback, required this.tint, required this.topLeft, this.topRight,
    required this.title, required this.meta, required this.footer, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => TapScale(
        onTap: onTap,
        child: Container(
          width: 236,
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(24), boxShadow: C.shadowSoft),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 118,
              width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                if (image != null)
                  NetImage(image!, fit: BoxFit.cover, fallbackIcon: fallback)
                else
                  Container(color: tint, child: Icon(fallback, size: 36, color: C.ink.withValues(alpha: 0.55))),
                Positioned(left: 10, top: 10, child: topLeft),
                if (topRight != null) Positioned(right: 10, top: 10, child: topRight!),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(14.5, w: 700, ls: -0.2)),
                const SizedBox(height: 2),
                Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle()),
                const SizedBox(height: 10),
                footer,
              ]),
            ),
          ]),
        ),
      );
}

class _Pill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color bg;
  final Color fg;
  const _Pill(this.text, {this.icon, this.bg = Colors.white, this.fg = C.ink});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 3)],
          Text(text, style: metaStyle(color: fg).copyWith(fontWeight: FontWeight.w700, fontSize: 11.5)),
        ]),
      );
}

class _SurplusCard extends StatelessWidget {
  final Donation d;
  final VoidCallback onTap;
  const _SurplusCard({required this.d, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final icon = categoryIcons[d.kind] ?? Icons.restaurant_rounded;
    final soon = d.expiresAt - DateTime.now().millisecondsSinceEpoch < 3 * 3600 * 1000;
    final dist = km(d.distanceKm);
    return _PhotoCard(
      image: d.media.isEmpty ? null : d.media.first,
      fallback: icon,
      tint: _peach,
      topLeft: _Pill(d.kindLabel, icon: icon),
      topRight: _Pill(_timeLeft(d.expiresAt), icon: Icons.schedule_rounded, bg: soon ? C.ink : Colors.white, fg: soon ? Colors.white : C.ink),
      title: d.title,
      meta: [if (d.servings != null) '${d.servings} servings' else d.quantity, d.donor.name].where((e) => e.isNotEmpty).join(' · '),
      footer: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(20)),
          child: Text('Claim', style: metaStyle(color: Colors.white).copyWith(fontWeight: FontWeight.w700)),
        ),
        const Spacer(),
        if (dist.isNotEmpty) ...[
          const Icon(Icons.near_me_rounded, size: 13, color: C.inkSoft),
          const SizedBox(width: 3),
          Text(dist, style: metaStyle()),
        ],
      ]),
      onTap: onTap,
    );
  }
}

class _EventCard extends StatelessWidget {
  final Gathering g;
  final VoidCallback onTap;
  const _EventCard({required this.g, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch(g.startAt);
    final cap = g.capacity;
    final shown = g.attendees.take(4).toList();
    return _PhotoCard(
      image: g.media.isEmpty ? null : g.media.first,
      fallback: Icons.diversity_3_rounded,
      tint: _mint,
      topLeft: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${dt.day}', style: numStyle(16, w: 700)),
          Text(_mon[dt.month - 1].toUpperCase(), style: metaStyle().copyWith(fontSize: 9.5, fontWeight: FontWeight.w700)),
        ]),
      ),
      topRight: _Pill(g.typeLabel),
      title: g.title,
      meta: [fmtTime(g.startAt), if (g.address.isNotEmpty) g.address.split(',').first].join(' · '),
      footer: Row(children: [
        if (shown.isNotEmpty)
          SizedBox(
            height: 24,
            width: 24.0 + (shown.length - 1) * 16,
            child: Stack(children: [
              for (var i = 0; i < shown.length; i++)
                Positioned(
                  left: i * 16.0,
                  child: Container(
                    width: 24, height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xFFE6E6E9), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                    child: Text(shown[i].name.isEmpty ? '?' : shown[i].name[0].toUpperCase(), style: metaStyle(color: C.ink).copyWith(fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
          ),
        if (shown.isNotEmpty) const SizedBox(width: 8),
        Expanded(child: Text(cap != null ? '${g.goingCount}/$cap going' : '${g.goingCount} going', maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle(color: C.ink).copyWith(fontWeight: FontWeight.w600))),
      ]),
      onTap: onTap,
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final String text;
  const _EmptyPanel({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        height: 110,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(24), boxShadow: C.shadowSoft),
        child: Text(text, style: metaStyle()),
      );
}

const _tints = [_peach, _lilac, _rose, _butter, _mint, _sky];

class _NeedRow extends StatelessWidget {
  final Need need;
  final VoidCallback onTap;
  const _NeedRow({required this.need, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final icon = categoryIcons[need.kind] ?? Icons.volunteer_activism_outlined;
    final tint = _tints[need.kind.hashCode.abs() % _tints.length];
    return TapScale(
      onTap: onTap,
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, size: 20, color: C.ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(need.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(14.5, w: 650, h: 1.3)),
              const SizedBox(height: 2),
              Text('${need.foundation.label} · ${need.pledgeCount} pledged', maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle()),
            ]),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, size: 20, color: C.inkSoft),
        ]),
      ),
    );
  }
}
