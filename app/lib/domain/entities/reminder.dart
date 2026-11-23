/// Who a reminder is visible to: only the creator, everyone in the space, or one collaborator.
enum ReminderScope { me, space, collaborator }

class ReminderRecipient {
  const ReminderRecipient({required this.id, required this.name, required this.hue, required this.role, this.orgName});
  final int id;
  final String name;
  final int hue;
  final String role;
  final String? orgName;
}

class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    required this.scope,
    required this.recipient,
    required this.remindAt,
    required this.refType,
    required this.refId,
    required this.done,
    required this.mine,
  });
  final int id;
  final String title;
  final ReminderScope scope;
  final ReminderRecipient? recipient;
  final DateTime remindAt;
  final String? refType;
  final int? refId;
  final bool done;

  /// True when the signed-in user created this reminder (only the creator may delete it).
  final bool mine;
}

/// Payload for creating a reminder.
class ReminderDraft {
  const ReminderDraft({required this.title, required this.scope, required this.remindAt, this.refType, this.refId, this.recipientId});
  final String title;
  final ReminderScope scope;
  final DateTime remindAt;
  final String? refType;
  final int? refId;
  final int? recipientId;
}
