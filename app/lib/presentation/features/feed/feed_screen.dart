import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/widgets/cards.dart';
import 'package:by_the_people/presentation/widgets/scope_bar.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';
import 'package:by_the_people/presentation/features/detail/issue_detail_screen.dart';
import 'package:by_the_people/presentation/features/notifications/notifications_screen.dart';
import 'package:by_the_people/presentation/features/activity/activity_screen.dart';
import 'package:by_the_people/presentation/features/neta/neta_screen.dart';
import 'package:by_the_people/presentation/widgets/layout.dart';
import 'package:by_the_people/presentation/widgets/map.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});
  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  int _phase = 0; // 0 issues, 1 events, 2 resolved
  String _sort = 'top';
  String? _category;
  static const _phases = ['issue', 'event', 'closed'];
  static const _sortLabels = {'top': 'Top', 'nearby': 'Nearby', 'new': 'Newest'};

  Future<void> _pickSort() async {
    final v = await showChoiceSheet<String>(
      context,
      title: 'Sort by',
      selected: _sort,
      options: const [
        ('top', 'Top', Icons.local_fire_department_outlined),
        ('nearby', 'Nearby', Icons.near_me_outlined),
        ('new', 'Newest', Icons.schedule_rounded),
      ],
    );
    if (v != null) setState(() => _sort = v);
  }

  Future<void> _pickCategory(List<CategoryInfo> cats) async {
    final v = await showChoiceSheet<String>(
      context,
      title: 'Category',
      selected: _category ?? '',
      options: [('', 'All categories', Icons.apps_rounded), for (final c in cats) (c.key, c.label, categoryIcons[c.key])],
    );
    if (v != null) setState(() => _category = v.isEmpty ? null : v);
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final loc = ref.watch(locationProvider);
    final online = ref.watch(connectionProvider);
    final phase = _phases[_phase];
    final sort = phase == 'closed' ? 'new' : _sort;
    final feed = ref.watch(feedProvider((phase, sort, _category, '')));
    final cats = ref.watch(metaProvider).asData?.value ?? <CategoryInfo>[];
    final first = (auth.user?.name ?? '').split(' ').first;
    final catLabel = _category == null ? 'Category' : cats.where((c) => c.key == _category).map((c) => c.label.split(' & ').first).firstOrNull ?? 'Category';
    final sub = online == false ? 'Offline · tap to retry' : (loc.has ? (loc.fallback ? 'Demo location' : 'Near you') : 'Locating…');
    final bottom = MediaQuery.of(context).padding.bottom + navClearance(context) + 12;

    return RefreshIndicator(
      color: C.ember,
      edgeOffset: 120,
      onRefresh: () async {
        await ref.read(locationProvider.notifier).refresh();
        ref.read(tickProvider.notifier).bump();
        await ref.read(feedProvider((phase, sort, _category, '')).future);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            pinned: false,
            backgroundColor: Colors.transparent,
            flexibleSpace: frostedBarBackground(),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            toolbarHeight: 52,
            automaticallyImplyLeading: false,
            titleSpacing: 0,
            title: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: online == false ? () => ref.read(connectionProvider.notifier).check() : null,
              child: AppTopBar(
                title: first.isEmpty ? 'By the People' : 'Hi, $first',
                subtitle: sub,
                leading: GestureDetector(
                  onTap: () => ref.read(shellTabProvider.notifier).go(3),
                  child: Avatar(auth.user?.asPerson ?? Person(0, '?', 200), size: 34),
                ),
                actions: [
                  TopBarAction(
                    icon: Icons.map_outlined,
                    tooltip: 'Map',
                    onTap: () {
                      final issues = feed.asData?.value ?? const <Issue>[];
                      _push(MarkersMapScreen(
                        title: 'Issues near you',
                        items: [
                          for (final i in issues)
                            MapItem(id: '${i.id}', title: i.title, lat: i.lat, lng: i.lng, subtitle: i.categoryLabel, data: i),
                        ],
                        onOpen: (ctx, m) => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => IssueDetailScreen(id: (m.data as Issue).id))),
                      ));
                    },
                  ),
                  TopBarAction(
                    icon: Icons.notifications_none_rounded,
                    tooltip: 'Notifications',
                    dot: auth.unread > 0,
                    onTap: () => _push(const NotificationsScreen()),
                  ),
                  PopupMenuButton<int>(
                    tooltip: 'More',
                    icon: const Icon(Icons.more_vert_rounded, size: 22, color: C.ink),
                    padding: EdgeInsets.zero,
                    color: C.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (v) => _push(v == 0 ? const PushedPage(title: 'Leaders', child: NetaScreen()) : const PushedPage(title: 'My activity', child: ActivityScreen())),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 0, child: Row(children: [const Icon(Icons.shield_moon_outlined, size: 18), const SizedBox(width: 10), Text('Leaders', style: ui(14))])),
                      PopupMenuItem(value: 1, child: Row(children: [const Icon(Icons.history_rounded, size: 18), const SizedBox(width: 10), Text('My activity', style: ui(14))])),
                    ],
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(40 + 6 + 38 + 6),
              child: Column(children: [
                CompactTabs(labels: const ['Issues', 'In action', 'Resolved'], index: _phase, onChanged: (i) => setState(() => _phase = i)),
                const SizedBox(height: 6),
                FilterChipRow(children: [
                  const ScopeChip(),
                  if (_phase != 2) FilterButton(icon: Icons.swap_vert_rounded, label: _sortLabels[_sort]!, onTap: _pickSort),
                  FilterButton(icon: Icons.tune_rounded, label: catLabel, active: _category != null, onTap: () => _pickCategory(cats)),
                ]),
                const SizedBox(height: 6),
              ]),
            ),
          ),
          if (!loc.has && loc.error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: _Banner(text: 'Location is off. Turn it on to support, report and join.', onTap: () => ref.read(locationProvider.notifier).refresh()),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(12, 2, 12, bottom),
            sliver: SliverToBoxAdapter(
              child: feed.when(
                skipLoadingOnReload: true,
                loading: () => const IssueListSkeleton(),
                error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(feedProvider)),
                data: (items) {
                  if (items.isEmpty) {
                    return EmptyState(
                      title: _phase == 0 ? 'All quiet here' : _phase == 1 ? 'Nothing in action yet' : 'Nothing resolved yet',
                      body: _phase == 0 ? 'No open issues match. Spotted a problem? Tap + to report it.' : _phase == 1 ? 'Issues become events once 5 neighbours support them.' : 'Resolved issues show up after neighbours verify the fix.',
                    );
                  }
                  return Column(children: [
                    for (final i in items) IssueCard(key: ValueKey('${i.id}-$phase'), issue: i, onTap: () => _push(IssueDetailScreen(id: i.id))),
                  ]);
                },
              ),
            ),
          ),
        ],
      ),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: C.ember.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.ember.withValues(alpha: 0.25))),
          child: Row(children: [
            const Icon(Icons.location_off_outlined, size: 18, color: C.ember),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: ui(13, w: 550))),
            Text('Retry', style: ui(13, color: C.ember, w: 650)),
          ]),
        ),
      );
}
