import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/features/admin/issue_row.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Neta tab 2: issues escalated to the authority, with their live authority status.
class NetaEscalatedScreen extends ConsumerWidget {
  const NetaEscalatedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(netaFeedProvider((null, 'top')));
    final pad = MediaQuery.of(context).padding;
    return RefreshIndicator(
      color: C.ember,
      onRefresh: () async {
        ref.read(tickProvider.notifier).bump();
        await ref.read(netaFeedProvider((null, 'top')).future);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, pad.top + 12, 20, 140),
        children: [
          Text('Priority', style: ui(20, w: 650)),
          const SizedBox(height: 4),
          Text('Issues you pushed to the admin portal.', style: ui(13.5, color: C.inkSoft)),
          const SizedBox(height: 16),
          feed.when(
            skipLoadingOnReload: true,
            loading: () => const IssueListSkeleton(),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(netaFeedProvider)),
            data: (all) {
              final items = all.where((i) => i.escalated).toList();
              return items.isEmpty
                  ? const EmptyState(title: 'No escalations yet', body: 'Open an issue in your locality feed and tap Escalate to send it to the authority.')
                  : Column(children: [for (final i in items) IssueRow(key: ValueKey(i.id), issue: i, netaActions: true)]);
            },
          ),
        ],
      ),
    );
  }
}
