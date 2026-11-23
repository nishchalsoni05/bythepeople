import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:by_the_people/app/welfare_di.dart';
import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/domain/entities/club.dart';
import 'package:by_the_people/domain/entities/comment.dart';
import 'package:by_the_people/domain/entities/donation.dart';
import 'package:by_the_people/domain/entities/foundation.dart';
import 'package:by_the_people/domain/entities/gathering.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/domain/entities/query.dart';
import 'package:by_the_people/domain/repositories/welfare_repositories.dart';
import 'package:by_the_people/presentation/features/donations/create_donation_sheet.dart';
import 'package:by_the_people/presentation/features/donations/donation_detail_screen.dart';
import 'package:by_the_people/presentation/features/donations/donation_widgets.dart';
import 'package:by_the_people/presentation/features/donations/donations_screen.dart';
import 'package:by_the_people/presentation/features/foundations/foundations_screen.dart';
import 'package:by_the_people/presentation/features/gatherings/create_gathering_sheet.dart';
import 'package:by_the_people/presentation/features/gatherings/gathering_detail_screen.dart';
import 'package:by_the_people/presentation/features/gatherings/gatherings_screen.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/presentation/widgets/map.dart';

// ---------------------------------------------------------------- fakes

int _now() => DateTime.now().millisecondsSinceEpoch;

Map<String, dynamic> gJson(int id, {String status = 'upcoming', bool going = false, int? startAt, int? capacity, String type = 'plantation'}) => {
      'id': id,
      'title': 'Lakeside plantation drive number $id with a rather long title to test wrapping',
      'description': 'Bring gloves.',
      'type': type,
      'typeLabel': 'Plantation',
      'lat': 21.25,
      'lng': 81.63,
      'address': 'Telibandha Lake, Raipur',
      'startAt': startAt ?? _now() + 26 * 3600000,
      'status': status,
      'organizer': {'id': 9, 'name': 'Green Raipur Club', 'hue': 120, 'role': 'citizen'},
      'capacity': capacity,
      'goingCount': 12,
      'spotsLeft': capacity == null ? null : capacity - 12,
      'goingByMe': going,
      'voteCount': 2,
      'votesNeeded': 5,
      'votedByMe': false,
      'likeCount': 3,
      'commentCount': 1,
      'shareCount': 0,
      'attendees': [
        {'id': 1, 'name': 'Asha Verma', 'hue': 30},
        {'id': 2, 'name': 'Ravi', 'hue': 200},
      ],
    };

Map<String, dynamic> dJson(int id,
        {String kind = 'food', String status = 'available', int minutesLeft = 40, bool canClaim = false, bool claimedByMe = false, Map<String, dynamic>? claimedBy}) =>
    {
      'id': id,
      'kind': kind,
      'kindLabel': kind == 'food' ? 'Food' : 'Clothes',
      'title': 'Wedding dinner leftovers for $id people with a long title',
      'description': 'Hot dal and rice.',
      'quantity': '3 trays',
      'servings': 40,
      'veg': 'veg',
      'preparedAt': _now() - 30 * 60000,
      'expiresAt': _now() + minutesLeft * 60000,
      'freshness': 'critical',
      'lat': 21.25,
      'lng': 81.63,
      'address': 'Civil Lines, Raipur',
      'donor': {'id': 5, 'name': 'Meera', 'hue': 300, 'role': 'citizen'},
      'status': status,
      'canClaim': canClaim,
      'claimedByMe': claimedByMe,
      'claimedBy': claimedBy,
      'hygieneAck': true,
      'timeline': [
        {'status': 'available', 'note': null, 'createdAt': _now() - 600000, 'actor': {'id': 5, 'name': 'Meera', 'hue': 300}},
      ],
    };

class FakeGatherings extends Fake implements GatheringRepository {
  FakeGatherings(this.items);
  List<Gathering> items;
  final calls = <String>[];
  Object? rsvpError;

  @override
  Future<List<Gathering>> list({String when = 'upcoming', String? type, int? clubId, String sort = 'soon', String? query, GeoPoint? at}) async {
    calls.add('list:$when');
    return items;
  }

  @override
  Future<Gathering> detail(int id, {GeoPoint? at}) async => items.firstWhere((g) => g.id == id);

