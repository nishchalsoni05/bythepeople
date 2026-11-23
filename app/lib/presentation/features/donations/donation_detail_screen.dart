import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/domain/entities/donation.dart';
import 'package:by_the_people/presentation/features/donations/donation_widgets.dart';
import 'package:by_the_people/presentation/features/gatherings/welfare_common.dart';
import 'package:by_the_people/presentation/providers/donation_providers.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart';
import 'package:by_the_people/presentation/widgets/map.dart';
import 'package:by_the_people/presentation/widgets/media.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Opens the donation detail screen.
Future<void> openDonation(BuildContext context, int id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DonationDetailScreen(id: id)));

class DonationDetailScreen extends ConsumerStatefulWidget {
  const DonationDetailScreen({super.key, required this.id});
  final int id;
  @override
  ConsumerState<DonationDetailScreen> createState() => _DonationDetailScreenState();
}

class _DonationDetailScreenState extends ConsumerState<DonationDetailScreen> with PollingState {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Live status for the donor and rival claimers.
    startPolling(const Duration(seconds: 15), () => ref.invalidate(donationProvider(widget.id)));
  }

  Future<void> _run(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    await fn();
    if (mounted) setState(() => _busy = false);
  }

  DonationActions get _act => ref.read(donationActionsProvider);

  Future<void> _release(Donation d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.canvas,
        title: Text('Release this claim?', style: ui(18, w: 600)),
        content: Text('It goes back to the list so another foundation can take it.', style: ui(14, color: C.inkSoft)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep it', style: ui(14, w: 600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Release', style: ui(14, color: C.ember, w: 600)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      final r = await guarded(context, () => _act.release(d.id));
      if (r != null && mounted) showToast(context, 'Released back to the list', icon: Icons.undo_rounded);
    });
  }

  Future<void> _cancel(Donation d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.canvas,
        title: Text('Cancel this listing?', style: ui(18, w: 600)),
        content: Text(
          d.isClaimed
              ? '${d.claimedBy?.label ?? 'The foundation'} is on the way and will be told.'
              : 'It will no longer be visible to foundations.',
          style: ui(14, color: C.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep it', style: ui(14, w: 600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancel listing', style: ui(14, color: C.ember, w: 600)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      final r = await guarded(context, () => _act.cancel(d.id));
      if (r != null && mounted) showToast(context, 'Listing cancelled', icon: Icons.block_rounded);
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(donationProvider(widget.id));
    final me = ref.watch(authProvider).user;
    return Scaffold(
      body: PageBackdrop(
        child: async.when(
          skipLoadingOnReload: true,
          loading: () => const SafeArea(child: DetailSkeleton()),
          error: (e, _) => SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: WHeader(title: 'Surplus'),
                ),
                ErrorState(error: e, onRetry: () => ref.invalidate(donationProvider(widget.id))),
              ],
            ),
          ),
          data: (d) => _content(d, me?.id, me?.role ?? 'citizen', me?.verified ?? false),
        ),
      ),
    );
  }

  Widget _content(Donation fetched, int? meId, String role, bool verified) {
    final d = effectiveDonation(ref, fetched);
    final k = kindStyle(d.kind);
    final pad = MediaQuery.paddingOf(context);
    final isFoundation = role == 'foundation';
    final isDonor = d.isDonor(meId);

    return RefreshIndicator(
      color: C.ember,
      onRefresh: () async {
        ref.invalidate(donationProvider(d.id));
        await ref.read(donationProvider(d.id).future);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, pad.top + 4, 16, pad.bottom + 110),
        children: [
          WHeader(title: 'Surplus', trailing: Tag(donationStatusLabel(d.status))),
          const SizedBox(height: 8),
          if (d.media.isNotEmpty) ...[
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: d.media.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => NetPhoto(d.media[i], height: 200, width: d.media.length == 1 ? MediaQuery.sizeOf(context).width - 32 : 280, radius: 14, fallbackIcon: k.icon),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Tag(d.kindLabel, icon: k.icon),
              if (d.isFood && d.veg != 'na')
                Row(mainAxisSize: MainAxisSize.min, children: [VegDot(d.veg), const SizedBox(width: 5), Text(vegLabel(d.veg), style: ui(12.5))]),
              if (d.isActive) FreshnessChip(d),
            ],
          ),
          const SizedBox(height: 10),
          Text(d.title, style: ui(20, w: 650, h: 1.25)),
          if (d.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(d.description, style: ui(14, color: C.ink.withValues(alpha: 0.85), h: 1.5)),
          ],
          const SizedBox(height: 14),
          _Section(
            child: Column(
              children: [
                if (d.quantity.isNotEmpty) _Row(Icons.inventory_2_outlined, 'Quantity', d.quantity),
                if (d.servings != null) _Row(Icons.groups_outlined, 'Servings', '${d.servings} people'),
                if (d.preparedAt != null)
                  _Row(Icons.soup_kitchen_outlined, 'Prepared', '${whenLabel(d.preparedAt!)} (${relative(d.preparedAt!)})'),
                _Row(Icons.timer_outlined, 'Expires', '${fmtDateLong(d.expiresAt)}, ${fmtTime(d.expiresAt)}'),
                if (d.isFood && d.hygieneAck) _Row(Icons.clean_hands_rounded, 'Hygiene', 'Donor confirmed safe preparation'),
                _Row(
                  Icons.place_outlined,
                  'Pickup',
                  [if (d.address.isNotEmpty) d.address, if (d.distanceKm != null) km(d.distanceKm)].join(' · '),
                ),
                if (d.pickupNote.isNotEmpty) _Row(Icons.sticky_note_2_outlined, 'Note', d.pickupNote),
                PersonLine(d.donor, sub: 'Donor'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          MapPreview(lat: d.lat, lng: d.lng, label: d.title, height: 150),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: DecoratedBox(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: C.shadowSoft),
              child: TextButton.icon(
                onPressed: () => openInMaps(d.lat, d.lng, label: d.title, directions: true),
                icon: const Icon(Icons.directions_rounded, size: 18),
                label: const Text('Directions'),
                style: TextButton.styleFrom(
                  backgroundColor: C.surface,
                  foregroundColor: C.ink,
                  textStyle: ui(14, w: 650),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _StatusCard(d: d),
          if (d.proof != null) ...[
            const SizedBox(height: 12),
            _DeliveredCard(proof: d.proof!),
          ],
          if (d.distribution != null && d.proof == null) ...[
            const SizedBox(height: 12),
            _Section(
              color: C.mint.withValues(alpha: 0.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.favorite_rounded, size: 16, color: C.ember),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Helped ${d.distribution!.beneficiaries} people', style: ui(14, w: 600))),
                    ],
                  ),
                  if (d.distribution!.note.isNotEmpty) ...[const SizedBox(height: 6), Text(d.distribution!.note, style: ui(14, h: 1.45))],
                  if (d.distribution!.media.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 110,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: d.distribution!.media.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => NetPhoto(d.distribution!.media[i], height: 110, width: 150, radius: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          ..._actions(d, isFoundation, verified, isDonor),
          const SizedBox(height: 12),
          _Section(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: EngagementBar(
              likes: d.likeCount,
              comments: d.commentCount,
              shares: d.shareCount,
              liked: d.likedByMe,
              onLike: () => toggleDonationLike(context, ref, d),
              onComment: () => openDonationComments(context, ref, d),
              onShare: () => guarded(context, () => _act.share(d.id)),
            ),
          ),
          if (d.timeline.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text('Timeline', style: titleStyle())),
            _Section(
              child: Column(
                children: [for (var i = 0; i < d.timeline.length; i++) _TimelineRow(d.timeline[i], last: i == d.timeline.length - 1)],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _actions(Donation d, bool isFoundation, bool verified, bool isDonor) {
    final out = <Widget>[];
    if (isFoundation && !verified) {
      out.add(const SizedBox(height: 12));
      out.add(
        const InfoBanner(
          icon: Icons.hourglass_top_rounded,
          text: 'Your organisation is pending verification. You can browse donations, but only verified foundations can claim them.',
        ),
      );
    }
    if (isFoundation && verified) {
      if (d.canClaim) {
        out.add(const SizedBox(height: 12));
        out.add(
          PillButton(
            label: 'Claim this donation',
            icon: Icons.volunteer_activism_rounded,
            loading: _busy,
            onPressed: () => _run(() async {
              await claimFlow(context, ref, d);
            }),
          ),
        );
      } else if (d.claimedByMe) {
        out.add(const SizedBox(height: 12));
        if (d.isClaimed) {
          out.add(
            PillButton(
              label: 'Mark picked up',
              icon: Icons.local_shipping_rounded,
              loading: _busy,
              onPressed: () => _run(() async {
                final r = await guarded(context, () => _act.pickup(d.id));
                // ignore: use_build_context_synchronously
                if (r != null) cheer(context, r.rewards, 'Marked as picked up');
              }),
            ),
          );
          out.add(const SizedBox(height: 10));
          out.add(
            PillButton(
              label: 'Release claim',
              icon: Icons.undo_rounded,
              color: C.muted,
              fg: C.ink,
              onPressed: _busy ? null : () => _release(d),
            ),
          );
        } else if (d.isPickedUp) {
          out.add(
            PillButton(
              label: 'Mark distributed',
              icon: Icons.favorite_rounded,
              color: C.lime,
              fg: C.ink,
              loading: _busy,
              onPressed: () => _run(() async {
                await distributeFlow(context, ref, d);
              }),
            ),
          );
        }
      } else if (d.isClaimed && d.claimedBy != null) {
        out.add(const SizedBox(height: 12));
        out.add(InfoBanner(icon: Icons.lock_outline_rounded, text: '${d.claimedBy!.label} has claimed this one.'));
      }
    } else if (!isFoundation && d.isAvailable && !isDonor) {
      out.add(const SizedBox(height: 12));
      out.add(
        const InfoBanner(
          icon: Icons.verified_user_outlined,
          color: C.mint,
          text: 'Only verified foundations can claim donations, so food reaches people safely.',
        ),
      );
    }
    if (isDonor && (d.isAvailable || d.isClaimed)) {
      out.add(const SizedBox(height: 12));
      out.add(
        PillButton(
          label: 'Cancel my listing',
          icon: Icons.block_rounded,
          color: C.muted,
          fg: C.ember,
          onPressed: _busy ? null : () => _cancel(d),
        ),
      );
    }
    return out;
  }
}

/// Section card for the detail screen: white, shared two-layer shadow, 24dp radius, 16dp inset.
class _Section extends StatelessWidget {
  const _Section({required this.child, this.padding = const EdgeInsets.all(R.cardInset), this.color = C.surface});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(R.card), boxShadow: C.shadowSoft),
        child: child,
      );
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: R.unit + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: C.inkSoft),
          const SizedBox(width: 10),
          SizedBox(
            width: 74,
            child: Text(label, style: ui(12.5, color: C.inkSoft, h: 1.4)),
          ),
          Expanded(child: Text(value, style: ui(14, h: 1.35))),
        ],
      ),
    );
  }
}

/// Four-step tracker: listed, claimed, picked up, distributed. Shows the hold timer while claimed.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.d});
  final Donation d;

  static const _steps = [
    ('available', 'Listed', Icons.add_task_rounded),
    ('claimed', 'Claimed', Icons.volunteer_activism_rounded),
    ('picked_up', 'Picked up', Icons.local_shipping_rounded),
    ('distributed', 'Distributed', Icons.favorite_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final current = _steps.indexWhereStatus(d.status);
    return _Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < _steps.length; i++) ...[
                Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(color: i <= current ? C.ink : C.muted, shape: BoxShape.circle),
                        child: Icon(_steps[i].$3, size: 15, color: i <= current ? C.lime : C.inkSoft),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _steps[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ui(11, color: i <= current ? C.ink : C.inkSoft, w: 600),
                      ),
                    ],
                  ),
                ),
                if (i < _steps.length - 1)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(color: i < current ? C.ink : C.line, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ),
              ],
            ],
          ),
          if (d.isDead) ...[
            const SizedBox(height: 12),
            Tag(
              d.status == 'expired' ? 'Expired before it was claimed' : 'Cancelled by the donor',
              icon: Icons.info_outline_rounded,
              bg: C.muted,
            ),
          ],
          if (d.isClaimed && d.claimedBy != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.business_rounded, size: 18, color: C.inkSoft),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${d.claimedBy!.label}${d.etaAt != null ? ' arrives about ${fmtTime(d.etaAt!)}' : ''}',
                    style: ui(13.5, w: 650, h: 1.35),
                  ),
                ),
              ],
            ),
            if (d.lockExpiresAt != null) ...[
              const SizedBox(height: 8),
              LiveClock(
                until: d.lockExpiresAt!,
                builder: (_, left) => Text(
                  left > 0
                      ? 'Held for them for ${countdownText(left)} more. If not picked up it returns to the list.'
                      : 'Hold ended. Refreshing status.',
                  style: ui(12.5, color: C.inkSoft, h: 1.35),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

extension on List<(String, String, IconData)> {
  int indexWhereStatus(String s) {
    final i = indexWhere((e) => e.$1 == s);
    return i < 0 ? 0 : i;
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow(this.e, {required this.last});
  final DonationEvent e;
  final bool last;
  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 5),
                width: 10,
                height: 10,
                decoration: const BoxDecoration(color: C.ink, shape: BoxShape.circle),
              ),
              if (!last) Expanded(child: Container(width: 2, color: C.line)),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(donationStatusLabel(e.status), style: ui(14, w: 600)),
                  Text('${e.actor != null ? '${e.actor!.label} · ' : ''}${relative(e.createdAt)}', style: ui(12, color: C.inkSoft, w: 600)),
                  if (e.note != null && e.note!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(e.note!, style: ui(13, h: 1.4)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Proof of delivery: photos, the foundation's note and how many people were reached.
class _DeliveredCard extends StatelessWidget {
  const _DeliveredCard({required this.proof});
  final DonationProof proof;

  @override
  Widget build(BuildContext context) {
    final at = proof.at;
    return _Section(
      color: C.mint.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.check_circle_rounded, size: 18, color: C.ink),
            const SizedBox(width: 8),
            Expanded(child: Text('Delivered', style: ui(14, w: 600))),
            if (at != null) Text(fmtDate(at), style: ui(12.5, color: C.inkSoft, w: 600)),
          ]),
          if (proof.media.isNotEmpty) ...[
            const SizedBox(height: 10),
            MediaGallery(media: proof.media, height: 180, radius: 14, fallbackIcon: Icons.photo_outlined),
          ],
          if (proof.note.isNotEmpty) ...[const SizedBox(height: 10), Text(proof.note, style: ui(14, h: 1.45))],
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.groups_outlined, size: 18, color: C.inkSoft),
            const SizedBox(width: 8),
            Text('${proof.beneficiaries} ${proof.beneficiaries == 1 ? 'person' : 'people'} reached', style: ui(13.5, w: 600)),
          ]),
        ],
      ),
    );
  }
}
