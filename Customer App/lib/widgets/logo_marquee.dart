import 'package:flutter/material.dart';

/// A row of items that drifts right to left, forever.
///
/// The list is repeated enough times to cover the viewport plus one whole set.
/// The animation translates the row by exactly one set width and then restarts,
/// and because copy N+1 was already sitting where copy N was, the loop point is
/// invisible — the row never jumps back.
///
/// The two ends fade out through a gradient mask rather than being sliced off at
/// the screen edge, which is what makes it read as a marquee instead of a strip
/// that got clipped.
///
/// Every item is the same width. That is the whole trick: it lets the length of
/// one pass be known without measuring anything, so the loop can be driven by a
/// plain repeating controller instead of a scroll listener.
class InfiniteLogoMarquee extends StatefulWidget {
  /// Number of distinct items. One pass of the row is this many items.
  final int itemCount;

  /// Fixed width of every item.
  final double itemExtent;

  /// Vertical space the row needs.
  final double height;

  /// Space between items. The gap is also added after the last item of a pass,
  /// so one pass is exactly `itemCount * (itemExtent + gap)` wide.
  final double gap;

  /// Drift speed. The loop duration is derived from this rather than being a
  /// constant, so the row moves at the same rate regardless of screen width or
  /// how many items there are.
  final double pixelsPerSecond;

  /// Width of the transparent gradient at each end.
  final double fadeExtent;

  final Widget Function(BuildContext context, int index) itemBuilder;

  const InfiniteLogoMarquee({
    super.key,
    required this.itemCount,
    required this.itemExtent,
    required this.height,
    required this.itemBuilder,
    this.gap = 12,
    this.pixelsPerSecond = 30,
    this.fadeExtent = 40,
  });

  @override
  State<InfiniteLogoMarquee> createState() => _InfiniteLogoMarqueeState();
}

class _InfiniteLogoMarqueeState extends State<InfiniteLogoMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// The duration the current layout wants, worked out during build.
  Duration? _desiredPeriod;

  /// The duration actually running, so the controller is not restarted on every
  /// unrelated rebuild.
  Duration? _runningPeriod;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// One full pass of the list.
  double get _passWidth =>
      widget.itemCount * (widget.itemExtent + widget.gap);

  /// Repeat count that keeps the row full width even at the moment the
  /// animation restarts: enough copies to cover the viewport, plus the one
  /// that is about to slide in from the right.
  int _copiesFor(double viewportWidth) {
    final passWidth = _passWidth;
    if (passWidth <= 0 || viewportWidth <= 0) return 1;
    // ceil() throws on an unbounded width, which is what a marquee dropped into
    // a horizontal scroll view would be handed.
    final ratio = viewportWidth / passWidth;
    if (!ratio.isFinite) return 1;
    return ratio.ceil() + 1;
  }

  void _requestPeriod(Duration? period) {
    if (_desiredPeriod == period) return;
    _desiredPeriod = period;
    // repeat()/stop() notify their listeners, which is not allowed while the
    // tree is laying out, so the controller is only ever touched after the
    // frame that asked for it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // A newer layout may have superseded this one before the frame ended.
      if (_desiredPeriod != period) return;
      if (period == null) {
        _runningPeriod = null;
        _controller.stop();
      } else if (_runningPeriod != period || !_controller.isAnimating) {
        _runningPeriod = period;
        _controller.repeat(period: period);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Someone who has asked the platform for less motion gets a strip they can
    // swipe instead of one that will not stop moving.
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (widget.itemCount <= 0) {
      _requestPeriod(null);
      return const SizedBox.shrink();
    }

    if (reduceMotion) {
      _requestPeriod(null);
      return _buildStatic();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final passWidth = _passWidth;

        if (!viewportWidth.isFinite || viewportWidth <= 0 || passWidth <= 0) {
          _requestPeriod(null);
          return SizedBox(height: widget.height);
        }

        _requestPeriod(
          Duration(milliseconds: (passWidth / widget.pixelsPerSecond * 1000).round()),
        );

        final row = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var copy = 0; copy < _copiesFor(viewportWidth); copy++)
              for (var i = 0; i < widget.itemCount; i++) ...[
                SizedBox(
                  width: widget.itemExtent,
                  child: widget.itemBuilder(context, i),
                ),
                SizedBox(width: widget.gap),
              ],
          ],
        );

        return SizedBox(
          width: viewportWidth,
          height: widget.height,
          // Clips the row to the viewport, which the fading row would otherwise
          // spill across the sections above and below.
          child: ClipRect(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              // Sized to the viewport by the SizedBox above, so the gradient
              // stops land on the screen edges rather than on the far end of the
              // row.
              shaderCallback: (bounds) {
                final fade =
                    widget.fadeExtent.clamp(0.0, bounds.width / 2).toDouble();
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: const [
                    Color(0x00FFFFFF),
                    Color(0xFFFFFFFF),
                    Color(0xFFFFFFFF),
                    Color(0x00FFFFFF),
                  ],
                  stops: [0, fade / bounds.width, 1 - fade / bounds.width, 1],
                ).createShader(bounds);
              },
              // Lets the row be wider than the viewport — a plain Row inside a
              // tight box would overflow the layout rather than the screen.
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                child: AnimatedBuilder(
                  animation: _controller,
                  child: row,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(-_controller.value * passWidth, 0),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatic() {
    return SizedBox(
      height: widget.height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: widget.itemCount,
        separatorBuilder: (_, _) => SizedBox(width: widget.gap),
        itemBuilder: (context, index) => SizedBox(
          width: widget.itemExtent,
          child: widget.itemBuilder(context, index),
        ),
      ),
    );
  }
}
