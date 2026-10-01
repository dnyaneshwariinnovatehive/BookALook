import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Loading placeholders in the shape of the content that is on its way.
///
/// A spinner in the middle of an empty page says "wait" and nothing else; a
/// skeleton says what is coming and where, so the page does not jump when it
/// arrives. Every shape inside one [Skeleton] shares a single shimmer: the
/// boxes are painted flat, and one [ShaderMask] sweeps a highlight across all
/// of them, so a list reads as one surface loading rather than a dozen
/// independently blinking rectangles.
///
/// Honours the platform's reduce-motion setting by holding still, and is
/// announced once as "Loading" — the shapes themselves are hidden from screen
/// readers, which would otherwise read out a stack of unlabelled boxes.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child, this.semanticLabel = 'Loading'});

  final Widget child;
  final String semanticLabel;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final shapes = ExcludeSemantics(child: widget.child);

    return Semantics(
      label: widget.semanticLabel,
      liveRegion: true,
      child: still
          ? shapes
          : AnimatedBuilder(
              animation: _c,
              child: shapes,
              builder: (context, child) => ShaderMask(
                // srcATop: the highlight lands only where a box is painted.
                blendMode: BlendMode.srcATop,
                shaderCallback: (bounds) => LinearGradient(
                  colors: [
                    colors.border,
                    colors.surface.withValues(alpha: 0.9),
                    colors.border,
                  ],
                  stops: const [0.35, 0.5, 0.65],
                  transform: _Slide(_c.value),
                ).createShader(bounds),
                child: child,
              ),
            ),
    );
  }
}

/// Moves the shimmer band from off the left edge to off the right.
class _Slide extends GradientTransform {
  const _Slide(this.t);

  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (2 * t - 1), 0, 0);
}

/// One flat placeholder shape. Draws in the theme's border colour so it reads
/// as "not loaded yet" on both a white and a near-black surface.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.border,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A short line of placeholder text, [widthFactor] of the available width.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.widthFactor = 1, this.height = 12});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: SkeletonBox(height: height, radius: height / 2),
    );
  }
}

/// [count] placeholders in a scrollable list, for screens whose content is a
/// list. Always scrollable, so pull-to-refresh still works while loading.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    required this.itemBuilder,
    this.count = 5,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 0),
  });

  final WidgetBuilder itemBuilder;
  final int count;
  final EdgeInsetsGeometry padding;

  /// Present while a list screen is loading, for tests.
  static const Key listKey = Key('skeleton-list');

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView.builder(
        key: listKey,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        itemCount: count,
        itemBuilder: (context, _) => itemBuilder(context),
      ),
    );
  }
}

/// The shape of [DiscoverySalonCard]: 12px padding, radius 20, a 100x114
/// photo on the left and the name, location, rating and chips beside it.
class SalonCardSkeleton extends StatelessWidget {
  const SalonCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.colors.listBorder, width: 1.5),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 100, height: 114, radius: 14),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 4),
                  SkeletonLine(widthFactor: 0.75, height: 16),
                  SizedBox(height: 10),
                  SkeletonLine(widthFactor: 0.55),
                  SizedBox(height: 10),
                  SkeletonLine(widthFactor: 0.35),
                  SizedBox(height: 18),
                  Row(
                    children: [
                      SkeletonBox(width: 64, height: 22, radius: 6),
                      SizedBox(width: 8),
                      SkeletonBox(width: 52, height: 22, radius: 6),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The shape of a booking card on My Bookings: radius 26, a thumbnail and two
/// lines of salon detail, the date row, and the action buttons.
class BookingCardSkeleton extends StatelessWidget {
  const BookingCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: context.colors.cardBorder),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SkeletonBox(width: 56, height: 56, radius: 10),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonLine(widthFactor: 0.7, height: 15),
                      SizedBox(height: 8),
                      SkeletonLine(widthFactor: 0.45),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                SkeletonBox(width: 70, height: 24, radius: 12),
              ],
            ),
            SizedBox(height: 16),
            SkeletonLine(widthFactor: 0.6),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: SkeletonBox(height: 44, radius: 22)),
                SizedBox(width: 12),
                Expanded(child: SkeletonBox(height: 44, radius: 22)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The shape of a category tile: a rounded square with a label under it.
class CategoryTileSkeleton extends StatelessWidget {
  const CategoryTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(aspectRatio: 1, child: SkeletonBox(height: double.infinity, radius: 18)),
        SizedBox(height: 8),
        SkeletonLine(widthFactor: 0.7, height: 10),
      ],
    );
  }
}

/// A search result row: a leading square and two lines.
class ResultRowSkeleton extends StatelessWidget {
  const ResultRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SkeletonBox(width: 48, height: 48, radius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(widthFactor: 0.6, height: 14),
                SizedBox(height: 8),
                SkeletonLine(widthFactor: 0.4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The salon detail page while it loads: the cover photo, the name and
/// address block, and the first section of services.
class SalonDetailSkeleton extends StatelessWidget {
  const SalonDetailSkeleton({super.key});

  /// Present while the salon page is loading, for tests.
  static const Key pageKey = Key('salon-detail-skeleton');

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView(
        key: pageKey,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          const SkeletonBox(height: 280, radius: 0),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLine(widthFactor: 0.65, height: 22),
                const SizedBox(height: 12),
                const SkeletonLine(widthFactor: 0.85),
                const SizedBox(height: 8),
                const SkeletonLine(widthFactor: 0.5),
                const SizedBox(height: 24),
                const Row(
                  children: [
                    SkeletonBox(width: 90, height: 32, radius: 16),
                    SizedBox(width: 8),
                    SkeletonBox(width: 90, height: 32, radius: 16),
                    SizedBox(width: 8),
                    SkeletonBox(width: 90, height: 32, radius: 16),
                  ],
                ),
                const SizedBox(height: 24),
                for (var i = 0; i < 3; i++) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: context.colors.border),
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonLine(widthFactor: 0.6, height: 15),
                              SizedBox(height: 8),
                              SkeletonLine(widthFactor: 0.3),
                            ],
                          ),
                        ),
                        SizedBox(width: 12),
                        SkeletonBox(width: 72, height: 34, radius: 17),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
