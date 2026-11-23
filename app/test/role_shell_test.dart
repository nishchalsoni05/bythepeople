import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:by_the_people/app/app.dart';
import 'package:by_the_people/app/di.dart';
import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/domain/entities/portal.dart';
import 'package:by_the_people/domain/repositories/repositories.dart';
import 'package:by_the_people/presentation/features/admin/admin_dashboard_screen.dart';
import 'package:by_the_people/presentation/features/admin/admin_queue_screen.dart';
import 'package:by_the_people/presentation/features/admin/authority_sheet.dart';
import 'package:by_the_people/presentation/features/auth/auth_screen.dart';
import 'package:by_the_people/presentation/features/detail/issue_detail_screen.dart';
import 'package:by_the_people/presentation/features/feed/feed_screen.dart';
import 'package:by_the_people/presentation/features/neta_portal/neta_home_screen.dart';
import 'package:by_the_people/presentation/features/profile/profile_screen.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/presentation/widgets/cards.dart';
import 'package:by_the_people/presentation/widgets/ui.dart';

import 'responsive_test.dart' show loadFonts, pumpAt, issue;

Map<String, dynamic> userJson(String role, {bool verified = true}) => {
      'id': 7, 'name': 'Asha Verma', 'email': '$role@x.app', 'points': 10, 'hue': 120, 'volunteer': false,
      'alertRadiusKm': 5, 'rank': {'name': 'Rookie', 'index': 0, 'min': 0, 'progress': 0.2, 'next': 'Scout', 'nextAt': 50},
      'stats': {'reports': 1}, 'badges': [], 'role': role, 'verified': verified,
      if (role == 'foundation') ...{'orgName': 'Seva Sankalp Foundation', 'regNo': 'REG1', 'needs': ['food']},
      if (role == 'admin') 'departmentName': 'Raipur Municipal Corporation',
    };

class _FakeAuth implements AuthRepository {
  _FakeAuth({this.wrongPortalRole});
  final String? wrongPortalRole;
  String? lastRole;
  Map<String, dynamic>? lastRegister;

  @override
  Future<AuthSession> login(String email, String password, {String? role}) async {
    lastRole = role;
    if (wrongPortalRole != null && role != wrongPortalRole) {
      throw ApiException('This account is a $wrongPortalRole account', 'WRONG_PORTAL', 403);
    }
    return AuthSession('t', UserProfile.fromJson(userJson(role ?? 'citizen')));
  }

  @override
  Future<AuthSession> register(Map<String, dynamic> body) async {
    lastRegister = body;
    return AuthSession('t', UserProfile.fromJson(userJson(body['role'] as String)));
  }

  @override
  Future<bool> restoreSession() async => false;
  @override
  Future<CurrentUser> currentUser() async => CurrentUser(UserProfile.fromJson(userJson('citizen')), 0);
  @override
  Future<UserProfile> updateProfile(Map<String, dynamic> changes) async => UserProfile.fromJson(userJson('citizen'));
  @override
  Future<void> logout() async {}
  @override
  Future<void> clearSession() async {}
}

const _rawIssue = <String, dynamic>{
  'id': 1, 'title': 'No water supply for 3 days in a long named locality', 'description': 'x', 'category': 'water',
  'categoryLabel': 'Water Supply', 'status': 'open', 'phase': 'issue', 'severity': 'high', 'radiusKm': 3.0, 'lat': 21.2, 'lng': 81.6,
  'severityScore': 20.0, 'supportCount': 3, 'linkedCount': 0, 'volunteerCount': 0, 'threshold': 5, 'createdAt': 0,
  'reporter': {'id': 1, 'name': 'Anita Sahu', 'hue': 10}, 'supporters': [], 'volunteers': [], 'area': {},
  'escalated': true, 'authorityStatus': 'acknowledged', 'assignedTo': 'Ward engineer team A',
  'authority': {'name': 'Raipur Municipal Corporation', 'department': 'Public Works', 'handle': '@RMC_Raipur'},
};

