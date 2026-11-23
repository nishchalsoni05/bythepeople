import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/app/reminders_di.dart';
import 'package:by_the_people/domain/entities/reminder.dart';
import 'package:by_the_people/presentation/providers/session_providers.dart';

/// Reminders for the signed-in user. Invalidate after creating or deleting one.
final remindersProvider = FutureProvider<List<Reminder>>((ref) {
  ref.watch(tickProvider);
  return ref.read(reminderRepositoryProvider).list();
});
