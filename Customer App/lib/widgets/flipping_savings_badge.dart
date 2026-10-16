import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// A compact, animated ticket-style badge inspired by promotional digital passes
/// and the District app's continuous 3D vertical flip motion.
///
/// Designed specifically for the **Value Packages** section in `SalonDetailScreen`,
/// this badge alternates between two faces:
/// * **Front face**: `Price Drop`
/// * **Back face**: `₹X OFF` (derived from the package's actual savings)
///
/// Design & Motion Features:
/// * **Ticket Geometry**: Custom notched rectangular pass with top and bottom
///   perforated semicircular cutouts and a dashed stub line on the right.
/// * **Mini Barcode Stub**: Decorative mini vertical barcode stripes on the right
///   ticket stub for an authentic promotional pass look.
/// * **Continuous 3D Vertical Flip**: Smoothly rotates 180° around the horizontal
///   axis (X-axis) with realistic perspective depth (`setEntry(3, 2, 0.001)`).
/// * **Zero Text Inversion / Overlap**: Swaps active face content at the exact
///   90° edge-on threshold so text is always right-side up, never mirrored or overlapping.
/// * **Tactile Depth Shading**: Dynamic shading attenuation during rotation to
///   simulate light drop-off as the ticket tilts away from the viewer.
/// * **Legible Pauses**: Pauses for ~1200ms on each face for effortless readability.
/// * **Fixed Footprint**: Strictly maintains fixed layout dimensions (96x24) to
///   eliminate layout reflows and prevent card expansion.
/// * **Accessibility & Reduced Motion**: Automatically renders a static ticket
///   when [MediaQueryData.disableAnimations] or [MediaQueryData.accessibleNavigation] is active.
/// * **Lifecycle Safe**: Cleanly disposes its [AnimationController] without leaks.
class FlippingSavingsBadge extends StatefulWidget {
  /// The monetary savings amount in Rupees (e.g. 100).
  final num savings;

  /// Text on the front face. Defaults to `'Price Drop'`.
  final String frontLabel;

  /// Optional text on the back face. Defaults to `'₹X OFF'`.
  final String? backLabel;

  /// Background color of the ticket. Defaults to BookALook secondary `#EEE3ED`.
  final Color? backgroundColor;

  /// Border and accent color of the ticket. Defaults to BookALook primary `#9850F1`.
  final Color? borderColor;

  /// Text color. Defaults to BookALook accent `#9850F1`.
  final Color? textColor;

  /// Custom text style.
  final TextStyle? textStyle;

  /// Duration of each active 180° vertical flip.
  final Duration flipDuration;

  /// Duration each face rests flat and readable between flips.
  final Duration pauseDuration;

  const FlippingSavingsBadge({
    super.key,
    required this.savings,
    this.frontLabel = 'Price Drop',
    this.backLabel,
    this.backgroundColor,
    this.borderColor,
    this.textColor,
    this.textStyle,
    this.flipDuration = const Duration(milliseconds: 600),
    this.pauseDuration = const Duration(milliseconds: 1200),
  });

  @override
  State<FlippingSavingsBadge> createState() => _FlippingSavingsBadgeState();
}

