import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/features/donations/donation_detail_screen.dart';
import 'package:by_the_people/presentation/features/donations/donation_widgets.dart';
import 'package:by_the_people/presentation/features/gatherings/welfare_common.dart';
import 'package:by_the_people/presentation/providers/donation_providers.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Header for a verified foundation: its impact numbers, what it needs, and the claims in flight.
class FoundationDashboardHeader extends ConsumerWidget {
  const FoundationDashboardHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(foundationDashboardProvider);
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const Skeleton(
        child: Row(
          children: [
            Expanded(child: SkeletonBox(height: 64, radius: 12)),
            SizedBox(width: 8),
            Expanded(child: SkeletonBox(height: 64, radius: 12)),
            SizedBox(width: 8),
            Expanded(child: SkeletonBox(height: 64, radius: 12)),
          ],
        ),
      ),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(foundationDashboardProvider)),
      data: (d) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: d.stats.claimed,
                  label: 'Claimed',
                  icon: Icons.volunteer_activism_rounded,
                  bg: C.lime.withValues(alpha: 0.35),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(value: d.stats.distributed, label: 'Distributed', icon: Icons.check_circle_outline_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(value: d.stats.beneficiaries, label: 'People helped', icon: Icons.favorite_border_rounded),
              ),
            ],
          ),
          if (d.needs.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('You are asking for', style: ui(12.5, color: C.inkSoft, w: 600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final n in d.needs) Tag(kindStyle(n).label, icon: kindStyle(n).icon, bg: C.surface)],
            ),
          ],
          if (d.activeClaims.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionTitle('Your active claims (${d.activeClaims.length})'),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: d.activeClaims.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final c = d.activeClaims[i];
                  final k = kindStyle(c.kind);
                  return TapScale(
                    onTap: () => openDonation(context, c.id),
                    child: Container(
                      width: 220,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(k.icon, size: 16, color: C.inkSoft),
                              const SizedBox(width: 6),
                              Expanded(child: Text(donationStatusLabel(c.status), style: ui(12, color: C.inkSoft, w: 600))),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(14, w: 600, h: 1.25)),
                          ),
                          FreshnessChip(c),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