  @override
  Future<Outcome<Gathering>> rsvp(int id) async {
    calls.add('rsvp:$id');
    if (rsvpError != null) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      throw rsvpError!;
    }
    return Outcome(Gathering.fromJson(gJson(id, going: true)));
  }

  @override
  Future<Outcome<Gathering>> vote(int id) async {
    calls.add('vote:$id');
    return Outcome(items.first);
  }

  @override
  Future<Map<String, List<GatheringLite>>> calendar(String month) async {
    final d = DateTime.now();
    final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return {key: [GatheringLite(1, 'Beach cleanup crew', 'cleanup', _now())]};
  }

  @override
  Future<List<Club>> clubs() async => [
        const Club(id: 1, name: 'Raipur Run Club', description: 'Weekend runs', category: 'Fitness', hue: 200, memberCount: 31, joinedByMe: false, owner: null, upcomingCount: 2),
      ];

  @override
  Future<void> joinClub(int id) async => calls.add('join:$id');

  @override
  Future<List<Comment>> comments(int id) async => [];
}

class FakeDonations extends Fake implements DonationRepository {
  FakeDonations(this.items);
  List<Donation> items;
  final calls = <String>[];
  Object? claimError;

  @override
  Future<List<Donation>> list({String? kind, String status = 'available', String sort = 'expiring', GeoPoint? at}) async => items;

  @override
  Future<Donation> detail(int id, {GeoPoint? at}) async => items.firstWhere((d) => d.id == id);

  @override
  Future<List<Donation>> mine() async => items;

  @override
  Future<Outcome<Donation>> claim(int id, int etaMinutes) async {
    calls.add('claim:$id:$etaMinutes');
    if (claimError != null) throw claimError!;
    return Outcome(Donation.fromJson(dJson(id, status: 'claimed', claimedByMe: true)));
  }

  @override
  Future<Outcome<Donation>> create(DonationDraft draft) async {
    calls.add('create:${draft.kind}');
    return Outcome(Donation.fromJson(dJson(99)));
  }

  @override
  Future<List<Comment>> comments(int id) async => [];
}

class FakeFoundations extends Fake implements FoundationRepository {
  @override
  Future<List<Foundation>> list({String? query, String? need}) async => [
        Foundation.fromJson({
          'id': 1,
          'name': 'Seva Sankalp Foundation',
          'about': 'Feeding families across Raipur.',
          'needs': ['food', 'clothes'],
          'address': 'Pandri, Raipur',
          'verified': true,
          'hue': 150,
          'stats': {'claimed': 20, 'distributed': 18, 'beneficiaries': 640},
        }),
      ];

  @override
  Future<FoundationDashboard> dashboard() async => FoundationDashboard.fromJson({
        'stats': {'claimed': 4, 'distributed': 3, 'beneficiaries': 120},
        'activeClaims': [dJson(7, status: 'claimed', claimedByMe: true)],
        'nearbyAvailable': <dynamic>[],
        'needs': ['food'],
      });
}

class FakeAuth extends AuthNotifier {
  FakeAuth(this.user);
  final UserProfile user;
  @override
  AuthState build() => AuthState(ready: true, user: user);
  @override
  Future<void> refreshMe() async {}
}

class FakeLoc extends LocationNotifier {
  @override
  LocState build() => const LocState(lat: 21.25, lng: 81.63);
  @override
  Future<void> refresh() async {}
}

class FakePlatform implements WelfarePlatform {
  @override
  Future<PickedPhoto?> pickPhoto({required bool camera}) async => null;
  @override
  Future<void> share(String text) async {}
}

UserProfile user(String role, {bool verified = true}) =>
    UserProfile.fromJson({'id': 1, 'name': 'Asha Verma', 'email': 'a@b.c', 'role': role, 'verified': verified, 'orgName': role == 'foundation' ? 'Seva Sankalp' : null});

