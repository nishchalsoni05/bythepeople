import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design tokens (see docs/design.md).
class C {
  static const canvas = Color(0xFFF5F5F3);
  static const surface = Colors.white;
  static const muted = Color(0xFFEFEEEA);
  static const ink = Color(0xFF17181A);
  static const inkCard = Color(0xFF232426);
  static const inkSoft = Color(0xFF666A70);
  static const line = Color(0xFFE4E4E0);

  static const lime = Color(0xFFC8DB7A);
  static const lavender = Color(0xFFA99BD6);
  static const sky = Color(0xFF8CC8F0);
  static const blush = Color(0xFFF4B8C0);
  static const mint = Color(0xFFD9F0E3);
  static const mintDeep = Color(0xFFBFE3C8);
  static const amber = Color(0xFFFFC48A);
  static const ember = Color(0xFFE0501F);
  static const emberLight = Color(0xFFFFB347);
  static const emberDark = Color(0xFF1A1013);
}

class R {
  static const card = 22.0;
  static const sheet = 28.0;
}

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

const categoryIcons = <String, IconData>{
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
  const list = [C.amber, C.mintDeep, C.lavender, C.sky, C.blush, C.lime];
  var h = 0;
  for (final u in key.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return Color.lerp(list[h % list.length], Colors.white, 0.4)!;
}
