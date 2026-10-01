import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared motion vocabulary for the login / OTP flow.
///
/// Every duration and curve used by the auth screens lives here so the two
/// screens feel like one product rather than two that happen to be adjacent.
class AuthMotion {
  AuthMotion._();

  /// The brand fill, resolved from AppTheme so the auth screens can never drift
  /// away from the palette the rest of the app uses.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppTheme.accentGradientStart, AppTheme.accentGradientEnd],
  );

  /// Extra mid-tone used only while the sheen sweeps.
  static const Color sheenMidTone = AppTheme.accentGradientLightEnd;

  /// The opaque backdrop [authRoute] paints outside its fade.
  ///
  /// Keyed so tests can assert the previous route is covered rather than
  /// showing through.
  static const Key routeBackdropKey = Key('auth-route-backdrop');

  static const fast = Duration(milliseconds: 180);
  static const base = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);
  static const reveal = Duration(milliseconds: 900);

  static const curve = Curves.easeOutCubic;
  static const curveInOut = Curves.easeInOutCubic;
  static const spring = Curves.easeOutBack;
}

/// Reveals a list of children one after another from a single controller.
///
/// One controller driving staggered intervals is much cheaper than giving every
/// child its own, and it keeps the whole header in lockstep.
class StaggeredReveal extends StatefulWidget {
  const StaggeredReveal({
    super.key,
    required this.children,
    this.duration = AuthMotion.reveal,
    this.startDelay = 0.05,
    this.step = 0.085,
    this.offset = 18,
  });

  final List<Widget> children;
  final Duration duration;

  /// Fraction of the timeline spent before the first child starts.
  final double startDelay;

  /// Gap between consecutive children, as a fraction of the timeline.
  final double step;

  final double offset;

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.children.length;
    // Each child gets the same visible window; the last one still finishes on
    // time because the span is derived from the spacing.
    final span = (1.0 - widget.startDelay - widget.step * (n - 1)).clamp(0.05, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(n, (i) {
        final start = widget.startDelay + widget.step * i;
        return AnimatedBuilder(
          animation: _c,
          // Skip rebuilding items whose interval has not started yet.
          child: widget.children[i],
          builder: (context, child) {
            if (_c.value < start) return Opacity(opacity: 0, child: child);
            final a = CurvedAnimation(
              parent: _c,
              curve: Interval(start, math.min(1.0, start + span),
                  curve: AuthMotion.curve),
            );
            return Opacity(
              opacity: a.value,
              child: Transform.translate(
                offset: Offset(0, widget.offset * (1 - a.value)),
                child: child,
              ),
            );
          },
        );
      }),
    );
  }
}

/// Shakes its child when [token] changes. Incremented by the parent to re-fire.
class Shake extends StatefulWidget {
  const Shake({
    super.key,
    required this.child,
    this.token = 0,
    this.amplitude = 10,
    this.duration = const Duration(milliseconds: 460),
  });

