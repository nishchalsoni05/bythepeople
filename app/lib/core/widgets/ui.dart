import 'dart:ui' as dui;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../tokens.dart';
import 'shaders.dart';

class TapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const TapScale({super.key, required this.child, this.onTap, this.scale = 0.97});
  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool dark, dot;
  final double size;
  final Color? bg;
  const CircleBtn({super.key, required this.icon, this.onTap, this.dark = false, this.dot = false, this.size = 46, this.bg});
  @override
  Widget build(BuildContext context) {
    final b = bg ?? (dark ? C.inkCard : C.surface);
    final fg = dark ? Colors.white : C.ink;
    return TapScale(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: b, shape: BoxShape.circle, boxShadow: dark ? null : softShadow),
            child: Icon(icon, size: size * 0.45, color: fg),
          ),
          if (dot)
            Positioned(
              right: 1,
              top: 1,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(color: C.ember, shape: BoxShape.circle, border: Border.all(color: C.canvas, width: 2)),
              ),
            ),
        ]),
      ),
    );
  }
}

const softShadow = [
  BoxShadow(color: Color(0x0F17181A), blurRadius: 24, offset: Offset(0, 8)),
  BoxShadow(color: Color(0x0A17181A), blurRadius: 6, offset: Offset(0, 2)),
];

class FrostedPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color tint;
  final bool border;
  const FrostedPanel({
    super.key, required this.child, this.radius = R.card, this.padding = const EdgeInsets.all(16),
    this.tint = const Color(0xB3FFFFFF), this.border = true,
  });
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: dui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(radius),
            border: border ? Border.all(color: Colors.white.withValues(alpha: 0.6)) : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

class SegmentedToggle extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final bool dark;
  const SegmentedToggle({super.key, required this.labels, required this.index, required this.onChanged, this.dark = false});
  @override
  Widget build(BuildContext context) {
    final track = dark ? Colors.white.withValues(alpha: 0.14) : C.muted;
    final thumb = dark ? Colors.white : C.surface;
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(30)),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / labels.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutBack,
            left: w * index,
            width: w,
            top: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: thumb,
                borderRadius: BorderRadius.circular(26),
                boxShadow: dark ? null : const [BoxShadow(color: Color(0x1417181A), blurRadius: 8, offset: Offset(0, 2))],
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (i != index) {
                      HapticFeedback.selectionClick();
                      onChanged(i);
                    }
                  },
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: ui_(13.5, i == index ? C.ink : (dark ? Colors.white70 : C.inkSoft), 650),
                      child: Text(labels[i]),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

TextStyle ui_(double s, Color c, double w) => ui(s, color: c, w: w);

class AppChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool dark;
  const AppChip({super.key, required this.label, this.count, this.selected = false, this.icon, this.onTap, this.dark = false});
  @override
  Widget build(BuildContext context) {
    final bg = selected ? (dark ? Colors.white : C.ink) : (dark ? Colors.white.withValues(alpha: 0.14) : C.surface);
    final fg = selected ? (dark ? C.ink : Colors.white) : (dark ? Colors.white : C.ink);
    return TapScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(30),
          border: selected || dark ? null : Border.all(color: C.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
          Text(label, style: ui(13, color: fg, w: 650)),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: selected ? C.lime : (dark ? Colors.white24 : C.muted), borderRadius: BorderRadius.circular(20)),
              child: Text('$count', style: ui(11.5, color: selected ? C.ink : (dark ? Colors.white : C.inkSoft), w: 700)),
            ),
          ],
        ]),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  final Person person;
  final double size;
  final Color? ring;
  const Avatar(this.person, {super.key, this.size = 30, this.ring});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [hueColor(person.hue, l: 0.78), hueColor(person.hue + 40, l: 0.66)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: ring ?? Colors.white, width: size > 34 ? 3 : 2),
      ),
      child: Text(person.initials, style: ui(size * 0.36, color: Colors.white, w: 750)),
    );
  }
}

class AvatarStack extends StatelessWidget {
  final List<Person> people;
  final int total;
  final double size;
  final Color? ring;
  final int max;
  const AvatarStack({super.key, required this.people, int? total, this.size = 28, this.ring, this.max = 4}) : total = total ?? people.length;
  @override
  Widget build(BuildContext context) {
    final shown = people.take(max).toList();
    final extra = total - shown.length;
    final step = size * 0.68;
    final n = shown.length + (extra > 0 ? 1 : 0);
    if (n == 0) return SizedBox(height: size);
    return SizedBox(
      height: size,
      width: step * (n - 1) + size,
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++) Positioned(left: i * step, child: Avatar(shown[i], size: size, ring: ring)),
        if (extra > 0)
          Positioned(
            left: shown.length * step,
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: C.ink, shape: BoxShape.circle, border: Border.all(color: ring ?? Colors.white, width: 2)),
              child: Text('+$extra', style: ui(size * 0.34, color: Colors.white, w: 700)),
            ),
          ),
      ]),
    );
  }
}

