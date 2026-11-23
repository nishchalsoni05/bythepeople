import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design tokens (see docs/design.md).
class C {
  // Minimal monochrome system: white surfaces on a soft grey canvas, near-black ink.
  static const canvas = Color(0xFFF4F4F5);
  static const surface = Colors.white;
  static const muted = Color(0xFFF0F0F2);
  static const ink = Color(0xFF111111);
  static const inkCard = Color(0xFF111111);
  static const inkSoft = Color(0xFF8A8A90);
  static const line = Color(0xFFEBEBED);

  // Accent family collapsed to neutrals; `ember` is the single brand accent (ink) and `danger` is reserved for alerts.
  static const lime = Color(0xFFEDEDEF);
  static const lavender = Color(0xFFEDEDEF);
  static const sky = Color(0xFFEDEDEF);
  static const blush = Color(0xFFF3F3F4);
  static const mint = Color(0xFFF0F0F2);
  static const mintDeep = Color(0xFFE6E6E9);
  static const amber = Color(0xFFEFEFF1);
  static const ember = Color(0xFF111111);
  static const emberLight = Color(0xFF3A3A3D);
  static const emberDark = Color(0xFF000000);
  static const danger = Color(0xFFD64545);

  /// Two-layer elevation: a tight contact shadow plus a wide, faint ambient one.
  static const shadowSoft = [
    BoxShadow(color: Color(0x0A111111), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0F111111), blurRadius: 20, offset: Offset(0, 6)),
  ];

  /// Stronger lift for floating elements (nav pill, sheets, toasts).
  static const shadowLift = [
    BoxShadow(color: Color(0x0F111111), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x1A111111), blurRadius: 28, offset: Offset(0, 10)),
  ];
}

class R {
  /// Card corner radius (24) and card inner inset (16) on an 8pt grid.
  static const card = 24.0;
  static const cardInset = 16.0;
  static const sheet = 28.0;
  static const unit = 8.0;
}

/// Hierarchy for list/card text: title 17 w650, body 14 w500, meta 12 w500 in [C.inkSoft].
TextStyle titleStyle({Color color = C.ink}) => ui(17, w: 650, color: color, h: 1.25);
TextStyle bodyStyle({Color color = C.ink}) => ui(14, w: 500, color: color, h: 1.4);
TextStyle metaStyle({Color color = C.inkSoft}) => ui(12, w: 500, color: color, h: 1.3);

/// Numbers that line up in columns and counters.
TextStyle numStyle(double size, {Color color = C.ink, double w = 700}) =>
    ui(size, w: w, color: color, ls: -0.3).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

const _wght = 'wght';

/// Global type scale: every call site passes a design size; these helpers pull it down to
/// professional levels (body ~13-14, titles 16-17, screen titles ~20) and cap heavy weights.
double _scaled(double size) => size >= 22 ? size * 0.82 : (size >= 16 ? size * 0.94 : size * 0.96);

TextStyle display(double size, {Color color = C.ink, double w = 560, double h = 1.15}) {
  final sz = _scaled(size);
  return TextStyle(
    fontFamily: 'Fraunces',
    fontSize: sz,
    height: h,
    color: color,
    letterSpacing: -sz * 0.01,
    fontVariations: [FontVariation(_wght, w.clamp(400, 600)), const FontVariation('SOFT', 30), FontVariation('opsz', sz.clamp(9, 144))],
  );
}

TextStyle ui(double size, {Color color = C.ink, double w = 500, double h = 1.3, double ls = 0}) {
  final sz = _scaled(size);
  return TextStyle(
    fontFamily: 'Jakarta',
    fontSize: sz,
    height: h,
    color: color,
    letterSpacing: ls != 0 ? ls : (sz >= 16 ? -0.2 : 0),
    fontVariations: [FontVariation(_wght, w.clamp(400, 680))],
  );
}

Color hueColor(int hue, {double s = 0.55, double l = 0.8}) => HSLColor.fromAHSL(1, hue % 360.0, s, l).toColor();

/// Need categories shown to users (keys match the API; old civic keys are kept so legacy rows still get an icon).
const categoryLabels = <String, String>{
  'food': 'Food',
  'clothes': 'Clothes',
  'money': 'Money',
  'medicine': 'Medicine',
  'stationery': 'Stationery',
  'volunteers': 'Volunteers',
  'other': 'Other',
};

const categoryIcons = <String, IconData>{
  'food': Icons.restaurant_outlined,
  'clothes': Icons.checkroom_outlined,
  'money': Icons.payments_outlined,
  'medicine': Icons.medication_outlined,
  'stationery': Icons.edit_note_outlined,
  'volunteers': Icons.groups_outlined,
  'road': Icons.add_road,
  'garbage': Icons.delete_outline,
  'water': Icons.water_drop_outlined,
  'drainage': Icons.waves,
  'electricity': Icons.bolt,
  'streetlight': Icons.lightbulb_outline,
  'safety': Icons.shield_outlined,
  'park': Icons.park_outlined,
  'other': Icons.more_horiz,
};

const badgeIcons = <String, IconData>{
  'flag': Icons.flag_rounded,
  'handshake': Icons.handshake_outlined,
  'watchdog': Icons.visibility_outlined,
  'megaphone': Icons.campaign_outlined,
  'spark': Icons.bolt_rounded,
  'responder': Icons.volunteer_activism_outlined,
  'verify': Icons.fact_check_outlined,
  'hero': Icons.military_tech_outlined,
  'crown': Icons.workspace_premium_outlined,
};

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: C.canvas,
    colorScheme: ColorScheme.fromSeed(seedColor: C.ember, brightness: Brightness.light, surface: C.surface),
    splashFactory: NoSplash.splashFactory,
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    }),
    highlightColor: Colors.transparent,
    fontFamily: 'Jakarta',
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark, statusBarBrightness: Brightness.light),
    ),
    textTheme: _textTheme(base.textTheme),
    sliderTheme: SliderThemeData(
      activeTrackColor: C.ink,
      inactiveTrackColor: C.line,
      thumbColor: C.ink,
      overlayColor: C.ink.withValues(alpha: 0.08),
      trackHeight: 6,
    ),
  );
}

TextTheme _textTheme(TextTheme t) {
  TextStyle s(double size, double w) => ui(size / 0.96, w: w).copyWith(fontSize: size);
  return t
      .copyWith(
        displayLarge: s(26, 600), displayMedium: s(24, 600), displaySmall: s(22, 600),
        headlineLarge: s(22, 600), headlineMedium: s(20, 600), headlineSmall: s(18, 600),
        titleLarge: s(20, 600), titleMedium: s(16, 600), titleSmall: s(14, 600),
        bodyLarge: s(15, 500), bodyMedium: s(14, 500), bodySmall: s(12, 500),
        labelLarge: s(14, 600), labelMedium: s(12, 600), labelSmall: s(11, 600),
      )
      .apply(bodyColor: C.ink, displayColor: C.ink);
}

/// Soft pastel surface for a card, chosen deterministically from a key (type/kind/category).
Color pastelOf(String key) {
  const list = [Color(0xFFF2F2F4), Color(0xFFEDEDF0), Color(0xFFF5F5F6)];
  var h = 0;
  for (final u in key.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return list[h % list.length];
}