List<Override> overrides({
  List<Gathering>? gatherings,
  List<Donation>? donations,
  String role = 'citizen',
  bool verified = true,
  FakeGatherings? gRepo,
  FakeDonations? dRepo,
}) =>
    [
      gatheringRepositoryProvider.overrideWithValue(gRepo ?? FakeGatherings(gatherings ?? [])),
      donationRepositoryProvider.overrideWithValue(dRepo ?? FakeDonations(donations ?? [])),
      foundationRepositoryProvider.overrideWithValue(FakeFoundations()),
      welfarePlatformProvider.overrideWithValue(FakePlatform()),
      authProvider.overrideWith(() => FakeAuth(user(role, verified: verified))),
      locationProvider.overrideWith(FakeLoc.new),
    ];

Future<void> pumpApp(WidgetTester t, Widget child, List<Override> o, {Size size = const Size(360, 1800), double textScale = 1.15}) async {
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    t.view.reset();
    t.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await t.pumpWidget(ProviderScope(
    overrides: o,
    child: MaterialApp(theme: buildTheme(), home: Scaffold(body: child)),
  ));
  await settle(t);
}

/// Lets futures complete and animations run, without waiting on endless shimmers.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

/// Unmounts the tree and drains timers (toasts, polling) so the test can finish.
Future<void> finish(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 5));
}

