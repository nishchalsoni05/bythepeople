import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/widgets/cards.dart';
import 'package:by_the_people/presentation/widgets/neta_card.dart';
import 'package:by_the_people/presentation/widgets/neta_deck.dart';
import 'package:by_the_people/presentation/widgets/scope_bar.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';
import 'package:by_the_people/presentation/features/neta/neta_screen.dart';

/// Typical phone viewport sizes in logical points.
const sizes = <String, Size>{
  'small 320x568': Size(320, 568),
  'compact 360x640': Size(360, 640),
  'iPhone SE 375x667': Size(375, 667),
  'standard 390x844': Size(390, 844),
  'Pro 402x874': Size(402, 874),
  'Pro Max 430x932': Size(430, 932),
};

Neta neta(int i, String rarity) => Neta(
      id: i, hue: i * 40, name: 'Hemant Chandrakar the Third', party: 'Chhattisgarh Jan Party', constituency: 'Devendra Nagar Ward',
      level: 'ward', city: 'Bhilai-Durg', state: 'Chhattisgarh', region: 'Central India',
      stats: NetaStats(10, 7, 3, 0, 5, 0.7, 12, 0.7, true, rarity),
    );

Issue issue() => Issue.fromJson({
      'id': 1, 'title': 'No water supply for 3 days in Devendra Nagar and the surrounding lanes', 'description': 'x', 'category': 'water',
      'categoryLabel': 'Water Supply', 'status': 'open', 'phase': 'issue', 'severity': 'critical', 'radiusKm': 3.0, 'lat': 21.2, 'lng': 81.6,
      'severityScore': 20.0, 'supportCount': 3, 'linkedCount': 0, 'volunteerCount': 0, 'threshold': 5, 'createdAt': 0,
      'reporter': {'id': 1, 'name': 'Anita Sahu', 'hue': 10}, 'distanceKm': 0.4, 'inRange': true,
      'supporters': [], 'volunteers': [], 'area': {},
    });

Future<void> pumpAt(WidgetTester t, Size size, Widget child, {double textScale = 1.0, List<Override> overrides = const []}) async {
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    t.view.reset();
    t.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await t.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: buildTheme(),
      builder: (context, c) {
        final mq = MediaQuery.of(context);
        final s = mq.textScaler.scale(1.0).clamp(0.9, 1.15); // same clamp as the real app
        return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(s)), child: c!);
      },
      home: Scaffold(body: child),
    ),
  ));
  await t.pump(const Duration(milliseconds: 700));
}

Future<void> loadFonts() async {
  for (final f in const [('Jakarta', 'assets/fonts/PlusJakartaSans.ttf'), ('Fraunces', 'assets/fonts/Fraunces.ttf')]) {
    final bytes = await File(f.$2).readAsBytes();
    final loader = FontLoader(f.$1)..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

/// The deck integrates physics with a per-frame dt clamp, so advance in real frame steps.
Future<void> frames(WidgetTester t, [int n = 90]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUpAll(loadFonts);
  for (final e in sizes.entries) {
    for (final scale in [1.0, 1.4]) {
      final label = '${e.key} @${scale}x text';

      testWidgets('floating nav fits: $label', (t) async {
        await pumpAt(t, e.value, Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 12), child: FloatingNav(index: 0, onChanged: (_) {}, onAdd: () {}))), textScale: scale);
        expect(t.takeException(), isNull);
        final r = t.getRect(find.byType(FloatingNav));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(e.value.width + 0.5));
      });

      testWidgets('issue card + controls: $label', (t) async {
        await pumpAt(t, e.value, ListView(padding: const EdgeInsets.all(20), children: [
          IssueCard(issue: issue(), onTap: () {}),
          const SegmentedToggle(labels: ['Issues', 'Events', 'Resolved'], index: 0, onChanged: _noop),
          const SizedBox(height: 12),
          const PillButton(label: 'Too far · 2.3 km away (max 1 km)', onPressed: null),
        ]), textScale: scale);
        expect(t.takeException(), isNull);
      });

      testWidgets('Neta screen (real layout) fits and swipes: $label', (t) async {
        final items = [neta(1, 'epic'), neta(2, 'legendary'), neta(3, 'common'), neta(4, 'unrated')];
        final summary = ScopeSummary('city', 'Raipur', 51, 23, 4, 4, 0.45, 12);
        await pumpAt(t, e.value, const NetaScreen(), textScale: scale, overrides: [
          netasProvider.overrideWith((ref) async => NetaList(items, ['Chhattisgarh Jan Party'])),
          netaTreeProvider.overrideWith((ref) async => items),
          scopeSummaryProvider.overrideWith((ref) async => summary),
          areasProvider.overrideWith((ref) async => [Area(1, 'Raipur', 'city', null)]),
          hereProvider.overrideWith((ref) async => {'city': {'id': 1, 'name': 'Raipur'}}),
        ]);
        await frames(t, 30);
        expect(t.takeException(), isNull);
        final deck = t.getRect(find.byType(NetaDeck));
        // everything must sit above the floating nav (nav clearance is measured from the bottom)
        final ctx = t.element(find.byType(NetaScreen));
        final limit = e.value.height - navClearance(ctx);
        expect(deck.bottom, lessThanOrEqualTo(limit + 1), reason: 'deck bottom ${deck.bottom} must clear the nav at $limit');
        expect(deck.left, greaterThanOrEqualTo(0));
        expect(deck.right, lessThanOrEqualTo(e.value.width + 0.5));
        await t.drag(find.byType(HoloNetaCard).last, Offset(e.value.width, 0), warnIfMissed: false);
        await frames(t);
        expect(t.takeException(), isNull);
        expect(find.text('2 / 4'), findsOneWidget);
        await t.tap(find.byIcon(Icons.undo_rounded));
        await frames(t);
        expect(find.text('1 / 4'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('scope bar renders with long area names on the narrowest phone', (t) async {
    await pumpAt(t, sizes['small 320x568']!, const Padding(padding: EdgeInsets.all(20), child: ScopeBar()), overrides: [
      areasProvider.overrideWith((ref) async => [Area(1, 'A Very Long Region Name For Testing', 'region', null)]),
      hereProvider.overrideWith((ref) async => {'city': {'id': 1, 'name': 'Bhilai-Durg Industrial Township'}}),
    ]);
    expect(t.takeException(), isNull);
  });
}

void _noop(int _) {}
