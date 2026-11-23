import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/domain/entities/donation.dart';
import 'package:by_the_people/presentation/features/donations/create_donation_sheet.dart';
import 'package:by_the_people/presentation/features/donations/donation_detail_screen.dart';
import 'package:by_the_people/presentation/features/donations/donation_widgets.dart';
import 'package:by_the_people/presentation/features/foundations/foundation_dashboard.dart';
import 'package:by_the_people/presentation/features/foundations/foundations_screen.dart';
import 'package:by_the_people/presentation/features/gatherings/welfare_common.dart';
import 'package:by_the_people/presentation/providers/donation_providers.dart';
import 'package:by_the_people/presentation/providers/gathering_providers.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart';
import 'package:by_the_people/presentation/widgets/map.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Feed 3: surplus donations. Citizens browse and list; verified foundations claim.
/// With [myClaims] it shows the foundation's own claims (or a donor's own listings).
class DonationsScreen extends ConsumerStatefulWidget {
  const DonationsScreen({super.key, this.myClaims = false});
  final bool myClaims;
  @override
  ConsumerState<DonationsScreen> createState() => _DonationsScreenState();
}

class _DonationsScreenState extends ConsumerState<DonationsScreen> with PollingState {
  int _tab = 0;
  String? _kind;
  String _sort = 'expiring';
  bool _map = false;

  @override
  void initState() {
    super.initState();
    // Keeps freshness and claim status current without the user pulling.
    startPolling(const Duration(seconds: 30), () => ref.read(welfareTickProvider.notifier).bump());
  }

