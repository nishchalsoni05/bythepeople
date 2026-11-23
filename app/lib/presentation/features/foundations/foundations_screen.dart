import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/domain/entities/foundation.dart';
import 'package:by_the_people/presentation/features/donations/create_donation_sheet.dart';
import 'package:by_the_people/presentation/features/donations/donation_widgets.dart';
import 'package:by_the_people/presentation/features/gatherings/welfare_common.dart';
import 'package:by_the_people/presentation/providers/donation_providers.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Directory of verified foundations, searchable and filterable by what they need.
class FoundationsScreen extends ConsumerStatefulWidget {
  const FoundationsScreen({super.key});
  @override
  ConsumerState<FoundationsScreen> createState() => _FoundationsScreenState();
}

class _FoundationsScreenState extends ConsumerState<FoundationsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _q = '';
  String? _need;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _q = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(foundationsProvider((_q, _need)));
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      body: PageBackdrop(
        child: RefreshIndicator(
          color: C.ember,
          onRefresh: () async {
            ref.invalidate(foundationsProvider);
            await ref.read(foundationsProvider((_q, _need)).future);
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, pad.top + 8, 16, pad.bottom + 40),
            children: [
              const WHeader(title: 'Foundations'),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text('Verified organisations that turn surplus into support.', style: ui(13, color: C.inkSoft, h: 1.35)),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('foundation-search'),
                controller: _search,
                onChanged: _onSearch,
                style: ui(14),
                decoration: InputDecoration(
                  hintText: 'Search by name',
                  prefixIcon: const Icon(Icons.search_rounded, color: C.inkSoft),
                  filled: true,
                  fillColor: C.surface,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AppChip(label: 'All needs', selected: _need == null, onTap: () => setState(() => _need = null)),
                    ),
                    for (final e in donationKinds.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: AppChip(
                          label: e.value.label,
                          icon: e.value.icon,
                          selected: _need == e.key,
                          onTap: () => setState(() => _need = _need == e.key ? null : e.key),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              async.when(
                skipLoadingOnReload: true,
                loading: () => const RowListSkeleton(count: 4),
                error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(foundationsProvider)),
                data: (items) => items.isEmpty
                    ? const EmptyState(title: 'No foundations found', body: 'Try a different search or clear the filter.')
                    : Column(
                        children: [
                          for (var i = 0; i < items.length; i++)
                            Enter(
                              key: ValueKey(items[i].id),
                              index: i,
                              child: FoundationCard(f: items[i]),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openFoundation(BuildContext context, int id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FoundationDetailScreen(id: id)));

class FoundationCard extends StatelessWidget {
  const FoundationCard({super.key, required this.f});
  final Foundation f;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: () => openFoundation(context, f.id),
      child: WCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Logo(f, 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(15, w: 600)),
                          ),
                          if (f.verified) ...[
                            const SizedBox(width: 5),
                            const Icon(Icons.verified_rounded, size: 15, color: Color(0xFF3B9C6E)),
                          ],
                        ],
                      ),
                      if (f.address.isNotEmpty)
                        Text(
                          f.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ui(12, color: C.inkSoft),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (f.about.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                f.about,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ui(13, color: C.inkSoft, h: 1.4),
              ),
            ],
            if (f.needs.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final n in f.needs) Tag(kindStyle(n).label, icon: kindStyle(n).icon)]),
            ],
            const SizedBox(height: 12),
            Text('${f.stats.distributed} distributed · ${f.stats.beneficiaries} people helped', style: ui(12.5, color: C.inkSoft, w: 500)),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo(this.f, this.size);
  final Foundation f;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: C.muted, borderRadius: BorderRadius.circular(size * 0.25), border: Border.all(color: C.line)),
    child: Text(f.name.isEmpty ? '?' : f.name[0].toUpperCase(), style: ui(size * 0.42, color: C.ink, w: 600)),
  );
}

class FoundationDetailScreen extends ConsumerWidget {
  const FoundationDetailScreen({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(foundationProvider(id));
    final role = ref.watch(authProvider).user?.role ?? 'citizen';
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      body: PageBackdrop(
        child: async.when(
          loading: () => const SafeArea(child: DetailSkeleton()),
          error: (e, _) => SafeArea(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: WHeader(title: 'Foundation'),
                ),
                ErrorState(error: e, onRetry: () => ref.invalidate(foundationProvider(id))),
              ],
            ),
          ),
          data: (f) => ListView(
            padding: EdgeInsets.fromLTRB(16, pad.top + 8, 16, pad.bottom + 40),
            children: [
              const WHeader(title: 'Foundation'),
              const SizedBox(height: 14),
              WCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Logo(f, 52),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.name, style: ui(18, w: 600, h: 1.2)),
                              const SizedBox(height: 4),
                              Tag(
                                f.verified ? 'Verified' : 'Pending verification',
                                icon: f.verified ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                                bg: f.verified ? C.mint : C.amber.withValues(alpha: 0.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (f.about.isNotEmpty) ...[const SizedBox(height: 14), Text(f.about, style: ui(14, h: 1.5))],
                    if (f.address.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.place_outlined, size: 18, color: C.inkSoft),
                          const SizedBox(width: 8),
                          Expanded(child: Text(f.address, style: ui(13.5))),
                        ],
                      ),
                    ],
                    if ((f.regNo ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.badge_outlined, size: 18, color: C.inkSoft),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Reg. no. ${f.regNo}', style: ui(13.5))),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(value: f.stats.claimed, label: 'Claimed', icon: Icons.volunteer_activism_rounded),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(value: f.stats.distributed, label: 'Distributed', icon: Icons.check_circle_outline_rounded),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      value: f.stats.beneficiaries,
                      label: 'People helped',
                      icon: Icons.favorite_border_rounded,
                      bg: C.lime.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
              if (f.needs.isNotEmpty) ...[
                const SizedBox(height: 18),
                const SectionTitle('Currently needs'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final n in f.needs) Tag(kindStyle(n).label, icon: kindStyle(n).icon, bg: C.surface)],
                ),
              ],
              if (f.activeClaims > 0) ...[
                const SizedBox(height: 14),
                Text('${f.activeClaims} pickups in progress right now', style: ui(13, color: C.inkSoft)),
              ],
              if (role != 'admin' && f.verified) ...[
                const SizedBox(height: 20),
                PillButton(
                  label: 'Donate something',
                  icon: Icons.volunteer_activism_rounded,
                  onPressed: () => showCreateDonationSheet(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