/// Pill progress bar with a diagonal hatch texture (ref-2).
class HatchedProgress extends StatelessWidget {
  final double value;
  final Color fill, track, hatch;
  final double height;
  final String? label;
  final Color labelColor;
  const HatchedProgress({
    super.key, required this.value, this.fill = C.lime, this.track = const Color(0x22000000),
    this.hatch = const Color(0x33FFFFFF), this.height = 34, this.label, this.labelColor = C.ink,
  });
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0, 1)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(children: [
            Positioned.fill(child: ColoredBox(color: track)),
            FractionallySizedBox(
              widthFactor: v == 0 ? 0.0001 : v,
              child: CustomPaint(painter: _HatchPainter(fill, hatch), child: const SizedBox.expand()),
            ),
            if (label != null)
              Positioned.fill(
                child: Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(left: 14), child: Text(label!, style: ui(12.5, color: labelColor, w: 650)))),
              ),
          ]),
        ),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  final Color fill, hatch;
  _HatchPainter(this.fill, this.hatch);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = fill);
    final p = Paint()
      ..color = hatch
      ..strokeWidth = 1.4;
    for (double x = -size.height; x < size.width + size.height; x += 7) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(_HatchPainter o) => o.fill != fill;
}

class SeverityChip extends StatelessWidget {
  final String severity;
  final bool onDark;
  const SeverityChip(this.severity, {super.key, this.onDark = false});
  static const _labels = {'low': 'Low', 'medium': 'Medium', 'high': 'High', 'critical': 'Critical'};
  @override
  Widget build(BuildContext context) {
    final crit = severity == 'critical';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: crit ? C.ember : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: crit ? null : Border.all(color: (onDark ? Colors.white : C.ink).withValues(alpha: 0.35), width: 1.2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (crit) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.local_fire_department, size: 14, color: Colors.white)),
        Text('${_labels[severity]} priority', style: ui(12, color: crit || onDark ? Colors.white : C.ink, w: 650)),
      ]),
    );
  }
}

class PillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color color, fg;
  final bool loading, expand;
  const PillButton({
    super.key, required this.label, this.icon, this.onPressed, this.color = C.ink, this.fg = Colors.white,
    this.loading = false, this.expand = true,
  });
  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return TapScale(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        opacity: onPressed == null ? 0.45 : 1,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          constraints: expand ? const BoxConstraints(minWidth: double.infinity) : null,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(30)),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (loading)
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
            else ...[
              if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 8)],
              Flexible(child: Text(label, style: ui(15.5, color: fg, w: 700), overflow: TextOverflow.ellipsis)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Height the floating nav occupies above the bottom safe area (bar + its margin).
double navClearance(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  final add = w < 360 ? 56.0 : 68.0;
  final item = ((w - 32 - add - 12 - 14) / 4).clamp(44.0, 58.0);
  return item + 14 + 12;
}

class FloatingNav extends StatefulWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final VoidCallback onAdd;
  final bool dotOnProfile;
  const FloatingNav({super.key, required this.index, required this.onChanged, required this.onAdd, this.dotOnProfile = false});
  static const icons = [Icons.home_rounded, Icons.event_available_rounded, Icons.shield_moon_rounded, Icons.person_rounded];
  static const labels = ['Feed', 'Activity', 'Neta', 'Profile'];
  @override
  State<FloatingNav> createState() => _FloatingNavState();
}

class _FloatingNavState extends State<FloatingNav> with SingleTickerProviderStateMixin {
  // The highlight blob is driven by a spring on a fractional tab position (0..3). A light
  // damping ratio gives a soft settle; the blob also stretches along its direction of travel.
  late final AnimationController _pos;
  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 240, ratio: 0.82);

  @override
  void initState() {
    super.initState();
    _pos = AnimationController.unbounded(vsync: this, value: widget.index.toDouble());
  }

  @override
  void didUpdateWidget(FloatingNav old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _pos.animateWith(SpringSimulation(_spring, _pos.value, widget.index.toDouble(), _pos.velocity));
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Scales with the screen so it fits from 320 pt wide phones up to large ones.
    final screenW = MediaQuery.sizeOf(context).width;
    final addSize = screenW < 360 ? 56.0 : 68.0;
    final item = ((screenW - 32 - addSize - 12 - 14) / 4).clamp(44.0, 58.0);
    const pad = 7.0;
    final barH = item + pad * 2;
    final d = item - 4; // blob diameter: always a true circle with a margin inside the bar
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        height: barH,
        padding: const EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: C.inkCard,
          borderRadius: BorderRadius.circular(40),
          boxShadow: const [BoxShadow(color: Color(0x3317181A), blurRadius: 30, offset: Offset(0, 12))],
        ),
        child: SizedBox(
          width: item * 4,
          height: item,
          child: Stack(clipBehavior: Clip.none, children: [
            AnimatedBuilder(
              animation: _pos,
              builder: (context, _) {
                final p = _pos.value.clamp(-0.15, 3.15);
                final v = _pos.velocity.abs();
                final stretch = (v * 0.045 * item / 4).clamp(0.0, item * 0.5);
                final w = d + stretch;
                final cx = item * (p + 0.5);
                // squash a little as it stretches so the blob keeps its volume
                final h = d - stretch * 0.28;
                return Positioned(
                  left: cx - w / 2,
                  top: (item - h) / 2,
                  width: w,
                  height: h,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(h),
                      boxShadow: const [BoxShadow(color: Color(0x33FFFFFF), blurRadius: 14)],
                    ),
                  ),
                );
              },
            ),
            Row(children: [
              for (var i = 0; i < 4; i++)
                SizedBox(
                  width: item,
                  height: item,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onChanged(i);
                    },
                    child: Center(
                      child: Semantics(
                        label: FloatingNav.labels[i],
                        button: true,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            FloatingNav.icons[i],
                            key: ValueKey(i == widget.index),
                            size: item * 0.45,
                            color: i == widget.index ? C.ink : Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
      ),
      const SizedBox(width: 12),
      TapScale(
        onTap: widget.onAdd,
        child: Container(
          width: addSize,
          height: addSize,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [C.emberLight, C.ember], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: Color(0x66FF5A36), blurRadius: 24, offset: Offset(0, 10))],
          ),
          child: Icon(Icons.add_rounded, color: Colors.white, size: addSize * 0.5, semanticLabel: 'Report an issue'),
        ),
      ),
    ]);
  }
}

