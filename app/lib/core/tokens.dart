import 'package:flutter/material.dart';

/// Design tokens (see docs/design.md).
class C {
  static const canvas = Color(0xFFF6F5F2);
  static const surface = Colors.white;
  static const muted = Color(0xFFEFEEEA);
  static const ink = Color(0xFF17181A);
  static const inkCard = Color(0xFF232426);
  static const inkSoft = Color(0xFF6B6E74);
  static const line = Color(0xFFE6E4DE);

  static const lime = Color(0xFFC8DB7A);
  static const lavender = Color(0xFFA99BD6);
  static const sky = Color(0xFF8CC8F0);
  static const blush = Color(0xFFF4B8C0);
  static const mint = Color(0xFFD9F0E3);
  static const mintDeep = Color(0xFFBFE3C8);
  static const amber = Color(0xFFFFC48A);
  static const ember = Color(0xFFFF5A36);
  static const emberLight = Color(0xFFFFB347);
  static const emberDark = Color(0xFF1A1013);
}

class R {
  static const card = 28.0;
  static const sheet = 32.0;
}

const _wght = 'wght';

TextStyle display(double size, {Color color = C.ink, double w = 560, double h = 1.05}) => TextStyle(
      fontFamily: 'Fraunces',
      fontSize: size,
      height: h,
      color: color,
      letterSpacing: -size * 0.015,
      fontVariations: [FontVariation(_wght, w), const FontVariation('SOFT', 60), FontVariation('opsz', size.clamp(9, 144))],
    );

TextStyle ui(double size, {Color color = C.ink, double w = 500, double h = 1.3, double ls = 0}) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: size,
      height: h,
      color: color,
      letterSpacing: ls,
      fontVariations: [FontVariation(_wght, w)],
    );

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
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink),
    sliderTheme: SliderThemeData(
      activeTrackColor: C.ink,
      inactiveTrackColor: C.line,
      thumbColor: C.ink,
      overlayColor: C.ink.withValues(alpha: 0.08),
      trackHeight: 6,
    ),
  );
}
