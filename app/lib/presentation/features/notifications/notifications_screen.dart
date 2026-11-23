import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/app/di.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/presentation/features/detail/issue_detail_screen.dart';
import 'package:by_the_people/presentation/features/donations/donation_detail_screen.dart';
import 'package:by_the_people/presentation/features/gatherings/gathering_detail_screen.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  Set<int> _unreadAtOpen = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final items = await ref.read(notificationsProvider.future);
      if (!mounted) return;
      setState(() => _unreadAtOpen = items.where((n) => !n.read).map((n) => n.id).toSet());
      await ref.read(notificationRepositoryProvider).markAllRead();
      unawaited_(ref.read(authProvider.notifier).refreshMe());
    });
  }

  void unawaited_(Future<void> f) => f.catchError((_) {});

  IconData _icon(String t) => switch (t) {
        'event_nearby' => Icons.volunteer_activism_rounded,
        'event_created' => Icons.bolt_rounded,
        'verify_request' => Icons.fact_check_rounded,
        'event_closed' => Icons.verified_rounded,
        'event_reopened' => Icons.replay_rounded,
        'event_scheduled' => Icons.event_rounded,
        'routed' => Icons.account_balance_rounded,
        'escalated' => Icons.trending_up_rounded,
        'authority_update' => Icons.account_balance_rounded,
        'rsvp' => Icons.how_to_reg_rounded,
        'gathering_cancelled' => Icons.event_busy_rounded,
        'gathering_reminder' => Icons.alarm_rounded,
        'donation' => Icons.volunteer_activism_rounded,
        'donation_claimed' => Icons.handshake_rounded,
        'donation_picked_up' => Icons.local_shipping_rounded,
        'donation_distributed' => Icons.favorite_rounded,
        'donation_released' => Icons.undo_rounded,
        'foundation_verified' => Icons.verified_rounded,
        'comment' => Icons.mode_comment_rounded,
        _ => Icons.notifications_rounded,
      };

  /// Opens the thing the alert is about: an issue, a gathering or a donation.
  void _open(AppNotification n) {
    final id = n.refId;
    if (id == null) return;
    switch (n.refType) {
      case 'gathering':
        openGathering(context, id);
      case 'donation':
        openDonation(context, id);
      default:
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => IssueDetailScreen(id: id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationsProvider);
    final pad = MediaQuery.of(context).padding;
    return Scaffold(
      body: PageBackdrop(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, pad.top + 8, 16, 40),
          children: [
            Row(children: [
              CircleBtn(icon: Icons.arrow_back_rounded, size: 42, onTap: () => Navigator.pop(context)),
              const SizedBox(width: 14),
              Text('Alerts', style: ui(20, w: 650)),
            ]),
            const SizedBox(height: 18),
            async.when(
              skipLoadingOnReload: true,
              loading: () => const RowListSkeleton(),
              error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(notificationsProvider)),
              data: (items) => items.isEmpty
                  ? const EmptyState(title: 'You are all caught up', body: 'Alerts about your needs, events and donations show up here.')
                  : Column(children: [
                      for (final n in items)
                        TapScale(
                          onTap: n.refId == null ? null : () => _open(n),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _unreadAtOpen.contains(n.id) ? const Color(0xFFFFEBDD) : C.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: C.line),
                            ),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                width: 42, height: 42,
                                decoration: BoxDecoration(color: _unreadAtOpen.contains(n.id) ? C.ember : C.muted, shape: BoxShape.circle),
                                child: Icon(_icon(n.type), size: 20, color: _unreadAtOpen.contains(n.id) ? Colors.white : C.ink),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(n.title, style: ui(14.5, w: 750)),
                                  if (n.body != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(n.body!, style: ui(13, color: C.inkSoft, h: 1.4))),
                                  const SizedBox(height: 4),
                                  Text(relative(n.createdAt), style: ui(11.5, color: C.inkSoft)),
                                ]),
                              ),
                            ]),
                          ),
                        ),
                    ]),
            ),
          ],
        ),
      ),
    );
  }
}