AdminDashboard dashboard() => AdminDashboard.fromJson({
      'counts': {'open': 12, 'acknowledged': 4, 'inProgress': 6, 'pendingVerification': 2, 'closed': 30, 'escalated': 3},
      'avgResolutionHours': 52.5,
      'byCategory': [
        {'category': 'road', 'label': 'Roads & Potholes', 'count': 14, 'open': 6},
        {'category': 'garbage', 'label': 'Garbage', 'count': 9, 'open': 2},
      ],
      'topIssues': [
        {
          ...{
            'id': 1, 'title': 'No water supply for 3 days in a long named locality', 'description': 'x', 'category': 'water',
            'categoryLabel': 'Water Supply', 'status': 'open', 'phase': 'issue', 'severity': 'high', 'radiusKm': 3.0, 'lat': 21.2, 'lng': 81.6,
            'severityScore': 20.0, 'supportCount': 3, 'linkedCount': 0, 'volunteerCount': 0, 'threshold': 5, 'createdAt': 0,
            'reporter': {'id': 1, 'name': 'Anita Sahu', 'hue': 10}, 'supporters': [], 'volunteers': [], 'area': {},
            'escalated': true, 'authorityStatus': 'acknowledged', 'assignedTo': 'Ward engineer team A',
            'authority': {'name': 'Raipur Municipal Corporation', 'department': 'Public Works', 'handle': '@RMC_Raipur'},
          }
        },
      ],
      'pendingFoundations': 2,
      'recent': [
        {'status': 'open', 'note': 'Acknowledged by RMC', 'createdAt': 0, 'kind': 'authority'},
      ],
    });