class RollingNumber extends StatelessWidget {
  final int value;
  final TextStyle style;
  const RollingNumber(this.value, {super.key, required this.style});
  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      transitionBuilder: (child, anim) => ClipRect(
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.9), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
          child: FadeTransition(opacity: anim, child: child),
        ),
      ),
      child: Text('$value', key: ValueKey(value), style: style),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String title, body;
  final bool dark;
  const EmptyState({super.key, required this.title, required this.body, this.dark = false});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Orb(size: 96),
        const SizedBox(height: 18),
        Text(title, textAlign: TextAlign.center, style: display(24, color: dark ? Colors.white : C.ink)),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center, style: ui(14, color: dark ? Colors.white70 : C.inkSoft, h: 1.45)),
      ]),
    );
  }
}

class LoadingOrb extends StatelessWidget {
  const LoadingOrb({super.key});
  @override
  Widget build(BuildContext context) => const Padding(padding: EdgeInsets.all(48), child: Center(child: Orb(size: 56)));
}

class ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  final bool dark;
  const ErrorState({super.key, required this.error, required this.onRetry, this.dark = false});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.cloud_off_rounded, size: 40, color: dark ? Colors.white70 : C.inkSoft),
        const SizedBox(height: 12),
        Text('$error', textAlign: TextAlign.center, style: ui(14, color: dark ? Colors.white : C.ink)),
        const SizedBox(height: 16),
        PillButton(label: 'Try again', onPressed: onRetry, expand: false, color: dark ? Colors.white : C.ink, fg: dark ? C.ink : Colors.white),
      ]),
    );
  }
}

void showToast(BuildContext context, String msg, {bool error = false, IconData? icon}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _Toast(msg: msg, error: error, icon: icon, onDone: () => entry.remove()));
  overlay.insert(entry);
}

class _Toast extends StatefulWidget {
  final String msg;
  final bool error;
  final IconData? icon;
  final VoidCallback onDone;
  const _Toast({required this.msg, required this.error, this.icon, required this.onDone});
  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  @override
  void initState() {
    super.initState();
    _c.forward();
    if (widget.error) HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 3200), () async {
      if (!mounted) return;
      await _c.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) => Opacity(
            opacity: _c.value,
            child: Transform.translate(offset: Offset(0, (1 - Curves.easeOutBack.transform(_c.value)) * -40), child: child),
          ),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: widget.error ? C.ink : C.inkCard,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [BoxShadow(color: Color(0x4017181A), blurRadius: 24, offset: Offset(0, 10))],
              ),
              child: Row(children: [
                Icon(widget.icon ?? (widget.error ? Icons.error_outline_rounded : Icons.check_circle_rounded),
                    color: widget.error ? C.ember : C.lime, size: 22),
                const SizedBox(width: 12),
                Expanded(child: Text(widget.msg, style: ui(13.5, color: Colors.white, w: 600, h: 1.35))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  final bool dark;
  const SectionTitle(this.title, {super.key, this.action, this.onAction, this.dark = false});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      child: Row(children: [
        Expanded(child: Text(title, style: ui(17, color: dark ? Colors.white : C.ink, w: 700))),
        if (action != null)
          GestureDetector(onTap: onAction, child: Text(action!, style: ui(13.5, color: dark ? Colors.white70 : C.inkSoft, w: 600))),
      ]),
    );
  }
}

/// Gradient page backdrop used by most screens.
class PageBackdrop extends StatelessWidget {
  final Widget child;
  final int mode;
  const PageBackdrop({super.key, required this.child, this.mode = 0});
  @override
  Widget build(BuildContext context) => IridescentBackground(mode: mode, child: child);
}
