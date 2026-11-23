import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:by_the_people/core/network/api_client.dart';
import 'package:by_the_people/domain/entities/models.dart';
import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/widgets/shaders.dart';

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
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
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
  const CircleBtn({super.key, required this.icon, this.onTap, this.dark = false, this.dot = false, this.size = 40, this.bg});
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
            decoration: BoxDecoration(color: b, shape: BoxShape.circle, boxShadow: dark ? null : C.shadowSoft),
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

/// Two-layer card shadow (see [C.shadowSoft]). Kept as an alias for existing call sites.
const softShadow = C.shadowSoft;

/// Small rounded-square icon tile: 18dp glyph on a 32dp [C.muted] chip. One icon family across the app.
class IconChip extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;
  const IconChip(this.icon, {super.key, this.size = 32, this.color});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: C.muted, borderRadius: BorderRadius.circular(size * 0.32)),
        child: Icon(icon, size: 18, color: color ?? C.ink),
      );
}

/// Flat surface panel (name kept for compatibility; no blur any more).
class FrostedPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color tint;
  final bool border;
  const FrostedPanel({
    super.key, required this.child, this.radius = R.card, this.padding = const EdgeInsets.all(16),
    this.tint = C.surface, this.border = true,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: C.line) : null,
      ),
      child: child,
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
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(20)),
      // pill track
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
                borderRadius: BorderRadius.circular(16),
                boxShadow: dark ? null : C.shadowSoft,
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
                      style: ui_(13, i == index ? C.ink : (dark ? Colors.white70 : C.inkSoft), 600),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: selected || dark ? null : Border.all(color: C.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
          Text(label, style: ui(13, color: fg, w: 600)),
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
        color: hueColor(person.hue, s: 0.38, l: 0.42),
        border: ring == null && size > 30 ? null : Border.all(color: ring ?? Colors.white, width: 1.5),
      ),
      child: Text(person.initials, style: TextStyle(fontFamily: 'Jakarta', fontSize: size * 0.36, color: Colors.white, fontVariations: const [FontVariation('wght', 650)])),
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
                child: Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(left: 12), child: Text(label!, style: ui(12, color: labelColor, w: 600)))),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: crit ? C.ember : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: crit ? null : Border.all(color: (onDark ? Colors.white : C.ink).withValues(alpha: 0.35), width: 1.2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (crit) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.local_fire_department, size: 12, color: Colors.white)),
        Text('${_labels[severity]} priority', style: ui(12, color: crit || onDark ? Colors.white : C.ink, w: 600)),
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
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          constraints: expand ? const BoxConstraints(minWidth: double.infinity) : null,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(26),
            boxShadow: color == C.ink && onPressed != null ? C.shadowSoft : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (loading)
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
            else ...[
              if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
              Flexible(child: Text(label, style: ui(14.5, color: fg, w: 650), overflow: TextOverflow.ellipsis)),
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

/// One destination in the floating nav.
class NavItem {
  final IconData icon;
  final String label;
  const NavItem(this.icon, this.label);
}

class FloatingNav extends StatefulWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final VoidCallback? onAdd;
  final bool dotOnProfile;

  /// Destinations; defaults to the four citizen-era tabs.
  final List<NavItem>? items;

  /// When set, the round action button sits INSIDE the bar after this many tabs (e.g. 2 = in the middle).
  /// When null, the button (if any) sits to the right of the bar.
  final int? addSlot;

  /// Tab index that gets the unread dot (defaults to the last tab).
  final int? dotIndex;
  const FloatingNav({
    super.key, required this.index, required this.onChanged, this.onAdd, this.dotOnProfile = false,
    this.items, this.addSlot, this.dotIndex,
  });
  static const defaultItems = [
    NavItem(Icons.home_rounded, 'Feed'),
    NavItem(Icons.event_available_rounded, 'Activity'),
    NavItem(Icons.shield_moon_rounded, 'Neta'),
    NavItem(Icons.person_rounded, 'Profile'),
  ];
  @override
  State<FloatingNav> createState() => _FloatingNavState();
}

