import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/state.dart';
import 'core/tokens.dart';
import 'core/widgets/brand_mark.dart';
import 'core/widgets/shaders.dart';
import 'core/widgets/ui.dart';
import 'features/activity/activity_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/feed/feed_screen.dart';
import 'features/neta/neta_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/report/report_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ShaderLib.load(); // compile shaders on splash
  // Phone UI is portrait-only; this also keeps the motion-sensor axes stable for the cards.
  await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarBrightness: Brightness.light, statusBarIconBrightness: Brightness.dark));
  // Riverpod 3 retries failed providers; we show our own retry button instead.
  runApp(ProviderScope(retry: (_, __) => null, child: const ByThePeopleApp()));
}

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
          return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(scale)), child: child!);
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
    return AnimatedSwitcher(duration: const Duration(milliseconds: 450), child: KeyedSubtree(key: ValueKey(auth.ready ? (auth.user == null ? 'auth' : 'shell') : 'splash'), child: child));
  }
}

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});
  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> with WidgetsBindingObserver {
  int _tab = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(locationProvider.notifier).refresh();
    ref.read(connectionProvider.notifier).check();
    // Poll for alerts + location (no push service in local mode).
    _timer = Timer.periodic(const Duration(seconds: 8), (t) {
      ref.read(connectionProvider.notifier).check();
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
    const pages = [FeedScreen(), ActivityScreen(), NetaScreen(), ProfileScreen()];
    return Scaffold(
      extendBody: true,
      body: Stack(children: [
        const Positioned.fill(child: PageBackdrop(child: SizedBox.expand())),
        Positioned.fill(
          child: IndexedStack(index: _tab, children: pages),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: pad.bottom + 12,
          child: Center(
            child: FloatingNav(
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
              onAdd: () => Navigator.of(context).push(PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 420),
                reverseTransitionDuration: const Duration(milliseconds: 300),
                pageBuilder: (_, __, ___) => const ReportScreen(),
                transitionsBuilder: (_, a, __, child) => SlideTransition(
                  position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
                  child: child,
                ),
              )),
              dotOnProfile: unread > 0,
            ),
          ),
        ),
      ]),
    );
  }
}
