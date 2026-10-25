import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// What the customer sees while their invoice loads: a paper invoice that
/// writes itself, line by line, while a soft scan passes over it, then a
/// check pops on the corner as it is handed over.
///
/// Always centred in the space it is given and scaled down on short screens,
/// so it never sits at the top or overflows. It shows for at least the length
/// of the writing animation so a fast load does not flash, and finishes the
/// moment [isReady] turns true after that. [onFinished] fires once the hand-off
/// has played, which is the caller's cue to fade it away.
class InvoiceLoader extends StatefulWidget {
  final bool isReady;
  final VoidCallback onFinished;

  const InvoiceLoader({super.key, required this.isReady, required this.onFinished});

  @override
  State<InvoiceLoader> createState() => _InvoiceLoaderState();
}

enum _Phase { writing, waiting, done }

class _InvoiceLoaderState extends State<InvoiceLoader> with TickerProviderStateMixin {
  late final AnimationController _write;  // lines drawing in, once
  late final AnimationController _loop;   // float + scan, while waiting
  late final AnimationController _finish; // check pop and lift
  _Phase _phase = _Phase.writing;
  Timer? _handOff;
  bool _reducedMotion = false;

  // Line items: (label width, amount width) as fractions of the paper.
  static const _items = [(0.46, 0.18), (0.58, 0.16), (0.38, 0.2), (0.52, 0.14), (0.42, 0.17)];

