import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/domain/entities/insights.dart';
import 'package:by_the_people/domain/repositories/insights_repository.dart';

class InsightsRepositoryImpl implements InsightsRepository {
  InsightsRepositoryImpl(this._api);
  final ApiClient _api;

  static Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static List<Map<String, dynamic>> _list(dynamic v) => v is List ? v.map(_m).toList() : const [];
  static num _n(dynamic v) => v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);
  static String _s(dynamic v) => v?.toString() ?? '';

  @override
  Future<Insights> insights() async {
    final j = await _api.get('/insights');
    final p = _m(j['period']);
    return Insights(
      period: InsightPeriod(_s(p['from']), _s(p['to'])),
      metrics: [
        for (final e in _list(j['metrics']))
          InsightMetric(
            key: _s(e['key']),
            label: _s(e['label']),
            value: _n(e['value']),
            delta: _n(e['delta']),
            deltaLabel: _s(e['deltaLabel']),
            positive: e['positive'] == true,
          ),
      ],
      weekly: [for (final e in _list(j['weekly'])) WeeklyPoint(_s(e['day']), _n(e['value']))],
      top: [
        for (final e in _list(j['top']))
          TopItem(
            id: _n(e['id']).toInt(),
            kind: _s(e['kind']),
            title: _s(e['title']),
            subtitle: _s(e['subtitle']),
            rate: _n(e['rate']),
            when: _s(e['when']),
          ),
      ],
    );
  }

  @override
  Future<Impact> impact() async {
    final j = await _api.get('/impact');
    return Impact(
      meals: _n(j['meals']),
      items: _n(j['items']),
      events: _n(j['events']),
      volunteerHours: _n(j['volunteerHours']),
    );
  }
}
