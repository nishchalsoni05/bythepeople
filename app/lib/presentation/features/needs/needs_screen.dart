import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/core/utils/format.dart';
import 'package:by_the_people/domain/entities/need.dart';
import 'package:by_the_people/presentation/features/donations/donation_widgets.dart' show donationKinds, kindStyle;
import 'package:by_the_people/presentation/features/gatherings/welfare_common.dart';
import 'package:by_the_people/presentation/providers/needs_providers.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart';
import 'package:by_the_people/presentation/widgets/layout.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/stacked_card.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// The needs board: specific asks from verified foundations. Anyone can pledge; verified foundations can post.
class NeedsScreen extends ConsumerStatefulWidget {
  const NeedsScreen({super.key});
  @override
  ConsumerState<NeedsScreen> createState() => _NeedsScreenState();
}

class _NeedsScreenState extends ConsumerState<NeedsScreen> {
  int _tab = 0;
  final Set<int> _busy = {};

  String get _status => needStatuses[_tab];

  Future<void> _togglePledge(Need n) async {
    if (_busy.contains(n.id)) return;
    setState(() => _busy.add(n.id));
    try {
      final actions = ref.read(needActionsProvider);
      if (n.pledgedByMe) {
        await actions.unpledge(n.id);
      } else {
        await actions.pledge(n.id);
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(n.id));
    }
  }

  Future<void> _close(Need n) async {
    if (_busy.contains(n.id)) return;
    setState(() => _busy.add(n.id));
    try {
      await ref.read(needActionsProvider).close(n.id);
      if (mounted) showToast(context, 'Need closed.');
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(n.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).user;
    final canPost = me?.role == 'foundation' && (me?.verified ?? false);
    final pad = MediaQuery.paddingOf(context);
    final async = ref.watch(needsProvider(_status));

    return Scaffold(
      body: PageBackdrop(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, pad.top + 8, 16, 0),
              child: Row(children: [
                CircleBtn(icon: Icons.arrow_back_rounded, size: 42, onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 14),
                Text('Needs', style: ui(17, color: C.inkSoft, w: 700)),
                const Spacer(),
                if (canPost) PillButton(label: 'Post a need', icon: Icons.add_rounded, expand: false, onPressed: _post),
              ]),
            ),
            Expanded(
              child: ContentWidth(
                child: RefreshIndicator(
                  color: C.ember,
                  onRefresh: () async {
                    ref.invalidate(needsProvider(_status));
                    await ref.read(needsProvider(_status).future);
                  },
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, pad.bottom + 110),
                    children: [
                      SegmentedToggle(labels: const ['Open', 'Closed', 'All'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
                      const SizedBox(height: 14),
                      async.when(
                        skipLoadingOnReload: true,
                        loading: () => const RowListSkeleton(count: 3),
                        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(needsProvider(_status))),
                        data: (items) {
                          if (items.isEmpty) return _empty();
                          return Column(children: [
                            for (var i = 0; i < items.length; i++)
                              Enter(
                                key: ValueKey('${items[i].id}-$_status'),
                                index: i,
                                child: _NeedRow(
                                  need: items[i],
                                  meId: me?.id,
                                  busy: _busy.contains(items[i].id),
                                  onPledge: () => _togglePledge(items[i]),
                                  onClose: () => _close(items[i]),
                                ),
                              ),
                          ]);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return switch (_status) {
      'open' => const EmptyState(title: 'No open needs', body: 'When a verified foundation posts something it needs, it shows up here.'),
      'closed' => const EmptyState(title: 'No closed needs', body: 'Needs that were met or withdrawn are kept here.'),
      _ => const EmptyState(title: 'No needs yet', body: 'Foundations post specific asks here, such as blankets or school books.'),
    };
  }

  // The sheet bumps the welfare tick on success, so the board refreshes by itself.
  Future<void> _post() => showWelfareSheet<void>(context, builder: (_) => const _PostNeedSheet());
}

class _NeedRow extends StatelessWidget {
  const _NeedRow({required this.need, required this.meId, required this.busy, required this.onPledge, required this.onClose});
  final Need need;
  final int? meId;
  final bool busy;
  final VoidCallback onPledge, onClose;

  @override
  Widget build(BuildContext context) {
    final n = need;
    final k = kindStyle(n.kind);
    final owner = n.isOwner(meId);
    final deadline = n.deadlineAt;
    final qty = RegExp(r'^\s*(\d+)').firstMatch(n.quantity);
    final target = qty == null ? null : int.tryParse(qty.group(1)!);
    // Need card: hero surface with two tinted layers behind it.
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: StackedCard(
        layers: 2,
        offset: 6,
        inset: 10,
        tint: const Color(0xFFEDEDF0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: C.muted, borderRadius: BorderRadius.circular(14)),
                  child: Icon(k.icon, size: 22, color: C.inkSoft),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: titleStyle()),
                      const SizedBox(height: 2),
                      Row(children: [
                        Flexible(child: Text([n.foundation.label, if (n.quantity.isNotEmpty) n.quantity].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle())),
                        if (n.foundation.verified) ...[const SizedBox(width: 6), const Tag('Verified', icon: Icons.check_rounded)],
                      ]),
                    ],
                  ),
                ),
                if (!n.isOpen) Tag(n.status == 'fulfilled' ? 'Fulfilled' : 'Closed'),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                InfoChip(k.icon, n.kindLabel),
                if (deadline != null)
                  InfoChip(
                    Icons.event_outlined,
                    'Needed by ${fmtDate(deadline)}',
                    color: deadline < DateTime.now().millisecondsSinceEpoch && n.isOpen ? C.danger : C.inkSoft,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (target != null && n.isOpen) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: (n.pledgeCount / target).clamp(0.0, 1.0).toDouble(),
                  minHeight: 8,
                  backgroundColor: C.muted,
                  valueColor: const AlwaysStoppedAnimation(C.ink),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Icon(Icons.people_outline_rounded, size: 16, color: C.inkSoft),
                const SizedBox(width: 5),
                Text(target != null ? '${n.pledgeCount} of $target pledged' : '${n.pledgeCount} pledged', style: metaStyle()),
                const Spacer(),
                if (owner && n.isOpen) ...[
                  _TextBtn(label: 'Close', busy: busy, onTap: onClose),
                  const SizedBox(width: 8),
                ],
                if (n.isOpen)
                  n.pledgedByMe
                      ? _PledgedChip(busy: busy, onTap: onPledge)
                      : _PledgeButton(busy: busy, onTap: onPledge),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PledgeButton extends StatelessWidget {
  const _PledgeButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text('Pledge', style: ui(13.5, color: Colors.white, w: 650)),
        ),
      );
}

/// Grey chip for a pledge already made. Tapping it withdraws the pledge.
class _PledgedChip extends StatelessWidget {
  const _PledgedChip({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: C.muted, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.inkSoft))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check_rounded, size: 16, color: C.inkSoft),
                  const SizedBox(width: 5),
                  Text('Pledged', style: ui(13, color: C.inkSoft, w: 650)),
                  const SizedBox(width: 6),
                  const Icon(Icons.undo_rounded, size: 14, color: C.inkSoft),
                ]),
        ),
      );
}

