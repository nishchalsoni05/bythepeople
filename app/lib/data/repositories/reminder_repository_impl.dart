import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/domain/entities/reminder.dart';
import 'package:by_the_people/domain/repositories/reminder_repository.dart';

class ReminderRepositoryImpl implements ReminderRepository {
  ReminderRepositoryImpl(this._api);
  final ApiClient _api;

  static Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static num _n(dynamic v) => v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);
  static String _s(dynamic v) => v?.toString() ?? '';

  static Reminder _parse(Map<String, dynamic> e) {
    final hasRecipient = e['recipient'] is Map;
    final r = _m(e['recipient']);
    return Reminder(
      id: _n(e['id']).toInt(),
      title: _s(e['title']),
      scope: ReminderScope.values.firstWhere((s) => s.name == _s(e['scope']), orElse: () => ReminderScope.me),
      recipient: hasRecipient
          ? ReminderRecipient(
              id: _n(r['id']).toInt(),
              name: _s(r['name']),
              hue: _n(r['hue']).toInt(),
              role: _s(r['role']),
              orgName: r['orgName'] == null ? null : _s(r['orgName']),
            )
          : null,
      remindAt: DateTime.fromMillisecondsSinceEpoch(_n(e['remindAt']).toInt()),
      refType: e['refType'] == null ? null : _s(e['refType']),
      refId: e['refId'] == null ? null : _n(e['refId']).toInt(),
      done: e['done'] == true,
      mine: e['mine'] == true,
    );
  }

  @override
  Future<List<Reminder>> list() async {
    final j = await _api.get('/reminders');
    final items = j['items'];
    if (items is! List) return const [];
    return [for (final e in items) _parse(_m(e))];
  }

  @override
  Future<Reminder> create(ReminderDraft d) async {
    final j = await _api.post('/reminders', {
      'title': d.title,
      'scope': d.scope.name,
      'remindAt': d.remindAt.millisecondsSinceEpoch,
      if (d.refType != null) 'refType': d.refType,
      if (d.refId != null) 'refId': d.refId,
      if (d.recipientId != null) 'recipientId': d.recipientId,
    });
    return _parse(_m(j['reminder']));
  }

  @override
  Future<void> delete(int id) async {
    await _api.delete('/reminders/$id');
  }
}