class _FloatingNavState extends State<FloatingNav> with SingleTickerProviderStateMixin {
  // The highlight blob is driven by a spring on a fractional tab position. A light
  // damping ratio gives a soft settle; the blob also stretches along its direction of travel.
  late final AnimationController _pos;
  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 240, ratio: 0.82);

  List<NavItem> get _items => widget.items ?? FloatingNav.defaultItems;

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
    final n = _items.length;
    final inline = widget.addSlot != null && widget.onAdd != null;
    final item = ((screenW - 32 - addSize - 12 - 14) / 4).clamp(44.0, 58.0);
    const pad = 4.0;
    final barH = item + pad * 2;
    final d = item - 4; // blob diameter: always a true circle with a margin inside the bar
    final slots = n + (inline ? 1 : 0);
    final addAt = widget.addSlot ?? n;
    // Fractional tab position -> fractional slot position (skips over the inline add button).
    double slotOf(double p) => inline ? p + (p - (addAt - 1)).clamp(0.0, 1.0) : p;
    int slotIdx(int tab) => inline && tab >= addAt ? tab + 1 : tab;
    final dotIdx = widget.dotIndex ?? n - 1;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        height: barH,
        padding: const EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(36),
          boxShadow: C.shadowLift,
        ),
        child: SizedBox(
          width: item * slots,
          height: item,
          child: Stack(clipBehavior: Clip.none, children: [
            AnimatedBuilder(
              animation: _pos,
              builder: (context, _) {
                final p = _pos.value.clamp(-0.15, n - 1 + 0.15);
                final v = _pos.velocity.abs();
                final stretch = (v * 0.045 * item / 4).clamp(0.0, item * 0.5);
                final w = d + stretch;
                final cx = item * (slotOf(p) + 0.5);
                // squash a little as it stretches so the blob keeps its volume
                final h = d - stretch * 0.28;
                return Positioned(
                  left: cx - w / 2,
                  top: (item - h) / 2,
                  width: w,
                  height: h,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: C.ink,
                      borderRadius: BorderRadius.circular(h),
                    ),
                  ),
                );
              },
            ),
            for (var i = 0; i < n; i++)
              Positioned(
                left: item * slotIdx(i),
                top: 0,
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
                      label: _items[i].label,
                      button: true,
                      child: Stack(clipBehavior: Clip.none, children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            _items[i].icon,
                            key: ValueKey(i == widget.index),
                            size: item * 0.45,
                            color: i == widget.index ? Colors.white : C.inkSoft,
                          ),
                        ),
                        if (widget.dotOnProfile && i == dotIdx)
                          Positioned(
                            right: -2, top: -2,
                            child: Container(width: 9, height: 9, decoration: BoxDecoration(color: C.ember, shape: BoxShape.circle, border: Border.all(color: C.surface, width: 1.5))),
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
            if (inline)
              Positioned(
                left: item * addAt,
                top: 0,
                width: item,
                height: item,
                child: Center(
                  child: TapScale(
                    onTap: widget.onAdd,
                    child: Container(
                      width: item - 2,
                      height: item - 2,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: C.ember, boxShadow: C.shadowSoft),
                      child: Icon(Icons.add_rounded, color: Colors.white, size: item * 0.55, semanticLabel: 'Create'),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
      if (!inline && widget.onAdd != null) ...[
        const SizedBox(width: 12),
        TapScale(
          onTap: widget.onAdd,
          child: Container(
            width: addSize,
            height: addSize,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: C.ember, boxShadow: C.shadowLift),
            child: Icon(Icons.add_rounded, color: Colors.white, size: addSize * 0.5, semanticLabel: 'Report an issue'),
          ),
        ),
      ],
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
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child)),
      child: Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(color: dark ? Colors.white12 : C.surface, borderRadius: BorderRadius.circular(R.card - 8), boxShadow: dark ? null : C.shadowSoft),
          child: Icon(Icons.inbox_outlined, size: 26, color: dark ? Colors.white70 : C.inkSoft),
        ),
        const SizedBox(height: R.cardInset),
        Text(title, textAlign: TextAlign.center, style: titleStyle(color: dark ? Colors.white : C.ink)),
        const SizedBox(height: R.unit),
        Text(body, textAlign: TextAlign.center, style: bodyStyle(color: dark ? Colors.white70 : C.inkSoft)),
      ]),
    ));
  }
}

