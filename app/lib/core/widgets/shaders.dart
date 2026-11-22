import 'dart:ui' as dui;
import 'package:flutter/material.dart';
import '../tokens.dart';

class ShaderLib {
  static dui.FragmentProgram? holo, iridescent, orb;
  static Future<void> load() async {
    // Loaded (and thereby compiled) on splash so the first frame never janks.
    try {
      holo = await dui.FragmentProgram.fromAsset('shaders/holo.frag');
      iridescent = await dui.FragmentProgram.fromAsset('shaders/iridescent.frag');
      orb = await dui.FragmentProgram.fromAsset('shaders/orb.frag');
    } catch (e) {
      debugPrint('Shader load failed, using fallbacks: $e');
    }
  }
}

/// Slow-moving pastel blobs (mode 0) or the ember hero gradient (mode 1).
class IridescentBackground extends StatefulWidget {
  final int mode;
  final Widget? child;
  const IridescentBackground({super.key, this.mode = 0, this.child});
  @override
  State<IridescentBackground> createState() => _IridescentBackgroundState();
}

class _IridescentBackgroundState extends State<IridescentBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 120))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = ShaderLib.iridescent;
    final fallback = widget.mode == 0 ? C.canvas : C.emberDark;
    return Stack(fit: StackFit.expand, children: [
      if (p == null)
        ColoredBox(color: fallback)
      else
        RepaintBoundary(child: CustomPaint(painter: _IridPainter(p, _c, widget.mode))),
      if (widget.child != null) widget.child!,
    ]);
  }
}

class _IridPainter extends CustomPainter {
  final dui.FragmentProgram program;
  final Animation<double> anim;
  final int mode;
  _IridPainter(this.program, this.anim, this.mode) : super(repaint: anim);
  @override
  void paint(Canvas canvas, Size size) {
    final s = program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, anim.value * 120)
      ..setFloat(3, mode.toDouble());
    canvas.drawRect(Offset.zero & size, Paint()..shader = s);
  }

  @override
  bool shouldRepaint(_IridPainter old) => old.mode != mode;
}

/// Iridescent glass orb.
class Orb extends StatefulWidget {
  final double size;
  const Orb({super.key, this.size = 120});
  @override
  State<Orb> createState() => _OrbState();
}

class _OrbState extends State<Orb> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = ShaderLib.orb;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: p == null
          ? DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(center: Alignment(-0.4, -0.5), colors: [Colors.white, C.lavender, C.blush]),
              ),
            )
          : CustomPaint(painter: _OrbPainter(p, _c)),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final dui.FragmentProgram program;
  final Animation<double> anim;
  _OrbPainter(this.program, this.anim) : super(repaint: anim);
  @override
  void paint(Canvas canvas, Size size) {
    final s = program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, anim.value * 60);
    canvas.drawRect(Offset.zero & size, Paint()..shader = s);
  }

  @override
  bool shouldRepaint(_OrbPainter old) => false;
}