class _FlippingSavingsBadgeState extends State<FlippingSavingsBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final totalDuration =
        (widget.flipDuration * 2) + (widget.pauseDuration * 2);
    _controller = AnimationController(vsync: this, duration: totalDuration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimationState();
  }

  void _syncAnimationState() {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);

    if (reduceMotion) {
      if (_controller.isAnimating) {
        _controller.stop();
      }
      _controller.value = 0.0;
    } else {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _backFaceText {
    if (widget.backLabel != null) return widget.backLabel!;
    return '₹${widget.savings.toStringAsFixed(0)} OFF';
  }

  String get _frontFaceText => widget.frontLabel;

  @override
  Widget build(BuildContext context) {
    if (widget.savings <= 0 && widget.backLabel == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        widget.backgroundColor ??
        (isDark ? context.colors.accentSoft : const Color(0xFFEEE3ED));
    final strokeColor = widget.borderColor ?? AppTheme.accentColor;
    final fontColor =
        widget.textColor ?? (isDark ? Colors.white : AppTheme.accentColor);

    final style =
        widget.textStyle ??
        GoogleFonts.outfit(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: fontColor,
          letterSpacing: 0.15,
        );

    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);

    // Ticket dimensions
    const ticketWidth = 96.0;
    const ticketHeight = 24.0;
    const stubWidth = 18.0;
    const mainBodyWidth = ticketWidth - stubWidth;

    if (reduceMotion) {
      return SizedBox(
        width: ticketWidth,
        height: ticketHeight,
        child: CustomPaint(
          painter: _TicketPainter(
            backgroundColor: bgColor,
            borderColor: strokeColor,
            stubWidth: stubWidth,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: mainBodyWidth,
              child: Center(
                child: Text(
                  _backFaceText,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final flipMs = widget.flipDuration.inMilliseconds.toDouble();
    final pauseMs = widget.pauseDuration.inMilliseconds.toDouble();
    final totalMs = (flipMs * 2) + (pauseMs * 2);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final currentMs = _controller.value * totalMs;

        // Sequence of 4 phases in totalMs:
        // 1. [0 .. pauseMs): Front face ('Price Drop') resting flat
        // 2. [pauseMs .. pauseMs + flipMs): Flip from Front to Back
        // 3. [pauseMs + flipMs .. pauseMs * 2 + flipMs): Back face ('₹X OFF') resting flat
        // 4. [pauseMs * 2 + flipMs .. totalMs): Flip from Back to Front
        final phase2Start = pauseMs;
        final phase3Start = pauseMs + flipMs;
        final phase4Start = (pauseMs * 2) + flipMs;

        bool isFront = true;
        double rawAngle = 0.0;

        if (currentMs < phase2Start) {
          // Phase 1: Front face resting flat
          isFront = true;
          rawAngle = 0.0;
        } else if (currentMs < phase3Start) {
          // Phase 2: Flip from Front to Back
          final u = (currentMs - phase2Start) / flipMs;
          final k = Curves.easeInOutCubic.transform(u.clamp(0.0, 1.0));
          if (k < 0.5) {
            isFront = true;
            rawAngle = k * math.pi;
          } else {
            isFront = false;
            rawAngle = (k - 1.0) * math.pi;
          }
        } else if (currentMs < phase4Start) {
          // Phase 3: Back face resting flat
          isFront = false;
          rawAngle = 0.0;
        } else {
          // Phase 4: Flip from Back to Front
          final u = (currentMs - phase4Start) / flipMs;
          final k = Curves.easeInOutCubic.transform(u.clamp(0.0, 1.0));
          if (k < 0.5) {
            isFront = false;
            rawAngle = k * math.pi;
          } else {
            isFront = true;
            rawAngle = (k - 1.0) * math.pi;
          }
        }

        final visibleText = isFront ? _frontFaceText : _backFaceText;

        // Dynamic tactile depth shading as the ticket rotates edge-on
        final shadeAlpha = (0.16 * math.sin(rawAngle.abs())).clamp(0.0, 0.16);

        // 3D perspective matrix
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateX(rawAngle);

        return SizedBox(
          width: ticketWidth,
          height: ticketHeight,
          child: Transform(
            transform: matrix,
            alignment: Alignment.center,
            child: CustomPaint(
              painter: _TicketPainter(
                backgroundColor: bgColor,
                borderColor: strokeColor,
                stubWidth: stubWidth,
                shadeAlpha: shadeAlpha,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: mainBodyWidth,
                  child: Center(
                    child: Text(
                      visibleText,
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Custom painter for the ticket shape with top and bottom semicircular notches,
/// a dashed perforation divider line, and a mini vertical barcode on the right stub.
class _TicketPainter extends CustomPainter {
  final Color backgroundColor;
  final Color borderColor;
  final double stubWidth;
  final double shadeAlpha;

  static const double borderWidth = 1.0;
  static const double cornerRadius = 5.0;
  static const double notchRadius = 2.5;

  const _TicketPainter({
    required this.backgroundColor,
    required this.borderColor,
    this.stubWidth = 18.0,
    this.shadeAlpha = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dividerX = size.width - stubWidth;
    final r = cornerRadius;
    final nr = notchRadius;

    // Build the ticket contour with top and bottom semicircular cutout notches
    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(dividerX - nr, 0)
      ..arcToPoint(
        Offset(dividerX + nr, 0),
        radius: Radius.circular(nr),
        clockwise: false,
      )
      ..lineTo(size.width - r, 0)
      ..arcToPoint(Offset(size.width, r), radius: Radius.circular(r))
      ..lineTo(size.width, size.height - r)
      ..arcToPoint(
        Offset(size.width - r, size.height),
        radius: Radius.circular(r),
      )
      ..lineTo(dividerX + nr, size.height)
      ..arcToPoint(
        Offset(dividerX - nr, size.height),
        radius: Radius.circular(nr),
        clockwise: false,
      )
      ..lineTo(r, size.height)
      ..arcToPoint(Offset(0, size.height - r), radius: Radius.circular(r))
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..close();

    // 1. Fill ticket background
    final fillPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // 2. Stroke ticket border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawPath(path, borderPaint);

    // 3. Draw vertical dashed perforation line between the two notches
    final dashPaint = Paint()
      ..color = borderColor.withValues(alpha: 0.45)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const dashLength = 2.0;
    const dashGap = 2.0;
    double currentY = nr + 1.5;
    final maxY = size.height - nr - 1.5;

    while (currentY < maxY) {
      final endY = math.min(currentY + dashLength, maxY);
      canvas.drawLine(
        Offset(dividerX, currentY),
        Offset(dividerX, endY),
        dashPaint,
      );
      currentY += dashLength + dashGap;
    }

    // 4. Draw mini barcode stripes on the right stub
    final barcodePaint = Paint()
      ..color = borderColor.withValues(alpha: 0.5)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final stubCenterX = dividerX + (stubWidth / 2);
    final centerY = size.height / 2;

    // Bar 1 (thin, short)
    barcodePaint.strokeWidth = 1.0;
    canvas.drawLine(
      Offset(stubCenterX - 3.5, centerY - 3.5),
      Offset(stubCenterX - 3.5, centerY + 3.5),
      barcodePaint,
    );

    // Bar 2 (medium, taller)
    barcodePaint.strokeWidth = 1.6;
    canvas.drawLine(
      Offset(stubCenterX - 0.5, centerY - 5.5),
      Offset(stubCenterX - 0.5, centerY + 5.5),
      barcodePaint,
    );

    // Bar 3 (thin, medium)
    barcodePaint.strokeWidth = 1.0;
    canvas.drawLine(
      Offset(stubCenterX + 2.5, centerY - 4.0),
      Offset(stubCenterX + 2.5, centerY + 4.0),
      barcodePaint,
    );

    // 5. Tactile 3D depth shading layer when rotating
    if (shadeAlpha > 0.001) {
      final shadePaint = Paint()
        ..color = Colors.black.withValues(alpha: shadeAlpha)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, shadePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TicketPainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.shadeAlpha != shadeAlpha;
  }
}
