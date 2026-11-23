import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/domain/entities/insights.dart';
import 'package:by_the_people/presentation/providers/insights_providers.dart';
import 'package:by_the_people/presentation/widgets/layout.dart';
import 'package:by_the_people/presentation/widgets/skeleton.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

const _positive = Color(0xFF1E8E4E);

/// Pushed page: the user's metrics, weekly activity, community impact and top performing items.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  void _retry(WidgetRef ref) {
    ref.invalidate(insightsProvider);
    ref.invalidate(impactProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pad = MediaQuery.of(context).padding;
    final insights = ref.watch(insightsProvider);
    final impact = ref.watch(impactProvider).asData?.value;

    final List<Widget> body;
    if (insights.isLoading && !insights.hasValue) {
      body = const [RowListSkeleton(count: 4)];
    } else if (insights.hasError && !insights.hasValue) {
      body = [ErrorState(error: insights.error ?? 'error', onRetry: () => _retry(ref))];
    } else {
      body = _content(insights.asData?.value, impact);
    }

    return Scaffold(
      body: PageBackdrop(
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, pad.top + 8, 16, 0),
            child: Row(children: [
              CircleBtn(icon: Icons.arrow_back_rounded, size: 42, onTap: () => Navigator.of(context).pop()),
              const SizedBox(width: 14),
              Expanded(child: Text('Insights', style: ui(17, color: C.inkSoft, w: 700))),
              const CircleBtn(icon: Icons.more_horiz_rounded, size: 42),
            ]),
          ),
          Expanded(
            child: ContentWidth(
              child: RefreshIndicator(
                onRefresh: () async {
                  _retry(ref);
                  try {
                    await ref.read(insightsProvider.future);
                  } catch (_) {
                    // The error state renders the failure; pull-to-refresh just settles.
                  }
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, 12, 16, pad.bottom + 110),
                  children: body,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _content(Insights? data, Impact? impact) {
    return [
      if (data != null && data.hasNothing)
        const EmptyState(title: 'No insights yet', body: 'Reports, events and donations you take part in will show up here.'),
      if (data != null && data.metrics.isNotEmpty) _MetricGrid(metrics: data.metrics),
      if (data != null && data.weekly.isNotEmpty) ...[
        const SizedBox(height: 18),
        const SectionTitle('This week'),
        _WeeklyChart(points: data.weekly),
      ],
      const SizedBox(height: 18),
      const SectionTitle('Impact'),
      _ImpactRow(impact: impact),
      if (data != null && data.top.isNotEmpty) ...[
        const SizedBox(height: 18),
        const SectionTitle('Top performing'),
        for (final item in data.top.take(5)) _TopRow(item: item),
      ],
    ];
  }
}

/// Plain number: thousands separators, one decimal only when fractional.
String _fmt(num v) {
  if (v % 1 != 0) return v.toStringAsFixed(1);
  return v.toInt().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});
  final List<InsightMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < metrics.length; i++)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 300 + 70 * i),
            curve: Curves.easeOutCubic,
            builder: (_, t, c) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: c)),
            child: FlatCard(padding: const EdgeInsets.all(R.cardInset), child: _MetricBody(metric: metrics[i])),
          ),
      ],
    );
  }
}

class _MetricBody extends StatelessWidget {
  const _MetricBody({required this.metric});
  final InsightMetric metric;

  @override
  Widget build(BuildContext context) {
    final color = metric.positive ? _positive : C.danger;
    final sign = metric.delta > 0 ? '+' : '';
    final deltaText = metric.deltaLabel.isNotEmpty ? metric.deltaLabel : '$sign${_fmt(metric.delta)}';
    final value = metric.key == 'claim_rate' ? '${(metric.value * 100).round()}%' : _fmt(metric.value);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(metric.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: metaStyle()),
      SizedBox(height: 6),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: numStyle(24, w: 700)),
      SizedBox(height: 6),
      Row(children: [
        Icon(metric.positive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: color),
        const SizedBox(width: 3),
        Expanded(child: Text(deltaText, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(12, color: color, w: 650).copyWith(fontFeatures: const [FontFeature.tabularFigures()]))),
      ]),
    ]);
  }
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.points});
  final List<WeeklyPoint> points;

  @override
  Widget build(BuildContext context) {
    final maxV = points.fold<num>(0, (a, p) => p.value > a ? p.value : a);
    return FlatCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      radius: 20,
      child: Column(children: [
        SizedBox(
          height: 130,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final p in points)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    if (maxV > 0 && p.value == maxV) Text(_fmt(p.value), style: ui(11, w: 700)),
                    if (maxV > 0 && p.value == maxV) const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: maxV <= 0 ? 4 : math.max(4, (p.value / maxV * 100).toDouble()),
                      decoration: BoxDecoration(
                        color: maxV > 0 && p.value == maxV ? C.ink : C.ink.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          for (final p in points)
            Expanded(
              child: Text(
                p.day.length > 3 ? p.day.substring(0, 3) : p.day,
                textAlign: TextAlign.center,
                style: ui(11.5, color: C.inkSoft, w: 600),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _ImpactRow extends StatelessWidget {
  const _ImpactRow({required this.impact});
  final Impact? impact;

  @override
  Widget build(BuildContext context) {
    final i = impact;
    final tiles = [
      ('Meals', i == null ? '–' : _fmt(i.meals)),
      ('Items', i == null ? '–' : _fmt(i.items)),
      ('Events', i == null ? '–' : _fmt(i.events)),
      ('Volunteer hrs', i == null ? '–' : _fmt(i.volunteerHours)),
    ];
    return Row(children: [
      for (var k = 0; k < tiles.length; k++) ...[
        if (k > 0) const SizedBox(width: 8),
        Expanded(
          child: FlatCard(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            radius: 16,
            child: Column(children: [
              Text(tiles[k].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(17, w: 700)),
              const SizedBox(height: 4),
              Text(tiles[k].$1, textAlign: TextAlign.center, maxLines: 2, style: ui(11, color: C.inkSoft, w: 600, h: 1.2)),
            ]),
          ),
        ),
      ],
    ]);
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({required this.item});
  final TopItem item;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FlatCard(
          padding: const EdgeInsets.all(14),
          radius: 18,
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: C.muted, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.auto_graph_rounded, size: 20, color: C.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(14.5, w: 700)),
                const SizedBox(height: 2),
                Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(12.5, color: C.inkSoft)),
              ]),
            ),
            const SizedBox(width: 12),
            Text('${(item.rate * 100).round()}%', style: ui(16, w: 700)),
          ]),
        ),
      );
}
