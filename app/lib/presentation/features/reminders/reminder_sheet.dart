import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/app/reminders_di.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/domain/entities/reminder.dart';
import 'package:by_the_people/presentation/providers/locale_provider.dart';
import 'package:by_the_people/presentation/providers/reminder_providers.dart';
import 'package:by_the_people/presentation/widgets/sheets.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Opens the "Set reminder" sheet. [refType]/[refId] optionally link the reminder to an item.
Future<void> showReminderSheet(BuildContext context, {String? refType, int? refId}) {
  return showAppSheet<void>(
    context,
    title: 'Set reminder',
    subtitle: 'Choose who should see it, then pick a time.',
    body: (_) => _ReminderForm(refType: refType, refId: refId),
  );
}

class _ReminderForm extends ConsumerStatefulWidget {
  const _ReminderForm({this.refType, this.refId});
  final String? refType;
  final int? refId;

  @override
  ConsumerState<_ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends ConsumerState<_ReminderForm> {
  final _title = TextEditingController();
  final _who = TextEditingController();
  DateTime _when = DateTime.now().add(const Duration(hours: 1));
  bool _showCollaborator = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _who.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _when.isBefore(now) ? now : _when,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 366)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (time == null || !mounted) return;
    setState(() => _when = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  Future<void> _save(ReminderScope scope, {int? recipientId}) async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showToast(context, 'Add a note for the reminder', error: true);
      return;
    }
    if (!_when.isAfter(DateTime.now())) {
      showToast(context, 'Pick a time in the future', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(reminderRepositoryProvider).create(ReminderDraft(
            title: title,
            scope: scope,
            remindAt: _when,
            refType: widget.refType,
            refId: widget.refId,
            recipientId: recipientId,
          ));
      ref.invalidate(remindersProvider);
      if (!mounted) return;
      final msg = trNow(ref, 'reminder_set');
      showToast(context, msg, icon: Icons.notifications_active_outlined);
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) toastError(context, e, fallback: 'Could not set the reminder.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _sendToCollaborator() {
    final raw = _who.text.trim().replaceFirst('@', '');
    final id = int.tryParse(raw);
    if (id == null) {
      showToast(context, 'Enter the collaborator\'s member ID', error: true);
      return;
    }
    _save(ReminderScope.collaborator, recipientId: id);
  }

  @override
  Widget build(BuildContext context) {
    final materials = MaterialLocalizations.of(context);
    final time = TimeOfDay.fromDateTime(_when);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppField(controller: _title, hint: 'What should we remember?', icon: Icons.notes_rounded, maxLength: 120),
      const SizedBox(height: R.unit),
      FlatCard(
        padding: const EdgeInsets.all(R.cardInset),
        onTap: _saving ? null : _pickWhen,
        child: Row(children: [
          const IconChip(Icons.schedule_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('When', style: metaStyle()),
              const SizedBox(height: 2),
              Text('${materials.formatMediumDate(_when)} · ${materials.formatTimeOfDay(time)}', style: numStyle(15)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, size: 20, color: C.inkSoft),
        ]),
      ),
      const SizedBox(height: R.cardInset),
      _OptionCard(
        icon: Icons.person_outline_rounded,
        title: 'Set reminder for me',
        sub: 'Only you can see this',
        enabled: !_saving,
        onTap: () => _save(ReminderScope.me),
      ),
      const SizedBox(height: R.unit),
      _OptionCard(
        icon: Icons.groups_outlined,
        title: 'Set reminder for space collaborators',
        sub: 'Everyone in this space can see it',
        enabled: !_saving,
        onTap: () => _save(ReminderScope.space),
      ),
      const SizedBox(height: R.unit),
      _OptionCard(
        icon: Icons.send_outlined,
        title: 'Send reminder to collaborator',
        sub: 'Pick one person and a time',
        enabled: !_saving,
        onTap: () => setState(() => _showCollaborator = !_showCollaborator),
      ),
      if (_showCollaborator) ...[
        const SizedBox(height: R.unit),
        AppField(controller: _who, hint: 'Name or handle', icon: Icons.alternate_email_rounded, type: TextInputType.text),
        const SizedBox(height: R.unit),
        PillButton(
          label: 'Send reminder',
          icon: Icons.send_rounded,
          loading: _saving,
          onPressed: _saving ? null : _sendToCollaborator,
        ),
      ],
    ]);
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.icon, required this.title, required this.sub, required this.onTap, this.enabled = true});
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => FlatCard(
        padding: const EdgeInsets.all(R.cardInset),
        onTap: enabled ? onTap : null,
        child: Row(children: [
          IconChip(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: titleStyle()),
              const SizedBox(height: 2),
              Text(sub, style: metaStyle()),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, size: 20, color: C.inkSoft),
        ]),
      );
}