  @override
  void initState() {
    super.initState();
    _write = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _finish = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

    // After the frame, because completing can happen while dependencies are
    // being set up (reduced motion jumps straight to the end).
    _write.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _phase != _Phase.writing) return;
        setState(() => _phase = _Phase.waiting);
        _maybeFinish();
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced == _reducedMotion && (_write.isAnimating || _write.isCompleted)) return;
    _reducedMotion = reduced;

    if (_reducedMotion) {
      _write.value = 1;
      _loop.stop();
    } else {
      if (!_write.isCompleted) _write.forward();
      _loop.repeat();
    }
  }

  @override
  void didUpdateWidget(InvoiceLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isReady && !oldWidget.isReady) _maybeFinish();
  }

  void _maybeFinish() {
    if (_phase != _Phase.waiting || !widget.isReady) return;
    setState(() => _phase = _Phase.done);
    _loop.stop();
    _finish.forward().whenComplete(() {
      _handOff = Timer(const Duration(milliseconds: 260), () {
        if (mounted) widget.onFinished();
      });
    });
  }

  @override
  void dispose() {
    _handOff?.cancel();
    _write.dispose();
    _loop.dispose();
    _finish.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      key: const ValueKey('invoice_loader'),
      color: colors.surfaceMuted,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _paperStack(colors),
                const SizedBox(height: 34),
                _caption(colors),
                const SizedBox(height: 18),
                _progress(colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- paper

  static const _paperW = 156.0;
  static const _paperH = 200.0;

  Widget _paperStack(AppColors colors) {
    return AnimatedBuilder(
      animation: Listenable.merge([_loop, _finish]),
      builder: (context, child) {
        final float = _reducedMotion ? 0.0 : math.sin(_loop.value * 2 * math.pi) * 4;
        final lift = Curves.easeOut.transform(_finish.value);
        return Transform.translate(
          offset: Offset(0, float - lift * 6),
          child: Transform.scale(scale: 1 + lift * 0.03, child: child),
        );
      },
      child: SizedBox(
        width: _paperW + 44,
        height: _paperH + 36,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // A soft glow under the page.
            Container(
              width: _paperW * 0.9,
              height: _paperH * 0.8,
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(color: AppTheme.accentColor.withValues(alpha: 0.16), blurRadius: 48, spreadRadius: 6),
                ],
              ),
            ),
            // The copy underneath, tilted, so it reads as a document.
            Transform.translate(
              offset: const Offset(-12, 8),
              child: Transform.rotate(
                angle: -0.09,
                child: CustomPaint(
                  size: const Size(_paperW, _paperH),
                  painter: _PaperPainter(fill: Colors.white.withValues(alpha: 0.75), edge: colors.border),
                ),
              ),
            ),
            _frontPage(colors),
            Positioned(
              right: 2,
              bottom: -4,
              child: ScaleTransition(
                scale: CurvedAnimation(parent: _finish, curve: Curves.elasticOut),
                child: Container(
                  key: const ValueKey('invoice_loader_check'),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(color: AppTheme.accentColor.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frontPage(AppColors colors) {
    final ink = AppTheme.accentColor;

    return SizedBox(
      width: _paperW,
      height: _paperH,
      child: CustomPaint(
        painter: _PaperPainter(fill: Colors.white, edge: colors.border, fold: colors.accentSoft, shadow: colors.dropShadow),
        child: ClipPath(
          clipper: _PaperClipper(),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                child: AnimatedBuilder(
                  animation: _write,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Letterhead: mark and salon name.
                      Row(
                        children: [
                          _appear(0.0, 0.18, Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(color: ink.withValues(alpha: 0.22), shape: BoxShape.circle),
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _bar(0.02, 0.2, 0.62, 6, ink.withValues(alpha: 0.28))),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _bar(0.12, 0.28, 0.42, 7, ink.withValues(alpha: 0.55)),
                      const SizedBox(height: 6),
                      _bar(0.16, 0.32, 0.3, 4, ink.withValues(alpha: 0.14)),
                      const SizedBox(height: 16),
                      for (var i = 0; i < _items.length; i++) ...[
                        _lineItem(i, ink),
                        const SizedBox(height: 9),
                      ],
                      const Spacer(),
                      _appear(0.78, 0.86, CustomPaint(size: const Size(double.infinity, 1), painter: _DashPainter(ink.withValues(alpha: 0.25)))),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          _bar(0.82, 0.92, 0.3, 6, ink.withValues(alpha: 0.3)),
                          const Spacer(),
                          _bar(0.86, 1.0, 0.26, 8, ink.withValues(alpha: _phase == _Phase.done ? 0.9 : 0.6)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (!_reducedMotion && _phase != _Phase.done) _scanBeam(ink),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lineItem(int i, Color ink) {
    final start = 0.28 + i * 0.09;
    final (label, amount) = _items[i];
    return Row(
      children: [
        _bar(start, start + 0.14, label, 4.5, ink.withValues(alpha: 0.16)),
        const Spacer(),
        _bar(start + 0.06, start + 0.18, amount, 4.5, ink.withValues(alpha: 0.24)),
      ],
    );
  }

  /// A bar that writes itself in from the left during [from]–[to] of the
  /// writing animation. [widthFactor] is a share of the page's inner width.
  Widget _bar(double from, double to, double widthFactor, double height, Color color) {
    final t = Curves.easeOutCubic.transform(Interval(from, to.clamp(0.0, 1.0)).transform(_write.value));
    return SizedBox(
      width: (_paperW - 32) * widthFactor,
      height: height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: t,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height)),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  Widget _appear(double from, double to, Widget child) {
    final t = Interval(from, to).transform(_write.value);
    return Opacity(opacity: t, child: Transform.scale(scale: 0.6 + 0.4 * t, child: child));
  }

  Widget _scanBeam(Color ink) {
    final beam = SizedBox(
      height: 56,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ink.withValues(alpha: 0), ink.withValues(alpha: 0.10), ink.withValues(alpha: 0)],
          ),
        ),
      ),
    );

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _loop,
          child: beam,
          builder: (context, child) {
            final y = Curves.easeInOut.transform(_loop.value) * (_paperH + 60) - 60;
            return Align(
              alignment: Alignment.topCenter,
              child: Transform.translate(offset: Offset(0, y), child: child),
            );
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------- caption

  Widget _caption(AppColors colors) {
    final (title, detail) = switch (_phase) {
      _Phase.writing => ('Preparing your invoice', 'Adding up your services'),
      _Phase.waiting => ('Preparing your invoice', 'Almost there'),
      _Phase.done => ('Your invoice is ready', 'Opening it now'),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey('$title|$detail'),
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w700, color: colors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(fontSize: 13.5, color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _progress(AppColors colors) {
    return SizedBox(
      width: 148,
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: _phase == _Phase.done || _reducedMotion
            ? LinearProgressIndicator(
                value: _phase == _Phase.done ? 1 : null,
                backgroundColor: colors.accentSoft,
                valueColor: const AlwaysStoppedAnimation(AppTheme.accentColor),
              )
            : LinearProgressIndicator(
                backgroundColor: colors.accentSoft,
                valueColor: const AlwaysStoppedAnimation(AppTheme.accentColor),
              ),
      ),
    );
  }
}

/// A sheet of paper with its top-right corner folded over.
Path _paperPath(Size size) {
  const r = 12.0;
  const fold = 26.0;
  return Path()
    ..moveTo(r, 0)
    ..lineTo(size.width - fold, 0)
    ..lineTo(size.width, fold)
    ..lineTo(size.width, size.height - r)
    ..quadraticBezierTo(size.width, size.height, size.width - r, size.height)
    ..lineTo(r, size.height)
    ..quadraticBezierTo(0, size.height, 0, size.height - r)
    ..lineTo(0, r)
    ..quadraticBezierTo(0, 0, r, 0)
    ..close();
}

class _PaperPainter extends CustomPainter {
  final Color fill;
  final Color edge;
  final Color? fold;
  final Color? shadow;

  _PaperPainter({required this.fill, required this.edge, this.fold, this.shadow});

  @override
  void paint(Canvas canvas, Size size) {
    final page = _paperPath(size);
    if (shadow != null) {
      canvas.drawShadow(page, shadow!.withValues(alpha: 0.5), 6, false);
    }
    canvas.drawPath(page, Paint()..color = fill);
    canvas.drawPath(page, Paint()
      ..color = edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);

    if (fold != null) {
      const f = 26.0;
      final flap = Path()
        ..moveTo(size.width - f, 0)
        ..lineTo(size.width - f, f - 4)
        ..quadraticBezierTo(size.width - f, f, size.width - f + 4, f)
        ..lineTo(size.width, f)
        ..close();
      canvas.drawPath(flap, Paint()..color = fold!);
      canvas.drawPath(flap, Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(_PaperPainter old) =>
      old.fill != fill || old.edge != edge || old.fold != fold || old.shadow != shadow;
}

class _PaperClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => _paperPath(size);

  @override
  bool shouldReclip(_PaperClipper oldClipper) => false;
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 5, size.width), 0), paint);
      x += 9;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
