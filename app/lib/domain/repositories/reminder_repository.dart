import 'package:by_the_people/domain/entities/reminder.dart';

/// Reminders visible to the signed-in user, sorted by remind time.
abstract interface class ReminderRepository {
  Future<List<Reminder>> list();
  Future<Reminder> create(ReminderDraft draft);
  Future<void> delete(int id);
}