/// Stat strip tile: big number over a small grey label.
class MetricTile extends StatelessWidget {
  final String value, label;
  final IconData? icon;
  final VoidCallback? onTap;
  const MetricTile({super.key, required this.value, required this.label, this.icon, this.onTap});
  @override
  Widget build(BuildContext context) => TapScale(
        onTap: onTap,
        scale: 0.98,
        child: Container(
          padding: const EdgeInsets.all(R.cardInset),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(R.card), boxShadow: C.shadowSoft),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: C.inkSoft), const SizedBox(height: 8)],
            Text(value, style: numStyle(26)),
            const SizedBox(height: 2),
            Text(label, style: metaStyle()),
          ]),
        ),
      );
}

/// Dashed outlined "Add" tile.
class DashedAddTile extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double height;
  const DashedAddTile({super.key, required this.label, this.onTap, this.height = 88});
  @override
  Widget build(BuildContext context) => TapScale(
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedRRect(),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.add_rounded, size: 20, color: C.inkSoft),
              const SizedBox(width: 6),
              Text(label, style: ui(14, color: C.inkSoft, w: 600)),
            ]),
          ),
        ),
      );
}

class _DashedRRect extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(R.card)));
    final paint = Paint()
      ..color = const Color(0xFFCFCFD4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 12) {
        canvas.drawPath(m.extractPath(d, (d + 6).clamp(0, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
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
        Text(friendlyError(error), textAlign: TextAlign.center, style: ui(14, color: dark ? Colors.white : C.ink)),
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: widget.error ? C.ink : C.inkCard,
                borderRadius: BorderRadius.circular(14),
                boxShadow: C.shadowLift,
              ),
              child: Row(children: [
                Icon(widget.icon ?? (widget.error ? Icons.error_outline_rounded : Icons.check_circle_rounded),
                    color: widget.error ? C.ember : C.lime, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(widget.msg, style: ui(13.5, color: Colors.white, w: 550, h: 1.35))),
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
      padding: const EdgeInsets.fromLTRB(4, R.unit, 4, R.unit + 4),
      child: Row(children: [
        Expanded(child: Text(title, style: titleStyle(color: dark ? Colors.white : C.ink))),
        if (action != null)
          TapScale(
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              decoration: BoxDecoration(color: dark ? Colors.white12 : C.surface, borderRadius: BorderRadius.circular(16), boxShadow: dark ? null : C.shadowSoft),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(action!, style: metaStyle(color: dark ? Colors.white : C.ink).copyWith(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(width: 2),
                Icon(Icons.arrow_outward_rounded, size: 14, color: dark ? Colors.white : C.ink),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Flat page backdrop used by most screens.
class PageBackdrop extends StatelessWidget {
  final Widget child;
  final int mode;
  const PageBackdrop({super.key, required this.child, this.mode = 0});
  @override
  Widget build(BuildContext context) => ColoredBox(color: C.canvas, child: child);
}


/// Turns any error into short, friendly copy. Never shows raw exception text.
String friendlyError(Object? e, {String fallback = 'Something went wrong. Please try again.'}) {
  if (e is ApiException) {
    if (e.isNetwork) return 'No connection. Check your internet and try again.';
    if (e.status == 401) return 'Please sign in again.';
    if (e.status == 403) return 'You do not have permission to do that.';
    if (e.status == 404) return 'That is no longer available.';
    if (e.status >= 500 || e.status == 400 && e.code == 'ERROR') return fallback;
    final m = e.message.trim();
    return m.isEmpty || m == 'Request failed' ? fallback : m;
  }
  return fallback;
}

/// Shows a friendly error toast for [e] (optionally prefixed by what failed).
void toastError(BuildContext context, Object? e, {String? fallback}) {
  if (!context.mounted) return;
  showToast(context, friendlyError(e, fallback: fallback ?? 'Something went wrong. Please try again.'), error: true);
}

/// Slim top bar: optional leading widget (avatar), title + optional subtitle, trailing actions.
/// Use inside a SliverAppBar or as a plain widget. Height ~52.
class AppTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;
  const AppTopBar({super.key, required this.title, this.subtitle, this.leading, this.actions = const [], this.padding = const EdgeInsets.fromLTRB(16, 6, 8, 6)});
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: SizedBox(
          height: 44,
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(20, w: 650, h: 1.15)),
                if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(12, color: C.inkSoft, h: 1.2)),
              ]),
            ),
            ...actions,
          ]),
        ),
      );
}

/// Small icon action for [AppTopBar] (40x40 hit area, 22dp glyph, optional unread dot).
class TopBarAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool dot;
  final String? tooltip;
  const TopBarAction({super.key, required this.icon, this.onTap, this.dot = false, this.tooltip});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(alignment: Alignment.center, children: [
              Icon(icon, size: 22, color: C.ink),
              if (dot) Positioned(right: 9, top: 9, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: C.ember, shape: BoxShape.circle, border: Border.all(color: C.canvas, width: 1.5)))),
            ]),
          ),
        ),
      );
}

