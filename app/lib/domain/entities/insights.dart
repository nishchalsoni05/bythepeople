// Personal insights (GET /insights) and community impact totals (GET /impact).

class InsightPeriod {
  final String from;
  final String to;
  const InsightPeriod(this.from, this.to);
}

class InsightMetric {
  final String key;
  final String label;
  final num value;
  final num delta;
  final String deltaLabel;
  final bool positive;
  const InsightMetric({
    required this.key,
    required this.label,
    required this.value,
    required this.delta,
    required this.deltaLabel,
    required this.positive,
  });
}

class WeeklyPoint {
  final String day;
  final num value;
  const WeeklyPoint(this.day, this.value);
}

class TopItem {
  final int id;
  final String kind;
  final String title;
  final String subtitle;
  /// Success rate as a percentage (0-100).
  final num rate;
  final String when;
  const TopItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.rate,
    required this.when,
  });
}

class Insights {
  final InsightPeriod period;
  final List<InsightMetric> metrics;
  final List<WeeklyPoint> weekly;
  final List<TopItem> top;
  const Insights({required this.period, required this.metrics, required this.weekly, required this.top});

  bool get hasNothing => metrics.isEmpty && top.isEmpty && weekly.every((p) => p.value == 0);
}

class Impact {
  final num meals;
  final num items;
  final num events;
  final num volunteerHours;
  const Impact({required this.meals, required this.items, required this.events, required this.volunteerHours});
}
