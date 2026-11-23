import 'package:flutter/material.dart';

import 'package:by_the_people/core/theme/tokens.dart';
import 'package:by_the_people/presentation/widgets/ui.dart' show TapScale;

/// A white hero card with 0-2 tinted layers peeking out behind it, so it reads as physically stacked.
///
/// [layers] is the total number of cards (1 to 3, the front one included). Each layer behind the
/// front one is inset by [inset] on each side per depth and drops [offset] lower than the one in front.
/// Use on hero surfaces only (stat strips, need cards, event cards, headline metrics).
class StackedCard extends StatelessWidget {
  const StackedCard({
    super.key,
    required this.child,
    this.layers = 2,
    this.offset = 7,
    this.inset = 10,
    this.tint = const Color(0xFFEDEDF0),
    this.onTap,
    this.padding = const EdgeInsets.all(R.cardInset),
    this.radius = R.card,
    this.color = C.surface,
  }) : assert(layers >= 1 && layers <= 3);

  final Widget child;

  /// Total cards including the front one (1-3).
  final int layers;

  /// Vertical distance between each layer, in logical pixels.
  final double offset;

  /// Horizontal inset per depth step, so back layers are narrower.
  final double inset;

  /// Colour of the back layers. The deepest layer is pulled toward the canvas colour.
  final Color tint;

  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final depth = layers - 1;
    final front = Padding(
      padding: EdgeInsets.only(bottom: offset * depth),
      child: Container(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius), boxShadow: C.shadowSoft),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return TapScale(
      onTap: onTap,
      scale: 0.98,
      child: Stack(clipBehavior: Clip.none, children: [
        // Deepest layer first so the nearer ones paint over it.
        for (var i = depth; i >= 1; i--)
          Positioned(
            left: inset * i,
            right: inset * i,
            top: offset * i,
            bottom: offset * (depth - i),
            child: Container(
              decoration: BoxDecoration(
                color: Color.lerp(tint, C.canvas, (i - 1) * 0.45),
                borderRadius: BorderRadius.circular(radius),
              ),
            ),
          ),
        front,
      ]),
    );
  }
}