void main() {
  setUpAll(loadFonts);

  group('models', () {
    test('UserProfile reads role fields and falls back to citizen', () {
      final f = UserProfile.fromJson(userJson('foundation', verified: false));
      expect(f.isFoundation, isTrue);
      expect(f.isVerifiedFoundation, isFalse);
      expect(f.displayName, 'Seva Sankalp Foundation');
      expect(f.needs, ['food']);
      final legacy = Map<String, dynamic>.from(userJson('citizen'))..remove('role')..remove('verified');
      final c = UserProfile.fromJson(legacy);
      expect(c.isCitizen, isTrue);
      expect(c.verified, isTrue);
    });

    test('Issue parses social and authority fields and tolerates their absence', () {
      final base = issue();
      expect(base.likeCount, 0);
      expect(base.authority, isNull);
      final i = Issue.fromJson({
        'id': 1, 'title': 't', 'description': '', 'category': 'water', 'categoryLabel': 'Water', 'status': 'open', 'phase': 'issue',
        'severity': 'low', 'radiusKm': 1, 'lat': 1, 'lng': 1, 'severityScore': 1, 'supportCount': 0, 'linkedCount': 0,
        'volunteerCount': 0, 'threshold': 5, 'createdAt': 0, 'reporter': {'id': 1, 'name': 'A', 'hue': 1}, 'area': {},
        'likeCount': 4, 'commentCount': 2, 'likedByMe': true, 'escalated': true, 'media': ['/uploads/a.jpg'],
        'authorityStatus': 'in_progress', 'authority': {'name': 'RMC', 'department': 'PW', 'handle': '@RMC'},
        'timeline': [
          {'status': 'in_progress', 'note': 'On it', 'createdAt': 1, 'kind': 'authority', 'media': ['/uploads/p.jpg'], 'actorRole': 'admin'},
        ],
      });
      expect(i.likedByMe, isTrue);
      expect(i.escalated, isTrue);
      expect(i.media, ['/uploads/a.jpg']);
      expect(i.authority!.handle, '@RMC');
      expect(i.timeline.single.kind, 'authority');
      expect(i.timeline.single.media.single, '/uploads/p.jpg');
    });

    test('Notification derives a deep link from issueId or refType', () {
      expect(AppNotification.fromJson({'id': 1, 'type': 'x', 'title': 't', 'issueId': 9, 'read': false, 'createdAt': 0}).refType, 'issue');
      final n = AppNotification.fromJson({'id': 1, 'type': 'donation', 'title': 't', 'refType': 'donation', 'refId': 4, 'read': false, 'createdAt': 0});
      expect((n.refType, n.refId), ('donation', 4));
    });
  });

  group('role shells', () {
    test('every role has its own tabs', () {
      List<String> labels(String r) => shellConfigFor(r).items.map((e) => e.label).toList();
      expect(labels('citizen'), ['Home', 'Calendar', 'Give', 'Profile']);
      expect(shellConfigFor('citizen').hasAdd, isTrue);
      expect(labels('admin'), ['Overview', 'Reports', 'Foundations', 'Profile']);
      expect(labels('neta'), ['Community', 'Priority', 'Gather', 'Profile']);
      expect(labels('foundation'), ['Donations', 'My claims', 'Gather', 'Profile']);
      for (final r in ['admin', 'neta', 'foundation']) {
        expect(shellConfigFor(r).hasAdd, isFalse, reason: '$r has no create button');
      }
      for (final r in ['citizen', 'admin', 'neta', 'foundation']) {
        final c = shellConfigFor(r);
        expect(c.pages.length, c.items.length);
      }
    });

    for (final w in [320.0, 360.0, 430.0]) {
      for (final scale in [1.0, 1.15]) {
        testWidgets('floating nav with centre create button fits @${w}x$scale', (t) async {
          var tab = -1;
          var added = 0;
          await pumpAt(
            t, Size(w, 700),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FloatingNav(
                  index: 0,
                  items: shellConfigFor('citizen').items,
                  addSlot: 2,
                  onChanged: (i) => tab = i,
                  onAdd: () => added++,
                  dotOnProfile: true,
                ),
              ),
            ),
            textScale: scale,
          );
          expect(t.takeException(), isNull);
          final r = t.getRect(find.byType(FloatingNav));
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(w + 0.5));
          await t.tap(find.byIcon(Icons.add_rounded));
          expect(added, 1);
          await t.tap(find.byIcon(Icons.volunteer_activism_rounded));
          expect(tab, 2); // third tab sits after the + button
          await t.tap(find.byIcon(Icons.person_rounded));
          expect(tab, 3);
        });
      }
    }

    testWidgets('admin shell shows admin tabs and the dashboard', (t) async {
      t.view.physicalSize = const Size(360, 780) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: _adminOverrides(),
        child: MaterialApp(theme: buildTheme(), home: const Shell()),
      ));
      await t.pump(const Duration(milliseconds: 900));
      expect(t.takeException(), isNull);
      expect(find.byIcon(Icons.dashboard_rounded), findsOneWidget);
      expect(find.byIcon(Icons.inbox_rounded), findsOneWidget);
      expect(find.byIcon(Icons.verified_user_rounded), findsWidgets);
      expect(find.text('Overview'), findsWidgets);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      // tear down timers
      await t.pumpWidget(const SizedBox());
    });
  });

  group('login', () {
    Future<_FakeAuth> pumpAuth(WidgetTester t, Size size, {double scale = 1.0, String? wrong}) async {
      final fake = _FakeAuth(wrongPortalRole: wrong);
      await pumpAt(t, size, const AuthScreen(), textScale: scale, overrides: [authRepositoryProvider.overrideWithValue(fake)]);
      return fake;
    }

    for (final w in [320.0, 360.0, 430.0]) {
      testWidgets('portal chooser and forms do not overflow @$w x1.15', (t) async {
        await pumpAuth(t, Size(w, 640), scale: 1.15);
        expect(t.takeException(), isNull);
        for (final p in portals.where((e) => !e.staff)) {
          expect(find.text(p.title), findsOneWidget);
        }
        await t.tap(find.text('Foundation'));
        await t.pump(const Duration(milliseconds: 500));
        await t.tap(find.text('Create account'));
        await t.pump(const Duration(milliseconds: 500));
        expect(t.takeException(), isNull);
        expect(find.text('Organisation name'), findsOneWidget);
        expect(find.text('Registration number'), findsOneWidget);
      });
    }

    testWidgets('demo quick-fill signs in through the chosen portal', (t) async {
      final fake = await pumpAuth(t, const Size(390, 844));
      await t.ensureVisible(find.text('Platform team? Sign in'));
      await t.tap(find.text('Platform team? Sign in'));
      await t.pump(const Duration(milliseconds: 300));
      await t.ensureVisible(find.text('Admin'));
      await t.tap(find.text('Admin'));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.textContaining('Fill demo admin'));
      await t.pump();
      expect(find.text('admin@bythepeople.app'), findsOneWidget);
      await t.tap(find.text('Sign in').last);
      await t.pump(const Duration(milliseconds: 100));
      expect(fake.lastRole, 'admin');
    });

    testWidgets('WRONG_PORTAL offers to switch to the right portal', (t) async {
      await pumpAuth(t, const Size(390, 844), wrong: 'neta');
      await t.tap(find.text('Volunteer'));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.textContaining('Fill demo volunteer'));
      await t.pump();
      await t.tap(find.text('Sign in').last);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('This is a Coordinator account'), findsOneWidget);
      await t.tap(find.text('Switch'));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Coordinator portal'), findsOneWidget);
    });

    testWidgets('foundation registration sends orgName and regNo', (t) async {
      final fake = await pumpAuth(t, const Size(390, 844));
      await t.tap(find.text('Foundation'));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.text('Create account'));
      await t.pump(const Duration(milliseconds: 500));
      Future<void> type(String hint, String v) async {
        await t.enterText(find.widgetWithText(TextField, hint), v);
      }

      await type('Your name (contact person)', 'Ravi Kumar');
      await type('Organisation name', 'Hope Trust');
      await type('Registration number', 'CG/123');
      await type('Email', 'hope@x.app');
      await type('Password (6+ characters)', 'secret12');
      await t.pump();
      await t.tap(find.text('Register foundation'));
      await t.pump(const Duration(milliseconds: 100));
      expect(fake.lastRegister?['role'], 'foundation');
      expect(fake.lastRegister?['orgName'], 'Hope Trust');
      expect(fake.lastRegister?['regNo'], 'CG/123');
    });
  });

  group('screens', () {
    for (final w in [360.0, 430.0]) {
      testWidgets('admin queue, neta home and detail render @$w x1.15', (t) async {
        final issues = dashboard().topIssues;
        final over = [
          ..._adminOverrides(),
          netaDashboardProvider.overrideWith((ref) async => NetaDashboard.fromJson({
                'politician': {'id': 1, 'name': 'Lakshmi Sahu', 'party': 'Chhattisgarh Jan Party', 'constituency': 'Ward 12', 'level': 'ward', 'hue': 30},
                'counts': {'open': 5, 'inProgress': 2, 'resolved': 9, 'escalated': 1},
                'resolutionRate': 0.64,
                'topIssues': <dynamic>[],
                'upcomingGatherings': [
                  {'id': 3, 'title': 'Plantation drive at Telibandha lake', 'typeLabel': 'Plantation', 'startAt': DateTime.now().millisecondsSinceEpoch + 86400000, 'goingCount': 12},
                ],
              })),
          netaFeedProvider.overrideWith((ref, q) async => issues),
          metaProvider.overrideWith((ref) async => <CategoryInfo>[]),
          issueProvider.overrideWith((ref, id) async => issues.first),
          commentsProvider.overrideWith((ref, id) async => [
                IssueComment.fromJson({'id': 1, 'body': 'We are on it, crew dispatched', 'createdAt': 0, 'author': {'id': 2, 'name': 'RMC Officer', 'hue': 10, 'role': 'admin'}}),
              ]),
        ];
        await pumpAt(t, Size(w, 800), const AdminQueueScreen(), textScale: 1.15, overrides: over);
        await t.pump(const Duration(milliseconds: 600));
        expect(t.takeException(), isNull);
        expect(find.text('Update'), findsOneWidget);
        await pumpAt(t, Size(w, 800), const NetaHomeScreen(), textScale: 1.15, overrides: over);
        await t.pump(const Duration(milliseconds: 1000));
        expect(t.takeException(), isNull);
        expect(find.text('Lakshmi Sahu'), findsOneWidget);
        expect(find.text('Escalate'), findsNothing); // already escalated: shows Withdraw
        expect(find.text('Withdraw'), findsWidgets);
        await pumpAt(t, Size(w, 800), const IssueDetailScreen(id: 1), textScale: 1.15, overrides: over);
        await t.pump(const Duration(milliseconds: 600));
        expect(t.takeException(), isNull);
        expect(find.text('Update status'), findsOneWidget); // admin sees the authority action
        await t.drag(find.byType(Scrollable).first, const Offset(0, -1200));
        await t.pump(const Duration(milliseconds: 400));
        expect(t.takeException(), isNull);
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('RMC Officer'), findsOneWidget);
      });

      testWidgets('citizen home dashboard renders @$w x1.15', (t) async {
        await pumpAt(t, Size(w, 800), const FeedScreen(), textScale: 1.15, overrides: [
          authProvider.overrideWith(() => _RoleAuth('citizen')),
          locationProvider.overrideWith(() => _NoLoc()),
          connectionProvider.overrideWith(() => _Online()),
          metaProvider.overrideWith((ref) async => [CategoryInfo('road', 'Roads & Potholes', 'road', 2)]),
          areasProvider.overrideWith((ref) async => <Area>[]),
          hereProvider.overrideWith((ref) async => null),
          scopeSummaryProvider.overrideWith((ref) async => ScopeSummary('city', 'Raipur', 1, 0, 1, 0, null, null)),
          feedProvider.overrideWith((ref, q) async => [issue(), Issue.fromJson({..._rawIssue, 'id': 9})]),
        ]);
        await t.pump(const Duration(milliseconds: 900));
        expect(t.takeException(), isNull);
        expect(find.text('Urgent right now'), findsOneWidget);
        expect(find.text('Open needs'), findsOneWidget);
        expect(find.text('Pledged'), findsOneWidget);
        expect(find.text('Fulfilled'), findsOneWidget);
        await t.pump(const Duration(milliseconds: 400));
        expect(t.takeException(), isNull);
      });

      testWidgets('authority sheet requires a note and proof to resolve @$w x1.15', (t) async {
        final issue0 = dashboard().topIssues.first;
        await pumpAt(
          t, Size(w, 700),
          Builder(builder: (ctx) => TextButton(onPressed: () => showAuthoritySheet(ctx, issue0), child: const Text('open'))),
          textScale: 1.15,
          overrides: _adminOverrides(),
        );
        await t.tap(find.text('open'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));
        expect(t.takeException(), isNull);
        await t.tap(find.text('Resolve'));
        await t.pump(const Duration(milliseconds: 300));
        final btn = find.ancestor(of: find.text('Mark resolved'), matching: find.byType(AnimatedOpacity)).first;
        expect(t.widget<AnimatedOpacity>(btn).opacity, lessThan(1)); // disabled until note + proof
        await t.enterText(find.byType(TextField).first, 'Pipeline repaired');
        await t.pump();
        expect(t.widget<AnimatedOpacity>(btn).opacity, lessThan(1)); // still needs a proof photo
        expect(t.takeException(), isNull);
      });

      testWidgets('foundation and neta profiles render @$w x1.15', (t) async {
        for (final role in ['foundation', 'neta', 'admin', 'citizen']) {
          await pumpAt(t, Size(w, 800), const ProfileScreen(), textScale: 1.15, overrides: [authProvider.overrideWith(() => _RoleAuth(role))]);
          await t.pump(const Duration(milliseconds: 500));
          expect(t.takeException(), isNull, reason: role);
          if (role == 'foundation') expect(find.text('Our needs'), findsOneWidget);
          if (role != 'citizen') expect(find.text('Leaders'), findsNothing);
        }
      });

      testWidgets('admin dashboard renders charts without overflow @$w x1.15', (t) async {
        await pumpAt(t, Size(w, 800), const AdminDashboardScreen(), textScale: 1.15, overrides: _adminOverrides());
        await t.pump(const Duration(milliseconds: 1000));
        expect(t.takeException(), isNull);
        expect(find.text('Status mix'), findsOneWidget);
        expect(find.text('By category'), findsOneWidget);
        expect(find.textContaining('2 foundations awaiting'), findsOneWidget);
        await t.drag(find.byType(Scrollable).first, const Offset(0, -900));
        await t.pump(const Duration(milliseconds: 400));
        expect(t.takeException(), isNull);
      });

      testWidgets('issue card with authority chip, escalation and actions @$w x1.15', (t) async {
        final i = Issue.fromJson({
          ...dashboard().topIssues.isEmpty ? {} : {},
          'id': 2, 'title': 'No water supply for 3 days in Devendra Nagar and the surrounding lanes', 'description': 'x', 'category': 'water',
          'categoryLabel': 'Water Supply', 'status': 'open', 'phase': 'issue', 'severity': 'critical', 'radiusKm': 3.0, 'lat': 21.2, 'lng': 81.6,
          'severityScore': 20.0, 'supportCount': 3, 'linkedCount': 0, 'volunteerCount': 0, 'threshold': 5, 'createdAt': 0,
          'reporter': {'id': 1, 'name': 'Anita Sahu', 'hue': 10}, 'supporters': [], 'volunteers': [], 'area': {},
          'likeCount': 128, 'commentCount': 42, 'shareCount': 9, 'escalated': true, 'authorityStatus': 'in_progress',
          'authority': {'name': 'Raipur Municipal Corporation', 'department': 'Public Works', 'handle': '@RMC_Raipur'},
        });
        await pumpAt(t, Size(w, 800), ListView(padding: const EdgeInsets.all(20), children: [IssueCard(issue: i, onTap: () {})]), textScale: 1.15);
        expect(t.takeException(), isNull);
        expect(find.text('Escalated'), findsOneWidget);
        expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
        expect(find.text('128'), findsOneWidget);
      });
    }
  });
}

List<Override> _adminOverrides() => [
      adminDashboardProvider.overrideWith((ref) async => dashboard()),
      adminIssuesProvider.overrideWith((ref, q) async => dashboard().topIssues),
      adminFoundationsProvider.overrideWith((ref, s) async => <FoundationRow>[]),
      authProvider.overrideWith(() => _AdminAuth()),
      locationProvider.overrideWith(() => _NoLoc()),
      connectionProvider.overrideWith(() => _Online()),
    ];

class _AdminAuth extends AuthNotifier {
  @override
  AuthState build() => AuthState(ready: true, user: UserProfile.fromJson(userJson('admin')), unread: 2);
  @override
  Future<void> refreshMe() async {}
}

class _RoleAuth extends AuthNotifier {
  _RoleAuth(this.role);
  final String role;
  @override
  AuthState build() => AuthState(ready: true, user: UserProfile.fromJson(userJson(role, verified: role != 'foundation')));
  @override
  Future<void> refreshMe() async {}
}

class _NoLoc extends LocationNotifier {
  @override
  Future<void> refresh() async {}
}

class _Online extends ConnectionNotifier {
  @override
  Future<void> check() async {
    await null;
    state = true;
  }
}
