import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/app/di.dart';
import 'package:by_the_people/data/repositories/reminder_repository_impl.dart';
import 'package:by_the_people/domain/repositories/reminder_repository.dart';

/// Composition root for reminders. Kept apart from di.dart so each feature owns its wiring.
final reminderRepositoryProvider =
    Provider<ReminderRepository>((ref) => ReminderRepositoryImpl(ref.watch(apiClientProvider)));
