import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/core/i18n/strings.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/providers/locale_provider.dart';
import 'package:by_the_people/presentation/features/admin/admin_dashboard_screen.dart';
import 'package:by_the_people/presentation/features/admin/admin_foundations_screen.dart';
import 'package:by_the_people/presentation/features/admin/admin_queue_screen.dart';
import 'package:by_the_people/presentation/features/create/create_sheet.dart';
import 'package:by_the_people/presentation/features/donations/donations_screen.dart';
import 'package:by_the_people/presentation/features/gatherings/gatherings_screen.dart';
import 'package:by_the_people/presentation/features/neta_portal/neta_escalated_screen.dart';
import 'package:by_the_people/presentation/features/neta_portal/neta_home_screen.dart';
import 'package:by_the_people/presentation/features/auth/auth_screen.dart';
import 'package:by_the_people/presentation/features/feed/feed_screen.dart';
import 'package:by_the_people/presentation/features/profile/profile_screen.dart';
import 'package:by_the_people/presentation/providers/providers.dart';
import 'package:by_the_people/presentation/widgets/brand_mark.dart';

import 'package:by_the_people/presentation/widgets/ui.dart';
import 'package:by_the_people/presentation/widgets/layout.dart';

class ByThePeopleApp extends StatelessWidget {
  const ByThePeopleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'By the People',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // Large accessibility font sizes are honoured up to 1.15x so layouts never overflow.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          final scale = mq.textScaler.scale(1.0).clamp(0.9, 1.15);
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark, statusBarBrightness: Brightness.light),
            child: MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          );
        },
        home: const AuthGate(),
      );
}

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(authProvider.notifier).init());
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    Widget child;
    if (!auth.ready) {
      child = const Scaffold(body: PageBackdrop(child: Center(child: BrandMark(size: 120))));
    } else if (auth.user == null) {
      child = const AuthScreen();
    } else {
      child = const Shell();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      child: KeyedSubtree(
        key: ValueKey(auth.ready ? (auth.user == null ? 'auth' : 'shell') : 'splash'),
        child: child,
      ),
    );
  }
}

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> with WidgetsBindingObserver {
  final Set<int> _visited = {0};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(locationProvider.notifier).refresh();
    ref.read(connectionProvider.notifier).check();
    Future.microtask(() => ref.read(shellTabProvider.notifier).go(0));
    // Poll for alerts and location (no push service in local mode).
    _timer = Timer.periodic(const Duration(seconds: 8), (t) {
      ref.read(connectionProvider.notifier).check();
      // Keep every list in sync with the server (likes, comments, status changes by others).
      if (t.tick % 4 == 0) ref.read(tickProvider.notifier).bump();
      if (t.tick % 3 == 0) {
        ref.read(locationProvider.notifier).refresh();
        ref.read(authProvider.notifier).refreshMe().catchError((_) {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(connectionProvider.notifier).check();
      ref.read(locationProvider.notifier).refresh();
      ref.read(tickProvider.notifier).bump();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final unread = ref.watch(authProvider.select((s) => s.unread));
    final role = ref.watch(roleProvider);
    final cfg = shellConfigFor(role, ref.watch(localeProvider));
    final tab = ref.watch(shellTabProvider).clamp(0, cfg.items.length - 1);
    _visited.add(tab);
    return Scaffold(
      extendBody: true,
      body: Stack(children: [
        const Positioned.fill(child: PageBackdrop(child: SizedBox.expand())),
        Positioned.fill(
          child: IndexedStack(
            index: tab,
            children: [
              for (var i = 0; i < cfg.items.length; i++)
                // Pages are built the first time they are opened, then kept alive.
                _visited.contains(i) ? ContentWidth(child: cfg.pages[i]()) : const SizedBox.shrink(),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: pad.bottom + 12,
          child: Center(
            child: FloatingNav(
              index: tab,
              items: cfg.items,
              addSlot: cfg.addSlot,
              onChanged: (i) => ref.read(shellTabProvider.notifier).go(i),
              onAdd: cfg.hasAdd ? () => showCreateSheet(context) : null,
              dotOnProfile: unread > 0,
            ),
          ),
        ),
      ]),
    );
  }
}

/// Tabs for one role: nav items, lazily built pages, and where the centre "+" sits (null = none).
class ShellConfig {
  const ShellConfig(this.items, this.pages, {this.addSlot, this.hasAdd = false});
  final List<NavItem> items;
  final List<Widget Function()> pages;
  final int? addSlot;
  final bool hasAdd;
}

ShellConfig shellConfigFor(String role, [String lang = 'en']) {
  String t(String k) => Strings.instance.get(k, lang);
  switch (role) {
    case 'admin':
      return ShellConfig(
        const [
          NavItem(Icons.dashboard_rounded, 'Overview'),
          NavItem(Icons.inbox_rounded, 'Reports'),
          NavItem(Icons.verified_user_rounded, 'Foundations'),
          NavItem(Icons.person_rounded, 'Profile'),
        ],
        [
          () => const AdminDashboardScreen(),
          () => const AdminQueueScreen(),
          () => const AdminFoundationsScreen(),
          () => const ProfileScreen(),
        ],
      );
    case 'neta':
      return ShellConfig(
        const [
          NavItem(Icons.hub_rounded, 'Community'),
          NavItem(Icons.trending_up_rounded, 'Priority'),
          NavItem(Icons.diversity_3_rounded, 'Gather'),
          NavItem(Icons.person_rounded, 'Profile'),
        ],
        [
          () => const NetaHomeScreen(),
          () => const NetaEscalatedScreen(),
          () => const GatheringsScreen(),
          () => const ProfileScreen(),
        ],
      );
    case 'foundation':
      return ShellConfig(
        const [
          NavItem(Icons.volunteer_activism_rounded, 'Donations'),
          NavItem(Icons.inventory_2_rounded, 'My claims'),
          NavItem(Icons.diversity_3_rounded, 'Gather'),
          NavItem(Icons.person_rounded, 'Profile'),
        ],
        [
          () => const DonationsScreen(),
          () => const DonationsScreen(myClaims: true),
          () => const GatheringsScreen(),
          () => const ProfileScreen(),
        ],
      );
    default:
      return ShellConfig(
        [
          NavItem(Icons.home_rounded, t('nav_home')),
          NavItem(Icons.calendar_month_rounded, t('nav_calendar')),
          NavItem(Icons.volunteer_activism_rounded, t('nav_give')),
          NavItem(Icons.person_rounded, t('nav_profile')),
        ],
        [
          () => const FeedScreen(),
          () => const GatheringsScreen(),
          () => const DonationsScreen(),
          () => const ProfileScreen(),
        ],
        hasAdd: true,
      );
  }
}