  bool get _mineMode => widget.myClaims;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).user;
    final role = me?.role ?? 'citizen';
    final isFoundation = role == 'foundation';
    final verified = me?.verified ?? false;
    final canList = role != 'admin';
    final pad = MediaQuery.paddingOf(context);
    final standalone = ModalRoute.of(context)?.canPop ?? false;

    final tabs = _mineMode
        ? const ['Active', 'Done']
        : [
            if (!isFoundation) ...['Available', 'Claimed', 'History', 'Mine'] else ...['Available', 'Claimed', 'History'],
          ];
    final tab = _tab.clamp(0, tabs.length - 1);
    final label = tabs[tab];

    // Which provider feeds the list.
    final bool useMine = (_mineMode && !isFoundation) || (!_mineMode && label == 'Mine');
    AsyncValue<List<Donation>> async;
    if (useMine) {
      async = ref.watch(myDonationsProvider);
    } else if (_mineMode) {
      async = ref.watch(donationsProvider((_kind, 'mine', 'new')));
    } else {
      final status = const {'Available': 'available', 'Claimed': 'claimed', 'History': 'history'}[label]!;
      async = ref.watch(donationsProvider((_kind, status, _sort)));
    }

    List<Donation> filter(List<Donation> all) {
      var items = all;
      if (_kind != null && useMine) items = items.where((d) => d.kind == _kind).toList();
      if (_mineMode) {
        final active = label == 'Active';
        items = items.where((d) => active ? d.isActive : !d.isActive).toList();
      }
      return items;
    }

    final filterActive = _kind != null || (!_mineMode && label == 'Available' && _sort != 'expiring');
    final actions = <Widget>[
      TopBarAction(
        icon: Icons.tune_rounded,
        tooltip: 'Filter',
        dot: filterActive,
        onTap: () async {
          final showSort = !_mineMode && label == 'Available';
          final r = await showFilterSheet(
            context,
            title: 'Filter',
            groups: [
              if (showSort)
                FilterGroup(
                  'sort',
                  'Sort by',
                  const [
                    ('expiring', 'Expiring', Icons.timer_outlined),
                    ('new', 'Newest', Icons.schedule_rounded),
                    ('near', 'Nearest', Icons.near_me_rounded),
                  ],
                  selected: _sort,
                ),
              FilterGroup('kind', 'Type', [for (final e in donationKinds.entries) (e.key, e.value.label, e.value.icon)], selected: _kind, allLabel: 'All types'),
            ],
          );
          if (r == null || !mounted) return;
          setState(() {
            _kind = r['kind'];
            if (showSort) _sort = r['sort'] ?? 'expiring';
          });
        },
      ),
      TopBarAction(icon: _map ? Icons.view_agenda_outlined : Icons.map_outlined, tooltip: _map ? 'List view' : 'Map view', onTap: () => setState(() => _map = !_map)),
      if (!_mineMode)
        TopBarAction(
          icon: Icons.handshake_outlined,
          tooltip: 'Foundations',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FoundationsScreen())),
        ),
      if (canList) TopBarAction(icon: Icons.add_rounded, tooltip: 'List a donation', onTap: () => showCreateDonationSheet(context)),
    ];
    final title = _mineMode ? (isFoundation ? 'My claims' : 'My listings') : 'Donations';
    final leading = standalone ? TopBarAction(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: () => Navigator.of(context).maybePop()) : null;
    void onTab(int i) => setState(() => _tab = i);

    Widget body;
    if (_map) {
      body = Column(
        children: [
          WelfareHeaderBox(title: title, actions: actions, tabs: tabs, tabIndex: tab, onTab: onTab, leading: leading),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: standalone ? pad.bottom : 84),
              child: async.when(
                skipLoadingOnReload: true,
                loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: C.inkSoft)),
                error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(donationsProvider)),
                data: (all) => MarkersMapScreen.body(
                  items: [for (final d in filter(all)) donationMapItem(d)],
                  onOpen: (ctx, m) => openDonation(ctx, (m.data! as Donation).id),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      body = RefreshIndicator(
        color: C.ember,
        edgeOffset: pad.top + 96,
        onRefresh: () async {
          await ref.read(locationProvider.notifier).refresh();
          await refreshWelfare(ref);
        },
        child: CustomScrollView(
          slivers: [
            WelfareHeaderSliver(title: title, actions: actions, tabs: tabs, tabIndex: tab, onTab: onTab, leading: leading),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, standalone ? pad.bottom + 40 : 140),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (isFoundation && !verified) ...[
                    const InfoBanner(
                      icon: Icons.hourglass_top_rounded,
                      text: 'Verification pending. An admin is reviewing your organisation. You can browse now and claim once verified.',
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (isFoundation && verified && !_mineMode) ...[const FoundationDashboardHeader(), const SizedBox(height: 14)],
                  async.when(
                    skipLoadingOnReload: true,
                    loading: () => const DonationListSkeleton(),
                    error: (e, _) => ErrorState(
                      error: e,
                      onRetry: () {
                        ref.invalidate(donationsProvider);
                        ref.invalidate(myDonationsProvider);
                      },
                    ),
                    data: (all) {
                      final items = filter(all);
                      if (items.isEmpty) return _empty(label, isFoundation);
                      return Column(
                        children: [
                          for (var i = 0; i < items.length; i++)
                            Enter(
                              key: ValueKey('${items[i].id}-$label-$_kind-$_sort'),
                              index: i,
                              child: DonationCard(
                                d: items[i],
                                onTap: () => openDonation(context, items[i].id),
                                onClaim: items[i].canClaim ? () => claimFlow(context, ref, items[i]) : null,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ]),
              ),
            ),
          ],
        ),
      );
    }

    if (!standalone) return body;
    return Scaffold(body: PageBackdrop(child: body));
  }

  Widget _empty(String label, bool isFoundation) {
    return switch (label) {
      'Available' => EmptyState(
        title: 'Nothing to claim right now',
        body: isFoundation
            ? 'We will alert you the moment something is listed near you.'
            : 'Have surplus food or clothes? Tap + to list it in under a minute.',
      ),
      'Claimed' => const EmptyState(title: 'No claims in flight', body: 'Donations that foundations are collecting show up here.'),
      'Active' => const EmptyState(title: 'No active claims', body: 'Claim a donation from the Available list and it will appear here.'),
      'Done' => const EmptyState(title: 'Nothing completed yet', body: 'Distributed donations will build your impact history.'),
      'Mine' => const EmptyState(title: 'You have not listed anything', body: 'Tap + to share surplus food, clothes, books and more.'),
      _ => const EmptyState(title: 'No history yet', body: 'Distributed and expired donations are kept here.'),
    };
  }
}
