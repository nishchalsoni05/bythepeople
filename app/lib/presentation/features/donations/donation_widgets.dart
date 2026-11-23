import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/domain/entities/donation.dart';
import 'package:by_the_people/presentation/features/gatherings/welfare_common.dart';
import 'package:by_the_people/presentation/providers/donation_providers.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart' show authProvider;
import 'package:by_the_people/presentation/providers/gathering_providers.dart' show Done;
import 'package:by_the_people/presentation/widgets/map.dart' show MapItem;
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

class DonationKindStyle {
  final IconData icon;
  final Color a, b;
  final String label;
  const DonationKindStyle(this.icon, this.a, this.b, this.label);
}

const donationKinds = <String, DonationKindStyle>{
  'food': DonationKindStyle(Icons.restaurant_rounded, Color(0xFFFFE6A8), Color(0xFFFFB347), 'Food'),
  'clothes': DonationKindStyle(Icons.checkroom_rounded, Color(0xFFD8D0F0), Color(0xFFA99BD6), 'Clothes'),
  'bottles': DonationKindStyle(Icons.local_drink_rounded, Color(0xFFD6ECFA), Color(0xFF8CC8F0), 'Bottles'),
  'books': DonationKindStyle(Icons.menu_book_rounded, Color(0xFFFAD3D8), Color(0xFFF4B8C0), 'Books'),
  'toys': DonationKindStyle(Icons.toys_rounded, Color(0xFFE4EEB8), Color(0xFFC8DB7A), 'Toys'),
  'essentials': DonationKindStyle(Icons.shopping_basket_rounded, Color(0xFFD9F0E3), Color(0xFFA6D9B6), 'Essentials'),
  'other': DonationKindStyle(Icons.inventory_2_rounded, Color(0xFFE6E4DE), Color(0xFFCFCBC0), 'Other'),
};

DonationKindStyle kindStyle(String kind) => donationKinds[kind] ?? donationKinds['other']!;

const _statusText = {
  'available': 'Available',
  'claimed': 'Claimed',
  'picked_up': 'Picked up',
  'distributed': 'Distributed',
  'expired': 'Expired',
  'cancelled': 'Cancelled',
};

String donationStatusLabel(String s) => _statusText[s] ?? s;

({Color bg, Color fg, String label}) freshnessLook(String f) => switch (f) {
  'critical' => (bg: C.ember, fg: Colors.white, label: 'Critical'),
  'soon' => (bg: const Color(0xFFFFE9CC), fg: const Color(0xFF8A4B00), label: 'Use soon'),
  'expired' => (bg: C.muted, fg: C.inkSoft, label: 'Expired'),
  _ => (bg: const Color(0xFFE3F3E8), fg: const Color(0xFF1E6B3E), label: 'Fresh'),
};

