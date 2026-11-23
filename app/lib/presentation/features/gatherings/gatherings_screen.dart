import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/domain/entities/gathering.dart';
import 'package:by_the_people/presentation/features/foundations/foundations_screen.dart';
import 'package:by_the_people/presentation/features/gatherings/calendar_view.dart';
import 'package:by_the_people/presentation/features/gatherings/clubs_view.dart';
import 'package:by_the_people/presentation/features/gatherings/create_gathering_sheet.dart';
import 'package:by_the_people/presentation/features/gatherings/gathering_detail_screen.dart';
import 'package:by_the_people/presentation/features/gatherings/gathering_widgets.dart';
import 'package:by_the_people/presentation/features/gatherings/welfare_common.dart';
import 'package:by_the_people/presentation/providers/gathering_providers.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart';
import 'package:by_the_people/presentation/widgets/map.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Feed 2: gatherings, campaigns, calendar and clubs.
class GatheringsScreen extends ConsumerStatefulWidget {
  const GatheringsScreen({super.key});
  @override
  ConsumerState<GatheringsScreen> createState() => _GatheringsScreenState();
}

class _GatheringsScreenState extends ConsumerState<GatheringsScreen> with PollingState {
  int _tab = 0; // 0 upcoming, 1 campaigns, 2 calendar, 3 clubs
  String _when = 'upcoming'; // upcoming | mine | past (tab 0)
  String _sort = 'soon';
  String? _type;
  bool _map = false;

  static const _tabs = ['Upcoming', 'Campaigns', 'Calendar', 'Clubs'];

  @override
  void initState() {
    super.initState();
    startPolling(const Duration(seconds: 45), () => ref.read(welfareTickProvider.notifier).bump());
  }

  GatheringQ get _query => _tab == 1 ? ('proposed', _type, 'popular', null) : (_when, _type, _sort, null);

  static const _show = [
    ('soon', 'Soonest', Icons.schedule_rounded),
    ('near', 'Nearest', Icons.near_me_rounded),
    ('popular', 'Popular', Icons.local_fire_department_rounded),
    ('mine', 'My RSVPs', Icons.event_available_rounded),
    ('past', 'Past', Icons.history_rounded),
  ];

  String get _showKey => _when == 'mine' ? 'mine' : (_when == 'past' ? 'past' : _sort);
  bool get _filtered => _type != null || (_tab == 0 && _showKey != 'soon');

  Future<void> _openFilters() async {
    final r = await showFilterSheet(
      context,
      title: 'Filter',
      groups: [
        if (_tab == 0) FilterGroup('show', 'Show', [for (final o in _show) (o.$1, o.$2, o.$3)], selected: _showKey),
        FilterGroup('type', 'Type', [for (final e in gatheringTypes.entries) (e.key, e.value.label, e.value.icon)], selected: _type, allLabel: 'All types'),
      ],
    );
    if (r == null || !mounted) return;
    setState(() {
      _type = r['type'];
      if (_tab == 0) {
        final k = r['show'] ?? 'soon';
        if (k == 'mine' || k == 'past') {
          _when = k;
          _sort = 'soon';
        } else {
          _when = 'upcoming';
          _sort = k;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(locationProvider);
    final pad = MediaQuery.paddingOf(context);
    final showList = _tab == 0 || _tab == 1;
    final async = showList ? ref.watch(gatheringsProvider(_query)) : null;

    final actions = <Widget>[
      if (showList) TopBarAction(icon: Icons.tune_rounded, tooltip: 'Filter', dot: _filtered, onTap: _openFilters),
      if (showList) TopBarAction(icon: _map ? Icons.view_agenda_outlined : Icons.map_outlined, tooltip: _map ? 'List view' : 'Map view', onTap: () => setState(() => _map = !_map)),
      TopBarAction(
        icon: Icons.volunteer_activism_outlined,
        tooltip: 'Foundations',
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FoundationsScreen())),
      ),
      TopBarAction(icon: Icons.add_rounded, tooltip: 'Create', onTap: () => showCreateGatheringSheet(context)),
    ];

    if (_map && showList) {
      return Column(
        children: [
          WelfareHeaderBox(title: 'Events', actions: actions, tabs: _tabs, tabIndex: _tab, onTab: (i) => setState(() => _tab = i)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 84),
              child: async!.when(
                skipLoadingOnReload: true,
                loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: C.inkSoft)),
                error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(gatheringsProvider)),
                data: (items) => MarkersMapScreen.body(
                  items: [for (final g in items) gatheringMapItem(g)],
                  openLabel: 'View gathering',
                  onOpen: (ctx, m) => openGathering(ctx, (m.data! as Gathering).id),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      color: C.ember,
      edgeOffset: pad.top + 96,
      onRefresh: () async {
        await ref.read(locationProvider.notifier).refresh();
        await refreshWelfare(ref);
      },
      child: CustomScrollView(
        slivers: [
          WelfareHeaderSliver(title: 'Events', actions: actions, tabs: _tabs, tabIndex: _tab, onTab: (i) => setState(() => _tab = i)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (!loc.has && loc.error != null) ...[
                  InfoBanner(
                    icon: Icons.location_off_rounded,
                    text: 'Location is off. Turn it on to find gatherings near you.',
                    cta: 'Retry',
                    onTap: () => ref.read(locationProvider.notifier).refresh(),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_tab == 1) ...[
                  Text('Ideas waiting for backing. Vote for the ones you want to see happen.', style: ui(12.5, color: C.inkSoft)),
                  const SizedBox(height: 10),
                ],
                if (showList)
                  async!.when(
                    skipLoadingOnReload: true,
                    loading: () => const GatheringListSkeleton(),
                    error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(gatheringsProvider)),
                    data: (items) {
                      if (items.isEmpty) {
                        return EmptyState(
                          title: _tab == 1 ? 'No campaigns to back' : (_when == 'mine' ? 'No RSVPs yet' : 'Nothing scheduled'),
                          body: _tab == 1
                              ? 'Have an idea? Propose a campaign and let neighbours vote it into being.'
                              : 'Be the one who starts it. Tap + to create a gathering.',
                        );
                      }
                      final going = items.fold<int>(0, (a, x) => a + x.goingCount);
                      final mine = items.where((x) => x.goingByMe).length;
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Row(children: [
                              Expanded(child: WelfareStat(value: items.length, label: _tab == 1 ? 'Campaigns' : 'Events', icon: Icons.event_outlined)),
                              const SizedBox(width: 10),
                              Expanded(child: WelfareStat(value: going, label: 'Attending', icon: Icons.groups_rounded)),
                              const SizedBox(width: 10),
                              Expanded(child: WelfareStat(value: mine, label: 'Your RSVPs', icon: Icons.check_circle_outline_rounded)),
                            ]),
                          ),
                          for (var i = 0; i < items.length; i++)
                            Enter(
                              key: ValueKey('${items[i].id}-$_tab-$_when-$_sort-$_type'),
                              index: i,
                              child: GatheringCard(g: items[i], onTap: () => openGathering(context, items[i].id)),
                            ),
                        ],
                      );
                    },
                  )
                else if (_tab == 2)
                  const CalendarView()
                else
                  const ClubsView(),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
