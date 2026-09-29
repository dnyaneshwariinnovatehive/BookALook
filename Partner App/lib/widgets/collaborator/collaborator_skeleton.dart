import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Drives a single looping [Animation] that every [SkeletonBox] below it reads.
///
/// The alternative — one controller per box — means a list of six skeletons
/// runs six independent timers, and they drift out of phase so the page looks
/// like a flicker rather than a sweep.
class CollaboratorSkeleton extends StatefulWidget {
  final Widget child;

  const CollaboratorSkeleton({super.key, required this.child});

  @override
  State<CollaboratorSkeleton> createState() => _CollaboratorSkeletonState();
}

class _CollaboratorSkeletonState extends State<CollaboratorSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) =>
          _ShimmerScope(animation: _controller, child: child!),
      child: widget.child,
    );
  }
}

/// Makes the sweep available to descendants without threading a build
/// parameter through every intermediate widget.
class _ShimmerScope extends InheritedWidget {
  final Animation<double> animation;

  const _ShimmerScope({required this.animation, required super.child});

  @override
  bool updateShouldNotify(_ShimmerScope oldWidget) => false;
}

extension on BuildContext {
  Animation<double>? get _shimmer {
    final scope = dependOnInheritedWidgetOfExactType<_ShimmerScope>();
    return scope?.animation;
  }
}

/// A single shimmering placeholder block.
///
/// Rounded to match [radius] so the placeholder has the same silhouette as the
/// real content it stands in for — a skeleton of the wrong shape is more
/// jarring than a spinner.
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final shimmer = context._shimmer;

    // Used outside a [CollaboratorSkeleton] — e.g. in a widget test, or a tab
    // preview. Falls back to a flat fill rather than crashing.
    final highlight = Color.lerp(
      palette.surfaceMuted,
      palette.border,
      shimmer == null ? 0 : 0.6 * (1 - (shimmer.value * 2 - 1).abs()),
    )!;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: highlight,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// The three stacked cards that stand in for a list while it loads.
class CollaboratorCardSkeleton extends StatelessWidget {
  final int count;

  const CollaboratorCardSkeleton({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return CollaboratorSkeleton(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < count; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.colors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 60, height: 60, radius: 10),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonBox(height: 15, radius: 5),
                        SizedBox(height: 8),
                        SkeletonBox(height: 11, radius: 5),
                        SizedBox(height: 6),
                        SkeletonBox(height: 11, width: 140, radius: 5),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A block skeleton for a full screen of tiles, e.g. the Home stat row.
class SkeletonRow extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const SkeletonRow({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    return CollaboratorSkeleton(
      child: Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: children[i]),
            ],
          ],
        ),
      ),
    );
  }
}
