import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/domain/entities/portal.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/presentation/widgets/sheets.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Admin tab 3: verify or reject foundation registrations.
class AdminFoundationsScreen extends ConsumerStatefulWidget {
  const AdminFoundationsScreen({super.key});
  @override
  ConsumerState<AdminFoundationsScreen> createState() => _AdminFoundationsScreenState();
}

class _AdminFoundationsScreenState extends ConsumerState<AdminFoundationsScreen> {
  int _tab = 0;
  static const _keys = ['pending', 'verified', 'all'];

  @override
  Widget build(BuildContext context) {
    final key = _keys[_tab];
    final async = ref.watch(adminFoundationsProvider(key));
    final pad = MediaQuery.of(context).padding;
    return RefreshIndicator(
      color: C.ember,
      onRefresh: () async {
        ref.read(tickProvider.notifier).bump();
        await ref.read(adminFoundationsProvider(key).future);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, pad.top + 12, 20, 140),
        children: [
          Text('Foundations', style: ui(20, w: 650)),
          const SizedBox(height: 4),
          Text('Only verified foundations can claim donations.', style: ui(13.5, color: C.inkSoft)),
          const SizedBox(height: 14),
          SegmentedToggle(labels: const ['Pending', 'Verified', 'All'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
          const SizedBox(height: 16),
          async.when(
            skipLoadingOnReload: true,
            loading: () => const RowListSkeleton(),
            error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(adminFoundationsProvider)),
            data: (items) => items.isEmpty
                ? EmptyState(title: _tab == 0 ? 'No pending requests' : 'No foundations', body: _tab == 0 ? 'New registrations appear here for verification.' : 'Nothing to show yet.')
                : Column(children: [for (final f in items) _FoundationCard(key: ValueKey(f.id), f: f)]),
          ),
        ],
      ),
    );
  }
}

class _FoundationCard extends ConsumerStatefulWidget {
  final FoundationRow f;
  const _FoundationCard({super.key, required this.f});
  @override
  ConsumerState<_FoundationCard> createState() => _FoundationCardState();
}

class _FoundationCardState extends ConsumerState<_FoundationCard> {
  bool _busy = false;

  Future<void> _decide(bool approve, {String? note}) async {
    setState(() => _busy = true);
    try {
      await ref.read(actionsProvider).verifyFoundation(widget.f.id, approve, note: note);
      if (mounted) showToast(context, approve ? '${widget.f.name} is now verified' : 'Registration rejected');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final ctl = TextEditingController();
    final note = await showAppSheet<String>(
      context,
      title: 'Reject registration',
      subtitle: 'Optionally tell ${widget.f.name} why.',
      body: (ctx) => Column(children: [
        AppField(controller: ctl, hint: 'Reason (optional)', lines: 3, maxLength: 300),
        const SizedBox(height: 14),
        PillButton(label: 'Reject', icon: Icons.close_rounded, color: C.ember, onPressed: () => Navigator.pop(ctx, ctl.text.trim())),
      ]),
    );
    if (note != null) await _decide(false, note: note);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(f.asPerson, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: ui(16, w: 750)),
              Text('Reg. ${f.regNo ?? 'not provided'}', style: ui(12.5, color: C.inkSoft, w: 600)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: f.verified ? C.mintDeep : C.amber, borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(f.verified ? Icons.verified_rounded : Icons.hourglass_top_rounded, size: 13, color: C.ink),
              const SizedBox(width: 4),
              Text(f.verified ? 'Verified' : 'Pending', style: ui(11.5, w: 700)),
            ]),
          ),
        ]),
        if ((f.about ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(f.about!, maxLines: 3, overflow: TextOverflow.ellipsis, style: ui(13.5, color: C.inkSoft, h: 1.4)),
        ],
        if ((f.address ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.place_outlined, size: 15, color: C.inkSoft),
            const SizedBox(width: 4),
            Expanded(child: Text(f.address!, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(12.5, color: C.inkSoft))),
          ]),
        ],
        if (f.needs.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final n in f.needs)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: C.muted, borderRadius: BorderRadius.circular(14)),
                child: Text(n, style: ui(11.5, w: 650)),
              ),
          ]),
        ],
        if (f.verified) ...[
          const SizedBox(height: 12),
          Row(children: [
            _Stat('${f.claimed}', 'claimed'),
            _Stat('${f.distributed}', 'distributed'),
            _Stat('${f.beneficiaries}', 'people helped'),
          ]),
        ],
        const SizedBox(height: 14),
        if (!f.verified)
          Row(children: [
            Expanded(child: PillButton(label: 'Reject', icon: Icons.close_rounded, color: C.muted, fg: C.ink, onPressed: _busy ? null : _reject)),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: PillButton(label: 'Verify', icon: Icons.verified_rounded, color: C.ink, loading: _busy, onPressed: () => _decide(true))),
          ])
        else
          PillButton(label: 'Revoke verification', icon: Icons.block_rounded, color: C.muted, fg: C.ink, loading: _busy, onPressed: _reject),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String v, l;
  const _Stat(this.v, this.l);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(v, style: ui(18, w: 750)),
          Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(11, color: C.inkSoft, w: 650)),
        ]),
      );
}
