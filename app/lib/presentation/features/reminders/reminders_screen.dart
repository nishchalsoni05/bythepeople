import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/app/reminders_di.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/domain/entities/reminder.dart';
import 'package:by_the_people/presentation/providers/locale_provider.dart';
import 'package:by_the_people/presentation/providers/reminder_providers.dart';
import 'package:by_the_people/presentation/widgets/cards.dart';
import 'package:by_the_people/presentation/widgets/layout.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

/// Pushed list of upcoming reminders. The creator can delete their own reminders.
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  Future<void> _delete(BuildContext context, WidgetRef ref, Reminder r) async {
    try {
      await ref.read(reminderRepositoryProvider).delete(r.id);
      ref.invalidate(remindersProvider);
    } catch (e) {
      if (context.mounted) toastError(context, e, fallback: 'Could not delete the reminder.');
    }
  }

  static String _scopeLabel(Reminder r) => switch (r.scope) {
        ReminderScope.me => 'Only you',
        ReminderScope.space => 'Space collaborators',
        ReminderScope.collaborator => 'Sent to ${r.recipient?.name ?? 'a collaborator'}',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(remindersProvider);
    final materials = MaterialLocalizations.of(context);
    return PushedPage(
      title: tr(ref, 'reminders_title'),
      child: async.when(
        loading: () => const LoadingOrb(),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(remindersProvider)),
        data: (items) {
          final open = items.where((r) => !r.done).toList();
          if (open.isEmpty) {
            return const EmptyState(title: 'No reminders yet', body: 'Reminders you set for yourself, your space or a collaborator appear here.');
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
            itemCount: open.length,
            separatorBuilder: (context, index) => const SizedBox(height: R.unit),
            itemBuilder: (context, i) {
              final r = open[i];
              final when = '${materials.formatMediumDate(r.remindAt)} · ${materials.formatTimeOfDay(TimeOfDay.fromDateTime(r.remindAt))}';
              return FlatCard(
                padding: const EdgeInsets.fromLTRB(R.cardInset, R.cardInset, R.unit, R.cardInset),
                child: Row(children: [
                  const IconChip(Icons.notifications_none_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: titleStyle()),
                      const SizedBox(height: 2),
                      Text(when, style: numStyle(12, color: C.inkSoft, w: 500)),
                      const SizedBox(height: R.unit),
                      StatusDot(color: r.mine ? C.ink : C.ember, label: _scopeLabel(r)),
                    ]),
                  ),
                  if (r.mine)
                    IconButton(
                      tooltip: 'Delete reminder',
                      icon: const Icon(Icons.delete_outline_rounded, color: C.inkSoft),
                      onPressed: () => _delete(context, ref, r),
                    ),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