/// Small underlined tab bar (one row, ~40dp). Great for Issues / In action / Resolved.
class CompactTabs extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry padding;
  const CompactTabs({super.key, required this.labels, required this.index, required this.onChanged, this.padding = const EdgeInsets.symmetric(horizontal: 16)});
  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: padding,
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.line))),
        child: Row(children: [
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
                child: Stack(alignment: Alignment.bottomCenter, children: [
                  Center(child: Text(labels[i], style: ui(13.5, w: i == index ? 650 : 500, color: i == index ? C.ink : C.inkSoft))),
                  AnimatedContainer(duration: const Duration(milliseconds: 180), height: 2.5, margin: const EdgeInsets.symmetric(horizontal: 14), decoration: BoxDecoration(color: i == index ? C.ember : Colors.transparent, borderRadius: BorderRadius.circular(2))),
                ]),
              ),
            ),
        ]),
      );
}

/// One compact horizontal row of chips/filters (36dp high, scrolls). Pass [AppChip]s or [FilterButton].
class FilterChipRow extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  const FilterChipRow({super.key, required this.children, this.padding = const EdgeInsets.symmetric(horizontal: 16)});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: padding,
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) => Center(child: children[i]),
        ),
      );
}

/// Chip-styled button that opens a menu/sheet: "[icon] Label  v". Set [active] to highlight a non-default choice.
class FilterButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const FilterButton({super.key, required this.label, required this.onTap, this.icon = Icons.tune_rounded, this.active = false});
  @override
  Widget build(BuildContext context) => TapScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? C.ink.withValues(alpha: 0.06) : C.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: active ? C.ink : C.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: C.ink),
            const SizedBox(width: 5),
            Text(label, style: ui(13, w: 600)),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded, size: 16, color: C.inkSoft),
          ]),
        ),
      );
}

/// Bottom sheet with a title and a list of single-choice options. Returns the chosen key.
Future<T?> showChoiceSheet<T>(BuildContext context, {required String title, required List<(T, String, IconData?)> options, T? selected}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      decoration: const BoxDecoration(color: C.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet))),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: C.line, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 12),
          Text(title, style: ui(16, w: 650)),
          const SizedBox(height: 6),
          for (final o in options)
            InkWell(
              onTap: () => Navigator.pop(ctx, o.$1),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                child: Row(children: [
                  if (o.$3 != null) ...[Icon(o.$3, size: 18, color: C.inkSoft), const SizedBox(width: 12)],
                  Expanded(child: Text(o.$2, style: ui(14.5, w: o.$1 == selected ? 650 : 500))),
                  if (o.$1 == selected) const Icon(Icons.check_rounded, size: 18, color: C.ember),
                ]),
              ),
            ),
        ]),
      ),
    ),
  );
}

/// White card with the two-layer soft shadow and a 24dp radius. Use for feed cards, list rows and panels.
class FlatCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;
  const FlatCard({super.key, required this.child, this.padding = EdgeInsets.zero, this.margin = EdgeInsets.zero, this.radius = R.card, this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? C.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: C.shadowSoft,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: Padding(padding: padding, child: child)),
    );
    return onTap == null ? card : TapScale(onTap: onTap, scale: 0.99, child: card);
  }
}

/// Neutral meta chip: [icon] label. Hairline border, 11.5dp text.
class TagChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  final Color? bg;
  const TagChip(this.label, {super.key, this.icon, this.color, this.bg});
  @override
  Widget build(BuildContext context) {
    final fg = color ?? C.inkSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg ?? C.muted, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ui(11.5, color: fg, w: 600))),
      ]),
    );
  }
}


/// Translucent frosted layer for sliver/app bars so the page gradient shows through consistently.
Widget frostedBarBackground() => ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: const ColoredBox(color: Color(0x40FFFFFF), child: SizedBox.expand()),
      ),
    );
