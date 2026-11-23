import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/presentation/widgets/celebrate.dart';
import 'package:by_the_people/presentation/widgets/media.dart';
import 'package:by_the_people/presentation/widgets/sheets.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Authority action sheet: acknowledge / in progress / resolve (note + proof photo) / assign.
Future<void> showAuthoritySheet(BuildContext context, Issue issue) => showAppSheet<void>(
      context,
      title: 'Update issue',
      subtitle: issue.title,
      body: (_) => _AuthorityBody(issue: issue, parent: context),
    );

class _AuthorityBody extends ConsumerStatefulWidget {
  final Issue issue;
  final BuildContext parent;
  const _AuthorityBody({required this.issue, required this.parent});
  @override
  ConsumerState<_AuthorityBody> createState() => _AuthorityBodyState();
}

class _AuthorityBodyState extends ConsumerState<_AuthorityBody> {
  static const _statuses = ['acknowledged', 'in_progress', 'resolved'];
  static const _labels = ['Acknowledge', 'In progress', 'Resolve'];
  late int _i = switch (widget.issue.authorityStatus) { 'acknowledged' => 1, 'in_progress' => 2, _ => 0 };
  final _note = TextEditingController(), _assign = TextEditingController();
  final _media = MediaAttachController(max: 4);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _assign.text = widget.issue.assignedTo ?? '';
  }

  @override
  void dispose() {
    _note.dispose();
    _assign.dispose();
    _media.dispose();
    super.dispose();
  }

  bool get _resolve => _statuses[_i] == 'resolved';
  bool get _ok => !_resolve || (_note.text.trim().isNotEmpty && _media.items.isNotEmpty);

  Future<void> _submit() async {
    setState(() => _busy = true);
    final a = ref.read(actionsProvider);
    try {
      final urls = _media.items.isEmpty ? <String>[] : await _media.upload(a.uploadMedia);
      final r = await a.authorityUpdate(
        widget.issue.id,
        status: _statuses[_i],
        note: _note.text.trim(),
        assignedTo: _assign.text.trim(),
        media: urls,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (widget.parent.mounted) {
        celebrate(widget.parent, rewards: r.rewards, headline: _resolve ? 'Sent to citizens for verification' : 'Issue updated', confetti: _resolve);
      }
    } on ApiException catch (e) {
      if (mounted) {
        showToast(context, e.message, error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedToggle(labels: _labels, index: _i, onChanged: (i) => setState(() => _i = i)),
      const SizedBox(height: 14),
      AppField(
        controller: _note,
        hint: _resolve ? 'What was done? (required)' : 'Public note for citizens (optional)',
        lines: 3,
        maxLength: 400,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 10),
      AppField(controller: _assign, hint: 'Assign to (officer or team)', icon: Icons.assignment_ind_outlined, maxLength: 80),
      const SizedBox(height: 14),
      Text(_resolve ? 'Proof photo or video (required)' : 'Attach photo or video (optional)', style: ui(13.5, w: 700)),
      const SizedBox(height: 8),
      MediaAttachStrip(controller: _media, addLabel: 'Add proof'),
      const SizedBox(height: 18),
      ListenableBuilder(
        listenable: _media,
        builder: (_, __) => PillButton(
          label: _resolve ? 'Mark resolved' : 'Save update',
          icon: _resolve ? Icons.task_alt_rounded : Icons.check_rounded,
          color: _resolve ? C.ember : C.ink,
          loading: _busy,
          onPressed: _ok ? _submit : null,
        ),
      ),
    ]);
  }
}