class _TextBtn extends StatelessWidget {
  const _TextBtn({required this.label, required this.busy, required this.onTap});
  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: busy ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border.all(color: C.line), borderRadius: BorderRadius.circular(12)),
          child: Text(label, style: ui(13, color: C.ink, w: 650)),
        ),
      );
}

/// Verified foundations post a need: kind, title, optional quantity and deadline.
class _PostNeedSheet extends ConsumerStatefulWidget {
  const _PostNeedSheet();
  @override
  ConsumerState<_PostNeedSheet> createState() => _PostNeedSheetState();
}

class _PostNeedSheetState extends ConsumerState<_PostNeedSheet> {
  final _title = TextEditingController();
  final _qty = TextEditingController();
  String _kind = 'food';
  DateTime? _deadline;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 366)),
    );
    if (d == null || !mounted) return;
    setState(() => _deadline = DateTime(d.year, d.month, d.day, 23, 59));
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.length < 3) return showToast(context, 'Add a short title.', error: true);
    setState(() => _busy = true);
    final need = await guarded(context, () => ref.read(needActionsProvider).create(NeedDraft(
          kind: _kind,
          title: title,
          quantity: _qty.text.trim(),
          deadlineAt: _deadline?.millisecondsSinceEpoch,
        )));
    if (!mounted) return;
    setState(() => _busy = false);
    if (need != null) {
      Navigator.of(context).pop();
      showToast(context, 'Need posted. Donors can pledge now.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      title: 'Post a need',
      subtitle: 'Tell donors and other foundations what you are short of.',
      children: [
        Text('What do you need?', style: ui(12.5, color: C.inkSoft, w: 600)),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final e in donationKinds.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AppChip(
                    label: e.value.label,
                    icon: e.value.icon,
                    selected: _kind == e.key,
                    onTap: () => setState(() => _kind = e.key),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        WField(label: 'Title', controller: _title, hint: 'e.g. Winter blankets for 40 children', maxLength: 80, fieldKey: const Key('n-title')),
        const SizedBox(height: 14),
        WField(label: 'Quantity (optional)', controller: _qty, hint: 'e.g. 40 blankets', maxLength: 60, fieldKey: const Key('n-qty')),
        const SizedBox(height: 14),
        Text('Needed by (optional)', style: ui(12.5, color: C.inkSoft, w: 600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppChip(label: 'No deadline', selected: _deadline == null, onTap: () => setState(() => _deadline = null)),
            AppChip(
              label: _deadline == null ? 'Pick a date' : fmtDate(_deadline!.millisecondsSinceEpoch),
              icon: Icons.event_outlined,
              selected: _deadline != null,
              onTap: _pickDeadline,
            ),
          ],
        ),
        const SizedBox(height: 22),
        PillButton(label: 'Post need', icon: Icons.campaign_outlined, loading: _busy, onPressed: _submit),
      ],
    );
  }
}
