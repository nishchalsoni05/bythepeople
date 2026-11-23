import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/domain/entities/club.dart';
import 'package:by_the_people/presentation/features/gatherings/gathering_detail_screen.dart';
import 'package:by_the_people/presentation/features/gatherings/gathering_widgets.dart';
import 'package:by_the_people/presentation/features/gatherings/welfare_common.dart';
import 'package:by_the_people/presentation/providers/gathering_providers.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Clubs tab: every club with join / leave, plus a way to start one.
class ClubsView extends ConsumerWidget {
  const ClubsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clubsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        async.when(
          loading: () => const RowListSkeleton(count: 4),
          error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(clubsProvider)),
          data: (clubs) => clubs.isEmpty
              ? const EmptyState(title: 'No clubs yet', body: 'Start the first one: a run club, a plantation crew, anything good.')
              : Column(
                  children: [
                    for (var i = 0; i < clubs.length; i++)
                      Enter(
                        index: i,
                        child: ClubCard(club: clubs[i]),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 6),
        PillButton(label: 'Start a club', icon: Icons.add_rounded, onPressed: () => showCreateClubSheet(context)),
      ],
    );
  }
}

Future<void> toggleClub(BuildContext context, WidgetRef ref, Club c) async {
  final join = !c.joinedByMe;
  final ok = await guarded(context, () async {
    await ref.read(gatheringActionsProvider).joinClub(c.id, on: join);
    return true;
  });
  if (ok == true && context.mounted) showToast(context, join ? 'Joined ${c.name}' : 'Left ${c.name}', icon: Icons.groups_rounded);
}

class ClubCard extends ConsumerWidget {
  const ClubCard({super.key, required this.club});
  final Club club;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = club;
    return TapScale(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ClubDetailScreen(id: c.id))),
      child: WCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: C.muted, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
              child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase(), style: ui(18, color: C.ink, w: 600)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(15, w: 600)),
                  const SizedBox(height: 2),
                  Text(
                    '${c.memberCount} members · ${c.upcomingCount} upcoming',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ui(12.5, color: C.inkSoft, w: 600),
                  ),
                  if (c.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      c.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ui(12.5, color: C.inkSoft, h: 1.35),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            AppChip(
              label: c.joinedByMe ? 'Joined' : 'Join',
              icon: c.joinedByMe ? Icons.check_rounded : Icons.add_rounded,
              selected: !c.joinedByMe,
              onTap: () => toggleClub(context, ref, c),
            ),
          ],
        ),
      ),
    );
  }
}

class ClubDetailScreen extends ConsumerWidget {
  const ClubDetailScreen({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clubDetailProvider(id));
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      body: PageBackdrop(
        child: async.when(
          loading: () => const SafeArea(child: DetailSkeleton()),
          error: (e, _) => SafeArea(
            child: ErrorState(error: e, onRetry: () => ref.invalidate(clubDetailProvider(id))),
          ),
          data: (d) {
            final c = d.club;
            return ListView(
              padding: EdgeInsets.fromLTRB(16, pad.top + 8, 16, pad.bottom + 40),
              children: [
                WHeader(title: c.name),
                const SizedBox(height: 16),
                WCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (c.category.isNotEmpty) Tag(c.category, icon: Icons.sell_outlined),
                          Tag('${c.memberCount} members', icon: Icons.groups_rounded),
                        ],
                      ),
                      if (c.description.isNotEmpty) ...[const SizedBox(height: 12), Text(c.description, style: ui(14.5, h: 1.5))],
                      if (c.owner != null) ...[const SizedBox(height: 14), PersonLine(c.owner!, sub: 'Club owner')],
                      const SizedBox(height: 16),
                      PillButton(
                        label: c.joinedByMe ? 'Leave club' : 'Join club',
                        icon: c.joinedByMe ? Icons.logout_rounded : Icons.add_rounded,
                        color: c.joinedByMe ? C.muted : C.ink,
                        fg: c.joinedByMe ? C.ink : Colors.white,
                        onPressed: () => toggleClub(context, ref, c),
                      ),
                    ],
                  ),
                ),
                if (d.members.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const SectionTitle('Members'),
                  WCard(
                    child: Wrap(spacing: 10, runSpacing: 10, children: [for (final m in d.members.take(24)) PersonAvatar(m, size: 38)]),
                  ),
                ],
                const SizedBox(height: 18),
                const SectionTitle('Upcoming'),
                if (d.upcoming.isEmpty)
                  WCard(
                    child: Text('No gatherings scheduled yet.', style: ui(14, color: C.inkSoft)),
                  )
                else
                  for (var i = 0; i < d.upcoming.length; i++)
                    Enter(
                      index: i,
                      child: GatheringCard(g: d.upcoming[i], onTap: () => openGathering(context, d.upcoming[i].id)),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

const _clubCategories = ['Fitness', 'Environment', 'Animals', 'Health', 'Education', 'Food', 'Community'];

Future<void> showCreateClubSheet(BuildContext context) => showWelfareSheet<void>(context, builder: (_) => const _CreateClubSheet());

class _CreateClubSheet extends ConsumerStatefulWidget {
  const _CreateClubSheet();
  @override
  ConsumerState<_CreateClubSheet> createState() => _CreateClubSheetState();
}

class _CreateClubSheetState extends ConsumerState<_CreateClubSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  String _category = _clubCategories.first;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 3) {
      showToast(context, 'Give the club a name of at least 3 letters.', error: true);
      return;
    }
    setState(() => _busy = true);
    final c = await guarded(context, () => ref.read(gatheringActionsProvider).createClub(_name.text.trim(), _desc.text.trim(), _category));
    if (!mounted) return;
    setState(() => _busy = false);
    if (c != null) {
      Navigator.of(context).pop();
      showToast(context, '${c.name} is live', icon: Icons.groups_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      title: 'Start a club',
      subtitle: 'People who care about the same thing, in one place.',
      children: [
        WField(label: 'Club name', controller: _name, hint: 'e.g. Sunday Cleanup Crew', maxLength: 60, fieldKey: const Key('club-name')),
        const SizedBox(height: 14),
        WField(label: 'What is it about?', controller: _desc, lines: 3, hint: 'A line or two', maxLength: 300),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in _clubCategories) AppChip(label: c, selected: _category == c, onTap: () => setState(() => _category = c)),
          ],
        ),
        const SizedBox(height: 22),
        PillButton(label: 'Create club', loading: _busy, onPressed: _save),
      ],
    );
  }
}
