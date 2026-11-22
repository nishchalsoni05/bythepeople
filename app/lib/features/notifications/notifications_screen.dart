import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/state.dart';
import '../../core/tokens.dart';
import '../../core/widgets/ui.dart';
import '../detail/issue_detail_screen.dart';

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
      await ref.read(apiProvider).post('/notifications/read', {});
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
        _ => Icons.notifications_rounded,
      };

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
              Text('Alerts', style: ui(20, w: 750)),
            ]),
            const SizedBox(height: 18),
            async.when(
              loading: () => const LoadingOrb(),
              error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(notificationsProvider)),
              data: (items) => items.isEmpty
                  ? const EmptyState(title: 'You are all caught up', body: 'Alerts about events near you and your reports show up here.')
                  : Column(children: [
                      for (final n in items)
                        TapScale(
                          onTap: n.issueId == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => IssueDetailScreen(id: n.issueId!))),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _unreadAtOpen.contains(n.id) ? const Color(0xFFFFEBDD) : C.surface,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: softShadow,
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
