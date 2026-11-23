import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/tokens.dart';

/// Loading placeholders. Each one mirrors the shape of the content it stands in for,
/// so the layout does not jump when data arrives.

/// Shimmer sweep across everything inside it. Wrap a whole list in one so it animates as a unit.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
        baseColor: C.muted,
        highlightColor: Colors.white,
        period: const Duration(milliseconds: 1400),
        child: child,
      );
}

/// A solid placeholder block. Must sit inside a [Skeleton].
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8, this.circle = false});

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: C.line,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(radius),
        ),
      );
}

/// Placeholder for [IssueCard], stacked [count] times.
class IssueListSkeleton extends StatelessWidget {
  const IssueListSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Column(children: [for (var i = 0; i < count; i++) const _IssueCardSkeleton()]),
      );
}

class _IssueCardSkeleton extends StatelessWidget {
  const _IssueCardSkeleton();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(R.card), border: Border.all(color: C.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(children: [
              SkeletonBox(width: 32, height: 32, circle: true),
              SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SkeletonBox(width: 120, height: 12), SizedBox(height: 6), SkeletonBox(width: 80, height: 10)])),
            ]),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(14, 12, 14, 0), child: SkeletonBox(height: 16)),
          const Padding(padding: EdgeInsets.fromLTRB(14, 6, 70, 0), child: SkeletonBox(height: 16)),
          const SizedBox(height: 12),
          const AspectRatio(aspectRatio: 16 / 9, child: SkeletonBox(width: double.infinity, height: double.infinity, radius: 0)),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Row(children: [SkeletonBox(width: 64, height: 32, radius: 16), SizedBox(width: 10), SkeletonBox(width: 44, height: 20), Spacer(), SkeletonBox(width: 80, height: 32, radius: 16)]),
          ),
        ]),
      );
}

/// Placeholder for the Neta deck: one tall card, sized like the real deck card.
class NetaDeckSkeleton extends StatelessWidget {
  const NetaDeckSkeleton({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final width = (c.maxWidth * 0.78).clamp(220.0, 320.0);
        return Align(
          alignment: Alignment.topCenter,
          child: Skeleton(child: SkeletonBox(width: width, height: width * 1.45, radius: R.card)),
        );
      });
}

/// Placeholder for a plain list of rows: a leading avatar and two text lines.
class RowListSkeleton extends StatelessWidget {
  const RowListSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Column(children: [
          for (var i = 0; i < count; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(R.card), border: Border.all(color: C.line)),
              child: Row(children: [
                const SkeletonBox(width: 42, height: 42, circle: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                    SkeletonBox(width: 150, height: 14),
                    SizedBox(height: 8),
                    SkeletonBox(height: 12),
                  ]),
                ),
              ]),
            ),
        ]),
      );
}

/// Placeholder for a horizontal row of filter chips.
class ChipRowSkeleton extends StatelessWidget {
  const ChipRowSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < count; i++) SkeletonBox(width: 64 + (i % 3) * 16.0, height: 30, radius: 15),
        ]),
      );
}

/// Placeholder for a detail screen: header, hero card, stat tiles and a couple of cards.
class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Skeleton(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            Row(children: const [
              SkeletonBox(width: 42, height: 42, circle: true),
              SizedBox(width: 14),
              Expanded(child: SkeletonBox(height: 20)),
            ]),
            const SizedBox(height: 18),
            const SkeletonBox(height: 220, radius: R.card),
            const SizedBox(height: 12),
            Row(children: const [
              Expanded(child: SkeletonBox(height: 64, radius: 12)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 64, radius: 12)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 64, radius: 12)),
            ]),
            const SizedBox(height: 22),
            const _IssueCardSkeleton(),
            const _IssueCardSkeleton(),
          ],
        ),
      );
}
