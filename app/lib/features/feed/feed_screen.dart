import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models.dart';
import '../../core/state.dart';
import '../../core/tokens.dart';
import '../../core/widgets/cards.dart';
import '../../core/widgets/scope_bar.dart';
import '../../core/widgets/ui.dart';
import '../detail/issue_detail_screen.dart';
import '../notifications/notifications_screen.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});
  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  int _phase = 0; // 0 issues, 1 events, 2 resolved
  String _sort = 'nearby';
  String? _category;
  static const _phases = ['issue', 'event', 'closed'];

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final loc = ref.watch(locationProvider);
    final phase = _phases[_phase];
    final sort = phase == 'event' ? 'soon' : (phase == 'closed' ? 'new' : _sort);
    final feed = ref.watch(feedProvider((phase, sort, _category, '')));
    final cats = ref.watch(metaProvider).asData?.value ?? [];
    final first = auth.user?.name.split(' ').first ?? '';

    return RefreshIndicator(
      color: C.ember,
      onRefresh: () async {
        await ref.read(locationProvider.notifier).refresh();
        ref.read(tickProvider.notifier).bump();
        await ref.read(feedProvider((phase, sort, _category, '')).future);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 140),
        children: [
          Row(children: [
            Avatar(auth.user?.asPerson ?? Person(0, '?', 200), size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hi, $first', style: ui(16, w: 700)),
                const SizedBox(height: 2),
                Row(children: [
                  _ConnDot(ref.watch(connectionProvider), onTap: () => ref.read(connectionProvider.notifier).check()),
                  Text('  ·  ', style: ui(12, color: C.inkSoft)),
                  Icon(Icons.near_me_rounded, size: 12, color: loc.has ? C.ember : C.inkSoft),
                  const SizedBox(width: 3),
                  Text(loc.has ? (loc.fallback ? 'Demo spot' : 'Near you') : 'Locating…', style: ui(12, color: C.inkSoft, w: 600)),
                ]),
              ]),
            ),
            CircleBtn(
              icon: Icons.notifications_none_rounded,
              size: 42,
              dot: auth.unread > 0,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
            ),
          ]),
          const SizedBox(height: 18),
          const ScopeBar(),
          const SizedBox(height: 16),
          SegmentedToggle(labels: const ['Issues', 'Events', 'Resolved'], index: _phase, onChanged: (i) => setState(() => _phase = i)),
          const SizedBox(height: 14),
          if (!loc.has && loc.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _Banner(text: 'Location is off. Turn it on to support, report and join.', onTap: () => ref.read(locationProvider.notifier).refresh()),
            ),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              if (_phase == 0)
                for (final s in const [('nearby', 'Nearby', Icons.near_me_rounded), ('severity', 'Severity', Icons.local_fire_department_rounded), ('new', 'Newest', Icons.schedule_rounded)])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppChip(label: s.$2, icon: s.$3, selected: _sort == s.$1, onTap: () => setState(() => _sort = s.$1)),
                  ),
              if (_phase == 0) Container(width: 1, margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8), color: C.line),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AppChip(label: 'All', selected: _category == null, onTap: () => setState(() => _category = null)),
              ),
              for (final c in cats)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AppChip(
                    label: c.label.split(' & ').first,
                    icon: categoryIcons[c.key],
                    selected: _category == c.key,
                    onTap: () => setState(() => _category = _category == c.key ? null : c.key),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 18),
          feed.when(
            loading: () => const LoadingOrb(),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(feedProvider)),
            data: (items) {
              if (items.isEmpty) {
                return EmptyState(
                  title: _phase == 0 ? 'All quiet here' : _phase == 1 ? 'No events yet' : 'Nothing resolved yet',
                  body: _phase == 0 ? 'No open issues match. Spotted a problem? Tap + to report it.' : _phase == 1 ? 'Issues become events once 5 neighbours support them.' : 'Resolved issues show up after neighbours verify the fix.',
                );
              }
              return Column(children: [
                for (var i = 0; i < items.length; i++)
                  _Enter(
                    key: ValueKey('${items[i].id}-$phase'),
                    index: i,
                    child: IssueCard(
                      issue: items[i],
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => IssueDetailScreen(id: items[i].id))),
                    ),
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

class _ConnDot extends StatelessWidget {
  final bool? ok;
  final VoidCallback onTap;
  const _ConnDot(this.ok, {required this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = ok == null ? C.inkSoft : (ok! ? const Color(0xFF34B26B) : C.ember);
    final label = ok == null ? 'Connecting' : (ok! ? 'Connected' : 'Offline · tap to retry');
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(duration: const Duration(milliseconds: 300), width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: ui(12, color: ok == false ? C.ember : C.inkSoft, w: 600)),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _Banner({required this.text, required this.onTap});
  @override
  Widget build(BuildContext context) => TapScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFFFE6D5), borderRadius: BorderRadius.circular(24)),
          child: Row(children: [
            const Icon(Icons.location_off_rounded, color: C.ember),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: ui(13, w: 600))),
            Text('Retry', style: ui(13, color: C.ember, w: 750)),
          ]),
        ),
      );
}

/// Staggered fade/slide-in for list items.
class _Enter extends StatelessWidget {
  final int index;
  final Widget child;
  const _Enter({super.key, required this.index, required this.child});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + (index.clamp(0, 6)) * 70),
      curve: Curves.easeOutCubic,
      builder: (context, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 24), child: c)),
      child: child,
    );
  }
}
