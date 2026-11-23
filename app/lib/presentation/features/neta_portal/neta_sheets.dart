import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/presentation/widgets/sheets.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Neta: escalate an issue to the admin portal with a note.
Future<void> showEscalateSheet(BuildContext context, Issue issue) => showAppSheet<void>(
      context,
      title: 'Escalate to authority',
      subtitle: 'Admins in your city are notified and see this issue first in their queue.',
      body: (_) => _NoteBody(
        parent: context,
        hint: 'Why does this need urgent attention?',
        label: 'Escalate',
        icon: Icons.trending_up_rounded,
        color: C.ember,
        success: 'Escalated to the admin portal',
        minLen: 3,
        submit: (ref, note) => ref.read(actionsProvider).escalate(issue.id, note),
      ),
    );

/// Neta: post a public response or pledge on the issue timeline.
Future<void> showNetaResponseSheet(BuildContext context, Issue issue) => showAppSheet<void>(
      context,
      title: 'Public response',
      subtitle: 'Your pledge is shown to everyone on this issue\'s timeline.',
      body: (_) => _NoteBody(
        parent: context,
        hint: 'e.g. Tanker supply starts tomorrow; repair by Friday',
        label: 'Post response',
        icon: Icons.campaign_rounded,
        color: C.ink,
        success: 'Response posted publicly',
        minLen: 3,
        submit: (ref, note) => ref.read(actionsProvider).netaResponse(issue.id, note),
      ),
    );

class _NoteBody extends ConsumerStatefulWidget {
  final BuildContext parent;
  final String hint, label, success;
  final IconData icon;
  final Color color;
  final int minLen;
  final Future<ActionResult> Function(WidgetRef ref, String note) submit;
  const _NoteBody({
    required this.parent, required this.hint, required this.label, required this.icon, required this.color,
    required this.success, required this.minLen, required this.submit,
  });
  @override
  ConsumerState<_NoteBody> createState() => _NoteBodyState();
}

class _NoteBodyState extends ConsumerState<_NoteBody> {
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      await widget.submit(ref, _note.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop();
      if (widget.parent.mounted) showToast(widget.parent, widget.success);
    } on ApiException catch (e) {
      if (mounted) {
        showToast(context, e.message, error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppField(controller: _note, hint: widget.hint, lines: 4, maxLength: 400, onChanged: (_) => setState(() {})),
        const SizedBox(height: 16),
        PillButton(
          label: widget.label,
          icon: widget.icon,
          color: widget.color,
          loading: _busy,
          onPressed: _note.text.trim().length >= widget.minLen ? _go : null,
        ),
      ]);
}