  final Widget child;
  final int token;
  final double amplitude;
  final Duration duration;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);

  // Damped oscillation: each leg is explicit and ends at zero so the row always
  // settles where it started.
  late final Animation<double> _t = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 1),
    TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: -1)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 2),
    TweenSequenceItem(
        tween: Tween<double>(begin: -1, end: 1)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 2),
    TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: -0.6)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 2),
    TweenSequenceItem(
        tween: Tween<double>(begin: -0.6, end: 0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 1),
  ]).animate(_c);

  @override
  void didUpdateWidget(Shake old) {
    super.didUpdateWidget(old);
    if (widget.token != old.token) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Transform.translate(
        offset: Offset(widget.amplitude * _t.value, 0),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Primary auth button. While [loading] it keeps its label and runs a sheen
/// across the gradient instead of swapping in a spinner, which reads far more
/// finished than a bare progress indicator.
class SweepButton extends StatefulWidget {
  const SweepButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.leading,
    this.height = 56,
    this.gradient,
    this.foreground,
    this.textSize = 16,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? leading;
  final double height;

  /// Base fill. Defaults to the brand gradient. Exposed so tests and callers
  /// can read back what is actually being painted.
  final Gradient? gradient;

  /// Label colour. Null means "whatever the theme puts on primary", so the
  /// button stays legible if the brand colour ever changes.
  final Color? foreground;

  final double textSize;

  @override
  State<SweepButton> createState() => _SweepButtonState();
}

class _SweepButtonState extends State<SweepButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1150));

  @override
  void initState() {
    super.initState();
    if (widget.loading) _c.repeat();
  }

  @override
  void didUpdateWidget(SweepButton old) {
    super.didUpdateWidget(old);
    if (widget.loading && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.loading && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final radius = BorderRadius.circular(widget.height / 2);
    final foreground = widget.foreground ?? Theme.of(context).colorScheme.onPrimary;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // The brand fill must always be present, idle or loading: defaulting
        // it only on the loading path would leave the idle button transparent.
        final base = widget.gradient ?? AuthMotion.brandGradient;

        // Sweeping the gradient's own begin/end is cheaper than overlaying a
        // second gradient, and it never leaves a hard seam at either edge.
        final s = _c.value;
        final live = widget.loading
            ? LinearGradient(
                begin: Alignment(-1 + 2.6 * s, -0.2),
                end: Alignment(-0.4 + 2.6 * s, 0.2),
                colors: _sheenColors(base),
              )
            : base;

        return Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(gradient: live, borderRadius: radius),
            child: InkWell(
              onTap: enabled ? widget.onPressed : null,
              borderRadius: radius,
              splashColor: Colors.white24,
              highlightColor: Colors.white12,
              child: SizedBox(
                height: widget.height,
                child: Center(
                  child: AnimatedOpacity(
                    duration: AuthMotion.fast,
                    opacity: widget.loading ? 0.55 : 1,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.leading != null) ...[
            Icon(widget.leading, size: 20, color: foreground),
            const SizedBox(width: 10),
          ],
          Text(
            widget.label,
            style: TextStyle(
              color: foreground,
              fontSize: widget.textSize,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _sheenColors(Gradient? g) {
    if (g is LinearGradient && g.colors.isNotEmpty) {
      return g.colors;
    }
    return const [
      AppTheme.accentGradientStart,
      AuthMotion.sheenMidTone,
      AppTheme.accentGradientEnd,
    ];
  }
}

/// Two very slow drifting radial washes. Costs one repeating controller and two
/// gradients, and it stops the auth screens reading as a flat white box.
///
/// The wash is transparent by design; [AuthShell] is what paints the opaque
/// themed base underneath it.
class AmbientBackdrop extends StatefulWidget {
  const AmbientBackdrop({
    super.key,
    this.color,
    this.enabled = true,
    this.intensityLight = 0.14,
    this.intensityDark = 0.22,
  });

  /// Wash tint. Null resolves to the theme's primary at build time.
  final Color? color;
  final bool enabled;

  /// Peak alpha per wash. Dark needs a stronger wash to read at all.
  final double intensityLight;
  final double intensityDark;

  @override
  State<AmbientBackdrop> createState() => _AmbientBackdropState();
}

class _AmbientBackdropState extends State<AmbientBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 22))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tint = widget.color ?? theme.colorScheme.primary;
    final peak = isDark ? widget.intensityDark : widget.intensityLight;

    final turn = _c.value * 2 * math.pi;
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-0.75 + 0.30 * math.sin(turn),
                          -0.85 + 0.12 * math.cos(turn)),
                      radius: 0.95,
                      colors: [
                        tint.withValues(alpha: peak),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.80 + 0.26 * math.cos(turn),
                          0.95 + 0.12 * math.sin(turn)),
                      radius: 0.9,
                      colors: [
                        tint.withValues(alpha: peak * 0.72),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fade-through push used between the auth screens and the app shell, so
/// arriving at the app feels like a continuation rather than a hard cut.
///
/// The opaque backdrop sits *outside* the fade. Fading the whole route leaves
/// the incoming screen semi-transparent while it animates, which lets the
/// outgoing screen's text stay legible underneath it. Covering the previous
/// route on the first frame and fading only the content keeps the motion
/// without the ghosting.
Route<T> authRoute<T>({
  required WidgetBuilder builder,
  Duration duration = const Duration(milliseconds: 460),
}) {
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: const Duration(milliseconds: 340),
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (context, animation, _, child) {
      final fadeIn = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.72, curve: AuthMotion.curve),
      );

      return Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              key: AuthMotion.routeBackdropKey,
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
          ),
          FadeTransition(
            opacity: fadeIn,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.03),
                end: Offset.zero,
              ).animate(fadeIn),
              child: child,
            ),
          ),
        ],
      );
    },
  );
}
