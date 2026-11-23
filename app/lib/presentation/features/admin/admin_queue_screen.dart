import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/features/admin/issue_row.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Admin tab 2: every issue in the officer's city with status, category and search filters.
class AdminQueueScreen extends ConsumerStatefulWidget {
  const AdminQueueScreen({super.key});
  @override
  ConsumerState<AdminQueueScreen> createState() => _AdminQueueScreenState();
}

class _AdminQueueScreenState extends ConsumerState<AdminQueueScreen> {
  String _q = '';
  String? _category;
  String _sort = 'default';
  final _search = TextEditingController();

  static const _statuses = <(String?, String)>[
    (null, 'All'),
    ('open', 'Open'),
    ('acknowledged', 'Acknowledged'),
    ('in_progress', 'In progress'),
    ('pending_verification', 'Verifying'),
    ('closed', 'Closed'),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (status, escalated) = ref.watch(queueFilterProvider);
    final cats = ref.watch(metaProvider).asData?.value ?? [];
    final q = (status, _q, escalated, _category, _sort);
    final async = ref.watch(adminIssuesProvider(q));
    final pad = MediaQuery.of(context).padding;
    return RefreshIndicator(
      color: C.ember,
      onRefresh: () async {
        ref.read(tickProvider.notifier).bump();
        await ref.read(adminIssuesProvider(q).future);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, pad.top + 12, 20, 140),
        children: [
          Text('Reports', style: ui(20, w: 650)),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => setState(() => _q = v.trim()),
            onChanged: (v) {
              if (v.isEmpty && _q.isNotEmpty) setState(() => _q = '');
            },
            style: ui(15, w: 600),
            decoration: InputDecoration(
              hintText: 'Search issues',
              hintStyle: ui(15, color: C.inkSoft),
              prefixIcon: const Icon(Icons.search_rounded, color: C.inkSoft),
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, color: C.inkSoft),
                      onPressed: () {
                        _search.clear();
                        setState(() => _q = '');
                      },
                    ),
              filled: true,
              fillColor: C.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          _chips([
            for (final s in _statuses)
              AppChip(
                label: s.$2,
                selected: status == s.$1 && !escalated,
                onTap: () => ref.read(queueFilterProvider.notifier).set(s.$1),
              ),
            AppChip(
              label: 'Escalated',
              icon: Icons.trending_up_rounded,
              selected: escalated,
              onTap: () => ref.read(queueFilterProvider.notifier).set(null, escalated: !escalated),
            ),
          ]),
          const SizedBox(height: 8),
          _chips([
            for (final s in const [('default', 'Priority'), ('top', 'Top'), ('new', 'Newest'), ('oldest', 'Oldest')])
              AppChip(label: s.$2, selected: _sort == s.$1, onTap: () => setState(() => _sort = s.$1)),
            Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4), color: C.line),
            AppChip(label: 'Any category', selected: _category == null, onTap: () => setState(() => _category = null)),
            for (final c in cats)
              AppChip(
                label: c.label.split(' & ').first,
                icon: categoryIcons[c.key],
                selected: _category == c.key,
                onTap: () => setState(() => _category = _category == c.key ? null : c.key),
              ),
          ]),
          const SizedBox(height: 16),
          async.when(
            skipLoadingOnReload: true,
            loading: () => const IssueListSkeleton(),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(adminIssuesProvider)),
            data: (items) => items.isEmpty
                ? const EmptyState(title: 'Queue is clear', body: 'No issues match these filters.')
                : Column(children: [for (final i in items) IssueRow(key: ValueKey(i.id), issue: i, adminActions: true)]),
          ),
        ],
      ),
    );
  }

  Widget _chips(List<Widget> children) => SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final c in children) Padding(padding: const EdgeInsets.only(right: 8), child: c),
        ]),
      );
}