Future<void> loadFonts() async {
  for (final f in const [('Jakarta', 'assets/fonts/PlusJakartaSans.ttf'), ('Fraunces', 'assets/fonts/Fraunces.ttf')]) {
    final bytes = await File(f.$2).readAsBytes();
    final loader = FontLoader(f.$1)..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

void main() {
  setUpAll(loadFonts);

  group('entities and helpers', () {
    test('Gathering.fromJson parses capacity and check-in window', () {
      final g = Gathering.fromJson(gJson(1, capacity: 12, startAt: _now() + 10 * 60000));
      expect(g.isFull, isTrue);
      expect(g.checkInOpenNow, isTrue);
      expect(Gathering.fromJson(gJson(2)).checkInOpenNow, isFalse);
    });

    test('Donation freshness follows the clock', () {
      final d = Donation.fromJson(dJson(1, minutesLeft: 30));
      expect(d.liveFreshness(), 'critical');
      expect(d.liveFreshness(DateTime.now().add(const Duration(minutes: 40))), 'expired');
      expect(Donation.fromJson(dJson(1, minutesLeft: 90)).liveFreshness(), 'soon');
      expect(Donation.fromJson(dJson(1, minutesLeft: 240)).liveFreshness(), 'fresh');
    });

    test('countdownText formats hours, minutes and seconds', () {
      expect(countdownText(0), 'Expired');
      expect(countdownText(125 * 60000), '2h 05m');
      expect(countdownText(12 * 60000 + 41000), '12:41');
    });

    test('DonationDraft omits food fields for other kinds', () {
      const d = DonationDraft(kind: 'clothes', title: 't', description: '', quantity: '2', address: 'a', lat: 1, lng: 2);
      expect(d.toJson().containsKey('preparedAt'), isFalse);
      expect(d.toJson()['hygieneAck'], false);
    });
  });

  group('gatherings', () {
    testWidgets('lists upcoming gatherings and RSVPs', (t) async {
      final repo = FakeGatherings([Gathering.fromJson(gJson(1, capacity: 30))]);
      await pumpApp(t, const GatheringsScreen(), overrides(gRepo: repo));
      expect(find.textContaining('Lakeside plantation'), findsOneWidget);
      expect(find.text('RSVP'), findsOneWidget);
      expect(find.textContaining('12 of 30 going'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.text('RSVP'));
      await settle(t);
      expect(repo.calls, contains('rsvp:1'));
      await finish(t);
    });

    testWidgets('RSVP is optimistic and rolls back with a friendly toast on failure', (t) async {
      final repo = FakeGatherings([Gathering.fromJson(gJson(1, capacity: 30))])..rsvpError = const ApiException('Server said no', 'X', 409);
      await pumpApp(t, const GatheringsScreen(), overrides(gRepo: repo));
      await t.tap(find.text('RSVP'));
      await t.pump();
      expect(find.text('Going'), findsOneWidget); // shown before the server answers
      await settle(t);
      expect(find.text('RSVP'), findsOneWidget); // rolled back
      expect(find.text('Server said no'), findsOneWidget);
      await finish(t);
    });

    testWidgets('detail shows the map preview and directions', (t) async {
      await pumpApp(t, const GatheringDetailScreen(id: 1), overrides(gatherings: [Gathering.fromJson(gJson(1))]));
      expect(find.byType(MapPreview), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
      await finish(t);
    });

    testWidgets('campaigns tab shows vote progress and voting', (t) async {
      final repo = FakeGatherings([Gathering.fromJson(gJson(2, status: 'proposed'))]);
      await pumpApp(t, const GatheringsScreen(), overrides(gRepo: repo), size: const Size(360, 1600));
      await t.tap(find.text('Campaigns'));
      await settle(t);
      expect(repo.calls, contains('list:proposed'));
      expect(find.textContaining('2 of 5 votes'), findsOneWidget);
      await t.tap(find.text('Vote to back it'));
      await settle(t);
      expect(repo.calls, contains('vote:2'));
      expect(t.takeException(), isNull);
      await finish(t);
    });

    testWidgets('calendar marks days and lists the selected day', (t) async {
      await pumpApp(t, const GatheringsScreen(), overrides(gatherings: []));
      await t.tap(find.text('Calendar'));
      await settle(t);
      expect(find.text('Beach cleanup crew'), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
    });

    testWidgets('clubs tab joins a club', (t) async {
      final repo = FakeGatherings([]);
      await pumpApp(t, const GatheringsScreen(), overrides(gRepo: repo));
      await t.tap(find.text('Clubs'));
      await settle(t);
      expect(find.text('Raipur Run Club'), findsOneWidget);
      await t.tap(find.text('Join'));
      await settle(t);
      expect(repo.calls, contains('join:1'));
      await finish(t);
    });

    testWidgets('detail shows check-in for an attendee near start time', (t) async {
      final g = Gathering.fromJson({...gJson(3, going: true, startAt: _now() + 5 * 60000), 'checkedInByMe': false});
      await pumpApp(t, const GatheringDetailScreen(id: 3), overrides(gatherings: [g]));
      expect(find.text('I am here, check in'), findsOneWidget);
      expect(find.text('Going'), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
    });
  });

  group('donations', () {
    testWidgets('citizen sees live freshness and no claim button', (t) async {
      await pumpApp(t, const DonationsScreen(), overrides(donations: [Donation.fromJson(dJson(1, canClaim: false))]));
      expect(find.textContaining('Critical'), findsWidgets);
      expect(find.text('Claim'), findsNothing);
      expect(t.takeException(), isNull);
      await finish(t);
    });

    testWidgets('verified foundation claims with an ETA', (t) async {
      final repo = FakeDonations([Donation.fromJson(dJson(1, minutesLeft: 200, canClaim: true))]);
      await pumpApp(t, const DonationsScreen(), overrides(dRepo: repo, role: 'foundation'), size: const Size(430, 1800));
      expect(find.text('Claim'), findsOneWidget);
      expect(find.text('Seva Sankalp'), findsNothing);
      await t.tap(find.text('Claim'));
      await settle(t);
      expect(find.text('Claim this donation'), findsOneWidget);
      await t.tap(find.text('Confirm claim'));
      await settle(t);
      expect(repo.calls.single, startsWith('claim:1:'));
      await finish(t);
    });

    testWidgets('ALREADY_CLAIMED is handled gracefully', (t) async {
      final repo = FakeDonations([Donation.fromJson(dJson(1, minutesLeft: 200, canClaim: true))])
        ..claimError = const ApiException('Already claimed', 'ALREADY_CLAIMED', 409, {'claimedBy': {'name': 'x', 'orgName': 'Annapurna Food Bank'}});
      await pumpApp(t, const DonationsScreen(), overrides(dRepo: repo, role: 'foundation'));
      await t.tap(find.text('Claim'));
      await settle(t);
      await t.tap(find.text('Confirm claim'));
      await settle(t);
      expect(find.textContaining('Annapurna Food Bank claimed this first'), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
    });

    testWidgets('unverified foundation sees the pending banner and cannot claim', (t) async {
      await pumpApp(t, const DonationsScreen(), overrides(donations: [Donation.fromJson(dJson(1, canClaim: false))], role: 'foundation', verified: false));
      expect(find.textContaining('Verification pending'), findsOneWidget);
      expect(find.text('Claim'), findsNothing);
      await finish(t);
    });

    testWidgets('detail offers distribute after pickup', (t) async {
      final d = Donation.fromJson(dJson(4, status: 'picked_up', claimedByMe: true, claimedBy: {'id': 1, 'name': 'Asha', 'orgName': 'Seva Sankalp', 'hue': 10}));
      await pumpApp(t, const DonationDetailScreen(id: 4), overrides(donations: [d], role: 'foundation'));
      expect(find.text('Mark distributed'), findsOneWidget);
      expect(find.text('Picked up'), findsWidgets);
      expect(t.takeException(), isNull);
      await finish(t);
    });

    testWidgets('detail shows donor the live claim status and cancel', (t) async {
      final d = Donation.fromJson({
        ...dJson(5, status: 'claimed', claimedBy: {'id': 2, 'name': 'Ravi', 'orgName': 'Annapurna Food Bank', 'hue': 40}),
        'donor': {'id': 1, 'name': 'Asha Verma', 'hue': 10},
        'etaAt': _now() + 20 * 60000,
        'lockExpiresAt': _now() + 45 * 60000,
      });
      await pumpApp(t, const DonationDetailScreen(id: 5), overrides(donations: [d]));
      expect(find.textContaining('Annapurna Food Bank arrives about'), findsOneWidget);
      expect(find.text('Cancel my listing'), findsOneWidget);
      await finish(t);
    });

    testWidgets('create sheet enforces food hygiene and previews expiry', (t) async {
      final repo = FakeDonations([]);
      await pumpApp(t, const CreateDonationSheet(), overrides(dRepo: repo), size: const Size(360, 2200));
      expect(find.byKey(const Key('expiry-preview')), findsOneWidget);
      await t.enterText(find.byKey(const Key('d-title')), 'Dal and rice');
      await t.enterText(find.byKey(const Key('d-servings')), '25');
      await t.enterText(find.byKey(const Key('d-address')), 'MG Road');
      final submit = find.text('List donation');
      await t.ensureVisible(submit);
      await t.tap(submit);
      await settle(t);
      expect(find.textContaining('prepared hygienically'), findsWidgets);
      expect(repo.calls, isEmpty);
      await t.ensureVisible(find.byKey(const Key('d-hygiene')));
      await t.tap(find.byKey(const Key('d-hygiene')));
      await t.pump();
      await t.ensureVisible(submit);
      await t.tap(submit);
      await settle(t);
      expect(repo.calls, ['create:food']);
      await finish(t);
    });
  });

  group('foundations', () {
    testWidgets('directory lists verified foundations', (t) async {
      await pumpApp(t, const FoundationsScreen(), overrides());
      expect(find.text('Seva Sankalp Foundation'), findsOneWidget);
      expect(find.textContaining('640 people helped'), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
    });

    testWidgets('dashboard header shows stats for a verified foundation', (t) async {
      await pumpApp(t, const DonationsScreen(), overrides(role: 'foundation'));
      expect(find.text('People helped'), findsOneWidget);
      expect(find.textContaining('Your active claims'), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
    });
  });

  group('no overflow at 360-430dp and 1.15 text scale', () {
    for (final w in [320.0, 360.0, 393.0, 430.0]) {
      testWidgets('screens at ${w.toInt()}dp', (t) async {
        final g = [
          Gathering.fromJson(gJson(1, capacity: 30, going: true)),
          Gathering.fromJson(gJson(2, status: 'proposed')),
        ];
        final d = [
          Donation.fromJson(dJson(1, minutesLeft: 20, canClaim: true)),
          Donation.fromJson(dJson(2, kind: 'clothes', minutesLeft: 5000)),
        ];
        final o = overrides(gatherings: g, donations: d, role: 'foundation');
        for (final screen in <Widget>[
          const GatheringsScreen(),
          const DonationsScreen(),
          const DonationsScreen(myClaims: true),
          const GatheringDetailScreen(id: 1),
          const DonationDetailScreen(id: 1),
          const CreateDonationSheet(),
          const CreateGatheringSheet(),
          const FoundationsScreen(),
        ]) {
          await pumpApp(t, screen, o, size: Size(w, 1400));
          expect(t.takeException(), isNull, reason: '${screen.runtimeType} at $w');
          await finish(t);
        }
      });
    }
  });
}