/// "2h 05m", "12:41" (under an hour), "Expired". [ms] is the time left.
String countdownText(int ms) {
  if (ms <= 0) return 'Expired';
  final totalSec = ms ~/ 1000;
  final h = totalSec ~/ 3600;
  final m = (totalSec % 3600) ~/ 60;
  final s = totalSec % 60;
  if (h >= 24) return '${h ~/ 24}d ${h % 24}h';
  if (h >= 1) return '${h}h ${m.toString().padLeft(2, '0')}m';
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// Ticks once a second while under an hour is left (every 20 s otherwise) and stops itself on dispose.
class LiveClock extends StatefulWidget {
  const LiveClock({super.key, required this.until, required this.builder});
  final int until;
  final Widget Function(BuildContext context, int msLeft) builder;
  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  Timer? _t;
  int _left = 0;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _left = widget.until - _now;
    _schedule();
  }

  void _schedule() {
    _t?.cancel();
    if (_left <= 0) return;
    final fast = _left < 3600000;
    _t = Timer(Duration(seconds: fast ? 1 : 20), () {
      if (!mounted) return;
      setState(() => _left = widget.until - _now);
      _schedule();
    });
  }

  @override
  void didUpdateWidget(LiveClock old) {
    super.didUpdateWidget(old);
    if (old.until != widget.until) {
      _left = widget.until - _now;
      _schedule();
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _left);
}

/// Freshness pill with a live countdown, driven by the clock rather than the last fetch.
class FreshnessChip extends StatelessWidget {
  const FreshnessChip(this.d, {super.key, this.big = false});
  final Donation d;
  final bool big;

  @override
  Widget build(BuildContext context) {
    if (d.isDead || d.isDone) return const SizedBox.shrink();
    return LiveClock(
      until: d.expiresAt,
      builder: (context, left) {
        final f = left <= 0 ? 'expired' : d.liveFreshness();
        final look = freshnessLook(f);
        final text = f == 'expired'
            ? 'Expired'
            : (d.isFood ? '${look.label} · ${countdownText(left)}' : 'Lists for ${countdownText(left)}');
        return Container(
          padding: EdgeInsets.symmetric(horizontal: big ? 10 : 8, vertical: big ? 6 : 4),
          decoration: BoxDecoration(color: look.bg, borderRadius: BorderRadius.circular(8)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                f == 'critical' ? Icons.local_fire_department_rounded : (f == 'expired' ? Icons.timer_off_rounded : Icons.timer_outlined),
                size: big ? 15 : 12,
                color: look.fg,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, key: const Key('freshness-text'), style: ui(big ? 13 : 12, color: look.fg, w: 600)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class VegDot extends StatelessWidget {
  const VegDot(this.veg, {super.key});
  final String veg;
  @override
  Widget build(BuildContext context) {
    final color = veg == 'veg' ? const Color(0xFF2E9E57) : (veg == 'nonveg' ? const Color(0xFFD8452B) : C.amber);
    if (veg == 'na') return const SizedBox.shrink();
    return Container(
      width: 16,
      height: 16,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

String vegLabel(String v) => switch (v) {
  'veg' => 'Vegetarian',
  'nonveg' => 'Non-veg',
  'mixed' => 'Veg and non-veg',
  _ => '',
};

extension DonationCopy on Donation {
  Donation copyWith({bool? likedByMe, int? likeCount, int? commentCount, String? status, bool? canClaim, bool? claimedByMe, Claimer? claimedBy, int? etaAt}) => Donation(
    id: id, kind: kind, kindLabel: kindLabel, title: title, description: description, quantity: quantity, servings: servings,
    veg: veg, preparedAt: preparedAt, expiresAt: expiresAt, expiresInMinutes: expiresInMinutes, freshness: freshness,
    lat: lat, lng: lng, address: address, pickupNote: pickupNote, media: media, hygieneAck: hygieneAck, donor: donor,
    status: status ?? this.status, claimedBy: claimedBy ?? this.claimedBy, claimedAt: claimedAt, etaAt: etaAt ?? this.etaAt,
    lockExpiresAt: lockExpiresAt, pickedUpAt: pickedUpAt, distributedAt: distributedAt, distribution: distribution,
    distanceKm: distanceKm, canClaim: canClaim ?? this.canClaim, claimedByMe: claimedByMe ?? this.claimedByMe,
    likeCount: likeCount ?? this.likeCount, likedByMe: likedByMe ?? this.likedByMe, commentCount: commentCount ?? this.commentCount,
    shareCount: shareCount, shareText: shareText, publicUrl: publicUrl, timeline: timeline,
  );
}

class DonationOverlay extends OptimisticStore<Donation> {}

final donationOverlayProvider = NotifierProvider<DonationOverlay, Map<int, (Donation, int)>>(DonationOverlay.new);

/// [d] with any in-flight or just-confirmed optimistic change applied.
Donation effectiveDonation(WidgetRef ref, Donation d) {
  ref.watch(donationOverlayProvider);
  return ref.read(donationOverlayProvider.notifier).fresh(d.id) ?? d;
}

final _inflight = <String>{};

Future<void> toggleDonationLike(BuildContext context, WidgetRef ref, Donation d) async {
  final tag = 'like:${d.id}';
  if (_inflight.contains(tag)) return;
  _inflight.add(tag);
  final store = ref.read(donationOverlayProvider.notifier);
  final actions = ref.read(donationActionsProvider);
  final before = store.fresh(d.id) ?? d;
  final on = !before.likedByMe;
  final r = await optimisticRun<Done<Donation>>(
    context,
    apply: () => store.put(d.id, before.copyWith(likedByMe: on, likeCount: (before.likeCount + (on ? 1 : -1)).clamp(0, 1 << 30))),
    rollback: () => store.put(d.id, before),
    run: () => actions.like(d.id, on: on),
    failMessage: 'Could not update your like. Please try again.',
  );
  _inflight.remove(tag);
  if (r != null) store.put(d.id, r.value);
}

Future<void> openDonationComments(BuildContext context, WidgetRef ref, Donation d) {
  final actions = ref.read(donationActionsProvider);
  final store = ref.read(donationOverlayProvider.notifier);
  return showCommentsSheet(
    context,
    comments: donationCommentsProvider(d.id),
    onSend: (b) async {
      await actions.addComment(d.id, b);
      final cur = store.fresh(d.id) ?? d;
      store.put(d.id, cur.copyWith(commentCount: cur.commentCount + 1));
    },
  );
}

/// Marker for maps, coloured by donation kind.
MapItem donationMapItem(Donation d) {
  final k = kindStyle(d.kind);
  return MapItem(
    id: '${d.id}',
    title: d.title,
    lat: d.lat,
    lng: d.lng,
    typeLabel: d.kindLabel,
    subtitle: [if (d.quantity.isNotEmpty) d.quantity, donationStatusLabel(d.status)].join(' · '),
    color: Color.lerp(k.b, C.ink, 0.3)!,
    icon: k.icon,
    data: d,
  );
}

class DonationCard extends ConsumerWidget {
  const DonationCard({super.key, required this.d, required this.onTap, this.onClaim});
  final Donation d;
  final VoidCallback onTap;

  /// Shown as a quick button when the viewer can claim.
  final VoidCallback? onClaim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = effectiveDonation(ref, this.d);
    final k = kindStyle(d.kind);
    final meta = <String>[if (d.quantity.isNotEmpty) d.quantity, if (d.servings != null) '${d.servings} servings'].join(' · ');
    final badge = d.isActive && d.isAvailable ? FreshnessChip(d) : CoverBadge(donationStatusLabel(d.status));
    return FeedCardShell(
      onTap: onTap,
      dim: d.isDead,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverImage(media: d.media, icon: k.icon, height: d.media.isEmpty ? 84 : 150, badge: badge),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PersonLine(d.donor, size: 22, sub: d.claimedBy != null ? 'Claimed by ${d.claimedBy!.label}' : null),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (d.isFood && d.veg != 'na') Padding(padding: const EdgeInsets.only(top: 3, right: 8), child: VegDot(d.veg)),
                    Expanded(child: Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(16, w: 600, h: 1.3))),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    InfoChip(k.icon, d.kindLabel),
                    if (meta.isNotEmpty) InfoChip(Icons.inventory_2_outlined, meta),
                    if (d.address.isNotEmpty || d.distanceKm != null)
                      InfoChip(Icons.place_outlined, [if (d.address.isNotEmpty) d.address, if (d.distanceKm != null) km(d.distanceKm)].join(' · ')),
                  ],
                ),
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 8), child: Divider(height: 1, color: C.line)),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            child: Row(
              children: [
                ActionBtn(
                  icon: d.likedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  count: d.likeCount,
                  color: d.likedByMe ? C.ember : null,
                  onTap: () => toggleDonationLike(context, ref, d),
                ),
                ActionBtn(icon: Icons.chat_bubble_outline_rounded, count: d.commentCount, onTap: () => openDonationComments(context, ref, d)),
                const Spacer(),
                if (onClaim != null && d.canClaim)
                  GestureDetector(
                    onTap: onClaim,
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.volunteer_activism_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text('Claim', style: ui(13, color: Colors.white, w: 600)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DonationListSkeleton extends StatelessWidget {
  const DonationListSkeleton({super.key, this.count = 3});
  final int count;
  @override
  Widget build(BuildContext context) => Skeleton(
    child: Column(
      children: [
        for (var i = 0; i < count; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14)),
            clipBehavior: Clip.antiAlias,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 140, radius: 0),
                Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 110, height: 12),
                      SizedBox(height: 10),
                      SkeletonBox(height: 16),
                      SizedBox(height: 8),
                      SkeletonBox(width: 150, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Actions shared by the card, the detail screen and the dashboard.

/// Asks for an ETA and claims the donation. Shows it as claimed straight away and rolls back if it fails
/// (including the race where someone else got there first).
Future<bool> claimFlow(BuildContext context, WidgetRef ref, Donation d) async {
  final eta = await showWelfareSheet<int>(context, builder: (_) => _ClaimSheet(d: d));
  if (eta == null || !context.mounted) return false;
  final store = ref.read(donationOverlayProvider.notifier);
  final actions = ref.read(donationActionsProvider);
  final me = ref.read(authProvider).user;
  final before = store.fresh(d.id) ?? d;
  store.put(
    d.id,
    before.copyWith(
      status: 'claimed',
      canClaim: false,
      claimedByMe: true,
      etaAt: DateTime.now().add(Duration(minutes: eta)).millisecondsSinceEpoch,
      claimedBy: me == null ? null : Claimer(me.id, me.name, me.orgName, 160),
    ),
  );
  try {
    final r = await actions.claim(d.id, eta);
    store.put(d.id, r.value);
    // ignore: use_build_context_synchronously
    cheer(context, r.rewards, 'Claimed. The donor has been told you are on the way.');
    return true;
  } catch (e) {
    store.put(d.id, before);
    if (!context.mounted) return false;
    if (e is ApiException && e.code == 'ALREADY_CLAIMED') {
      final who = e.extra['claimedBy'];
      final name = who is Map ? (who['orgName'] ?? who['name']) : null;
      showToast(context, name == null ? 'Someone else claimed this first.' : '$name claimed this first.', error: true, icon: Icons.flash_on_rounded);
      ref.invalidate(donationProvider(d.id));
    } else if (e is ApiException && e.code == 'NOT_VERIFIED') {
      showToast(context, 'Your organisation is pending verification, so you cannot claim yet.', error: true);
    } else {
      toastError(context, e, fallback: 'Could not claim this donation. Please try again.');
    }
    return false;
  }
}

class _ClaimSheet extends StatefulWidget {
  const _ClaimSheet({required this.d});
  final Donation d;
  @override
  State<_ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends State<_ClaimSheet> {
  static const _options = [15, 30, 45, 60, 90, 120];
  int? _eta;

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final left = ((d.expiresAt - DateTime.now().millisecondsSinceEpoch) / 60000).floor();
    final fits = _options.where((m) => m < left).toList();
    _eta ??= fits.isEmpty ? null : fits.first;
    final arrive = _eta == null ? null : DateTime.now().add(Duration(minutes: _eta!)).millisecondsSinceEpoch;
    return SheetBody(
      title: 'Claim this donation',
      subtitle: 'Tell ${d.donor.label} when you will arrive. You will hold it for 45 minutes at least.',
      children: [
        Text('How soon can you pick it up?', style: ui(12.5, color: C.inkSoft, w: 600)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in _options)
              Opacity(
                opacity: m < left ? 1 : 0.35,
                child: AppChip(
                  label: m < 60 ? '$m min' : '${m ~/ 60}h${m % 60 == 0 ? '' : ' ${m % 60}m'}',
                  selected: _eta == m,
                  onTap: m < left ? () => setState(() => _eta = m) : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (arrive != null)
          Text('You will arrive around ${fmtTime(arrive)}', style: ui(13.5, w: 600))
        else
          Text('This is expiring too soon to reach in time.', style: ui(13.5, color: C.ember, w: 650)),
        const SizedBox(height: 20),
        PillButton(label: 'Confirm claim', icon: Icons.check_rounded, onPressed: _eta == null ? null : () => Navigator.pop(context, _eta)),
      ],
    );
  }
}

/// Collects the distribution report (note, beneficiaries, proof photo) and submits it.
Future<bool> distributeFlow(BuildContext context, WidgetRef ref, Donation d) async {
  final note = TextEditingController();
  final people = TextEditingController();
  var media = <String>[];
  final ok = await showWelfareSheet<bool>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => SheetBody(
        title: 'Mark distributed',
        subtitle: 'Close the loop with the donor: what happened and who it helped.',
        children: [
          WField(
            label: 'Note',
            controller: note,
            lines: 3,
            hint: 'Where it went, who received it',
            maxLength: 400,
            fieldKey: const Key('dist-note'),
          ),
          const SizedBox(height: 14),
          WField(
            label: 'People helped',
            controller: people,
            hint: 'e.g. 40',
            keyboard: TextInputType.number,
            maxLength: 6,
            fieldKey: const Key('dist-people'),
          ),
          const SizedBox(height: 14),
          Text('Proof photo', style: ui(12.5, color: C.inkSoft, w: 600)),
          const SizedBox(height: 8),
          PhotoPicker(urls: media, onChanged: (v) => setState(() => media = v), max: 3, label: 'Add proof'),
          const SizedBox(height: 20),
          PillButton(label: 'Submit report', icon: Icons.check_rounded, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    ),
  );
  final text = note.text.trim();
  final n = int.tryParse(people.text.trim());
  note.dispose();
  people.dispose();
  if (ok != true || !context.mounted) return false;
  if (text.isEmpty || n == null || n <= 0) {
    showToast(context, 'Add a note and how many people were helped.', error: true);
    return false;
  }
  final r = await guarded(context, () => ref.read(donationActionsProvider).distribute(d.id, note: text, beneficiaries: n, media: media));
  // ignore: use_build_context_synchronously
  if (r != null) cheer(context, r.rewards, 'Distribution recorded. Thank you!', confetti: true);
  return r != null;
}
