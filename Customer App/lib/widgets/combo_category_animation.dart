import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A seamless, repeating 10-stage animation for the Combo category in BookALook.
///
/// Communicates that the Combo category brings together four salon services:
/// **Hair, Skin, Nails, and Spa**.
///
/// Sequence:
/// - Stage 1 (0.00 – 0.08): Closed glossy purple basket (initial state).
/// - Stage 2 (0.08 – 0.18): Basket opens, warm radiant glow and sparkles appear.
/// - Stage 3 (0.18 – 0.30): Hair service icon pops out (top-left).
/// - Stage 4 (0.30 – 0.42): Skin service icon pops out (top-right).
/// - Stage 5 (0.42 – 0.54): Nails service icon pops out (mid-left).
/// - Stage 6 (0.54 – 0.66): Spa service icon pops out (mid-right, all 4 visible).
/// - Stage 7 (0.66 – 0.82): Combo reveal — all 4 float with sparkles & aura.
/// - Stage 8 (0.82 – 0.92): Icons shrink and return inside basket.
/// - Stage 9 (0.92 – 0.97): Basket lid hinges closed, glow fades.
/// - Stage 10 (0.97 – 1.00): Basket resting closed, seamless loop back to 0.00.
class ComboCategoryAnimation extends StatefulWidget {
  final Color primaryColor;
  final Color backgroundColor;

  const ComboCategoryAnimation({
    super.key,
    this.primaryColor = const Color(0xFF9850F1),
    this.backgroundColor = const Color(0xFFEEE3FD),
  });

  @override
  State<ComboCategoryAnimation> createState() => _ComboCategoryAnimationState();
}

class _ComboCategoryAnimationState extends State<ComboCategoryAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 5.8 seconds per full cycle provides a luxurious, readable pace
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5800),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (reduceMotion) {
      // In reduced-motion mode, show static Stage 7 (all 4 services revealed)
      return CustomPaint(
        painter: _ComboFullScenePainter(
          t: 0.74, // Stage 7 snapshot
          primaryColor: widget.primaryColor,
          backgroundColor: widget.backgroundColor,
          isReducedMotion: true,
        ),
        size: Size.infinite,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _ComboFullScenePainter(
            t: _controller.value,
            primaryColor: widget.primaryColor,
            backgroundColor: widget.backgroundColor,
            isReducedMotion: false,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

/// Backward compatibility alias
typedef AnimatedCombosIllustration = ComboCategoryAnimation;

/// Single unified painter that handles layering, articulation, clipping, and motion.
class _ComboFullScenePainter extends CustomPainter {
  final double t; // 0.0 .. 1.0
  final Color primaryColor;
  final Color backgroundColor;
  final bool isReducedMotion;

  _ComboFullScenePainter({
    required this.t,
    required this.primaryColor,
    required this.backgroundColor,
    required this.isReducedMotion,
  });

  // Helper to calculate linear progress in range [start, end]
  static double _progress(double val, double start, double end) {
    if (val <= start) return 0.0;
    if (val >= end) return 1.0;
    return (val - start) / (end - start);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // Center coordinates & key anchor points
    final basketRimY = h * 0.60;
    final basketBottomY = h * 0.90;

    // --- TIMELINE STATE CALCULATION ---
    // Stage 1 (0.00..0.08) & Stage 10 (0.97..1.00): Closed basket
    // Stage 2 (0.08..0.18): Basket opens
    // Stage 3 (0.18..0.30): Hair pops up
    // Stage 4 (0.30..0.42): Skin pops up
    // Stage 5 (0.42..0.54): Nails pops up
    // Stage 6 (0.54..0.66): Spa pops up (all visible)
    // Stage 7 (0.66..0.82): Combo reveal floating
    // Stage 8 (0.82..0.92): Icons return to basket
    // Stage 9 (0.92..0.97): Basket closes

    // 1. Lid Open Angle: 0.0 (closed) -> 1.0 (fully open) -> 0.0 (closed)
    double lidOpen = 0.0;
    if (t >= 0.08 && t < 0.18) {
      lidOpen = Curves.easeInOutBack.transform(_progress(t, 0.08, 0.18));
    } else if (t >= 0.18 && t <= 0.92) {
      lidOpen = 1.0;
    } else if (t > 0.92 && t <= 0.97) {
      lidOpen = 1.0 - Curves.easeInOutCubic.transform(_progress(t, 0.92, 0.97));
    }

    // 2. Interior Glow & Rays: 0.0 -> 1.0 -> 0.0
    double glowAlpha = 0.0;
    if (t >= 0.08 && t < 0.18) {
      glowAlpha = Curves.easeIn.transform(_progress(t, 0.08, 0.18));
    } else if (t >= 0.18 && t <= 0.91) {
      glowAlpha = 1.0;
    } else if (t > 0.91 && t <= 0.97) {
      glowAlpha = 1.0 - Curves.easeOut.transform(_progress(t, 0.91, 0.97));
    }

    // 3. Basket subtle spring/breath reaction
    double basketScaleY = 1.0;
    double basketScaleX = 1.0;
    if (t >= 0.08 && t < 0.18) {
      final openBounce = math.sin(_progress(t, 0.08, 0.18) * math.pi);
      basketScaleY = 1.0 - (openBounce * 0.03);
      basketScaleX = 1.0 + (openBounce * 0.02);
    } else if (t >= 0.95 && t <= 1.00) {
      final closeBounce = math.sin(_progress(t, 0.95, 1.00) * math.pi);
      basketScaleY = 1.0 - (closeBounce * 0.02);
    }

    // Floating harmonic wave during reveal
    final floatPhase = isReducedMotion ? 0.0 : (t * 8.0 * math.pi);

    // Individual icon parameters: (scale, x, y, rotation, alpha)
    final hair = _calcIcon(
      t: t,
      emergeStart: 0.18,
      emergeEnd: 0.30,
      returnStart: 0.86,
      returnEnd: 0.92,
      origin: Offset(w * 0.50, basketRimY + 4),
      target: Offset(w * 0.36, basketRimY - h * 0.40),
      floatOffset: Offset(0, math.sin(floatPhase) * (h * 0.03)),
      initialRotation: -0.22,
      targetRotation: -0.08,
      w: w,
      h: h,
    );

    final skin = _calcIcon(
      t: t,
      emergeStart: 0.30,
      emergeEnd: 0.42,
      returnStart: 0.85,
      returnEnd: 0.90,
      origin: Offset(w * 0.52, basketRimY + 4),
      target: Offset(w * 0.67, basketRimY - h * 0.38),
      floatOffset: Offset(0, math.sin(floatPhase + 1.2) * (h * 0.03)),
      initialRotation: 0.25,
      targetRotation: 0.08,
      w: w,
      h: h,
    );

    final nails = _calcIcon(
      t: t,
      emergeStart: 0.42,
      emergeEnd: 0.54,
      returnStart: 0.82,
      returnEnd: 0.87,
      origin: Offset(w * 0.48, basketRimY + 4),
      target: Offset(w * 0.27, basketRimY - h * 0.18),
      floatOffset: Offset(0, math.sin(floatPhase + 2.4) * (h * 0.025)),
      initialRotation: -0.35,
      targetRotation: -0.22,
      w: w,
      h: h,
    );

    final spa = _calcIcon(
      t: t,
      emergeStart: 0.54,
      emergeEnd: 0.66,
      returnStart: 0.83,
      returnEnd: 0.88,
      origin: Offset(w * 0.52, basketRimY + 4),
      target: Offset(w * 0.74, basketRimY - h * 0.17),
      floatOffset: Offset(0, math.sin(floatPhase + 3.6) * (h * 0.025)),
      initialRotation: 0.15,
      targetRotation: 0.0,
      w: w,
      h: h,
    );

    // ==========================================
    // LAYER 1: Basket Back Cavity & Interior Glow
    // ==========================================
    _drawBasketBackAndGlow(
      canvas,
      w,
      h,
      basketRimY,
      basketBottomY,
      glowAlpha,
      lidOpen,
    );

    // ==========================================
    // LAYER 2: Services Icons (Emerging from inside)
    // Clipped so they only appear above the basket rim
    // and vanish cleanly inside without bottom leaks.
    // ==========================================
    canvas.save();
    // Safe boundary: top to rim + inner margin
    canvas.clipRect(Rect.fromLTRB(0, 0, w, basketRimY + h * 0.06));

    final iconSize = (w * 0.32).clamp(16.0, 32.0);

    // Draw Hair
    if (hair.scale > 0.01 && hair.alpha > 0.01) {
      canvas.save();
      canvas.translate(hair.pos.dx, hair.pos.dy);
      canvas.scale(hair.scale);
      canvas.rotate(hair.rotation);
      _drawHairIcon(canvas, iconSize, hair.alpha);
      canvas.restore();
    }

    // Draw Skin
    if (skin.scale > 0.01 && skin.alpha > 0.01) {
      canvas.save();
      canvas.translate(skin.pos.dx, skin.pos.dy);
      canvas.scale(skin.scale);
      canvas.rotate(skin.rotation);
      _drawSkinIcon(canvas, iconSize, skin.alpha);
      canvas.restore();
    }

    // Draw Nails
    if (nails.scale > 0.01 && nails.alpha > 0.01) {
      canvas.save();
      canvas.translate(nails.pos.dx, nails.pos.dy);
      canvas.scale(nails.scale);
      canvas.rotate(nails.rotation);
      _drawNailsIcon(canvas, iconSize, nails.alpha);
      canvas.restore();
    }

    // Draw Spa
    if (spa.scale > 0.01 && spa.alpha > 0.01) {
      canvas.save();
      canvas.translate(spa.pos.dx, spa.pos.dy);
      canvas.scale(spa.scale);
      canvas.rotate(spa.rotation);
      _drawSpaIcon(canvas, iconSize, spa.alpha);
      canvas.restore();
    }

    canvas.restore(); // end icon clipping

    // ==========================================
    // LAYER 3: Basket Front Body & Rim
    // ==========================================
    canvas.save();
    canvas.translate(w * 0.50, basketBottomY);
    canvas.scale(basketScaleX, basketScaleY);
    canvas.translate(-w * 0.50, -basketBottomY);

    _drawBasketFrontBody(canvas, w, h, basketRimY, basketBottomY);

    // ==========================================
    // LAYER 4: Basket Lid & Handle (Articulated)
    // ==========================================
    _drawBasketLidAndHandle(canvas, w, h, basketRimY, lidOpen);

    canvas.restore(); // end basket scale

    // ==========================================
    // LAYER 5: Foreground Sparkles (Combo Reveal)
    // ==========================================
    if (glowAlpha > 0.1) {
      _drawSparkles(canvas, w, h, basketRimY, glowAlpha);
    }
  }

  // --- CALCULATION HELPER ---
  _IconAnimState _calcIcon({
    required double t,
    required double emergeStart,
    required double emergeEnd,
    required double returnStart,
    required double returnEnd,
    required Offset origin,
    required Offset target,
    required Offset floatOffset,
    required double initialRotation,
    required double targetRotation,
    required double w,
    required double h,
  }) {
    if (t < emergeStart || t > returnEnd) {
      return _IconAnimState(
        scale: 0.0,
        pos: origin,
        rotation: initialRotation,
        alpha: 0.0,
      );
    }

    // Emerging (Stage 3..6)
    if (t <= emergeEnd) {
      final p = Curves.easeOutBack.transform(_progress(t, emergeStart, emergeEnd));
      final pos = Offset.lerp(origin, target, p)!;
      final rot = initialRotation + (targetRotation - initialRotation) * p;
      return _IconAnimState(scale: p, pos: pos, rotation: rot, alpha: p.clamp(0.0, 1.0));
    }

    // Floating (Stage 6..7)
    if (t <= returnStart) {
      final floatingPos = target + floatOffset;
      return _IconAnimState(
        scale: 1.0,
        pos: floatingPos,
        rotation: targetRotation,
        alpha: 1.0,
      );
    }

    // Returning into basket (Stage 8)
    final p = Curves.easeInCubic.transform(_progress(t, returnStart, returnEnd));
    final pos = Offset.lerp(target, origin, p)!;
    final scale = (1.0 - p).clamp(0.0, 1.0);
    final rot = targetRotation + (initialRotation - targetRotation) * p;
    return _IconAnimState(
      scale: scale,
      pos: pos,
      rotation: rot,
      alpha: scale,
    );
  }

  // --- DRAWING: BASKET BACK & GLOW ---
  void _drawBasketBackAndGlow(
    Canvas canvas,
    double w,
    double h,
    double basketRimY,
    double basketBottomY,
    double glowAlpha,
    double lidOpen,
  ) {
    // 1. Back cavity dark wall
    final backWall = Path()
      ..moveTo(w * 0.16, basketRimY)
      ..quadraticBezierTo(w * 0.50, basketRimY - h * 0.07, w * 0.84, basketRimY)
      ..lineTo(w * 0.76, basketBottomY - h * 0.04)
      ..lineTo(w * 0.24, basketBottomY - h * 0.04)
      ..close();

    final backWallPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF2E0854), Color(0xFF190028)],
      ).createShader(Rect.fromLTRB(w * 0.16, basketRimY - h * 0.07, w * 0.84, basketBottomY));
    canvas.drawPath(backWall, backWallPaint);

    // 2. Interior Radiant Light Burst (when lid opens)
    if (glowAlpha > 0.02) {
      final glowRect = Rect.fromCircle(
        center: Offset(w * 0.50, basketRimY),
        radius: w * 0.44,
      );
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFEE58).withValues(alpha: 0.90 * glowAlpha), // Warm golden core
            const Color(0xFFFFB74D).withValues(alpha: 0.65 * glowAlpha), // Amber warmth
            const Color(0xFFBA68C8).withValues(alpha: 0.35 * glowAlpha), // Lavender aura
            const Color(0xFF9850F1).withValues(alpha: 0.10 * glowAlpha),
            Colors.transparent,
          ],
          stops: const [0.0, 0.28, 0.55, 0.78, 1.0],
        ).createShader(glowRect);

      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * 0.50, basketRimY - h * 0.06),
          width: w * 0.80,
          height: h * 0.55,
        ),
        glowPaint,
      );

      // Light beams emitting upward
      final beamPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            const Color(0xFFFFF9C4).withValues(alpha: 0.45 * glowAlpha),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTRB(0, basketRimY - h * 0.35, w, basketRimY));

      final beamPath = Path()
        ..moveTo(w * 0.35, basketRimY)
        ..lineTo(w * 0.15, basketRimY - h * 0.35)
        ..lineTo(w * 0.85, basketRimY - h * 0.35)
        ..lineTo(w * 0.65, basketRimY)
        ..close();
      canvas.drawPath(beamPath, beamPaint);
    }
  }

  // --- DRAWING: BASKET FRONT BODY ---
  void _drawBasketFrontBody(
    Canvas canvas,
    double w,
    double h,
    double basketRimY,
    double basketBottomY,
  ) {
    // Trapezoidal body
    final body = Path()
      ..moveTo(w * 0.15, basketRimY)
      ..lineTo(w * 0.85, basketRimY)
      ..lineTo(w * 0.77, basketBottomY)
      ..lineTo(w * 0.23, basketBottomY)
      ..close();

    final bodyRect = Rect.fromLTRB(w * 0.15, basketRimY, w * 0.85, basketBottomY);

    // Glossy purple gradient finish matching storyboard
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF8E24AA), // top left highlight
          Color(0xFF9850F1), // primary brand purple
          Color(0xFF6A1B9A), // mid rich purple
          Color(0xFF4A148C), // deep shadow bottom right
        ],
        stops: [0.0, 0.30, 0.70, 1.0],
      ).createShader(bodyRect);

    canvas.drawPath(body, bodyPaint);

    // Front Body Specular Highlights
    final sheenPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.35),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(w * 0.15, basketRimY, w * 0.70, h * 0.08));
    canvas.drawPath(body, sheenPaint);

    // 4 Vertical Ventilation Slots (storyboard signature)
    final slotWidth = w * 0.045;
    final slotHeight = (basketBottomY - basketRimY) * 0.52;
    final slotTop = basketRimY + (basketBottomY - basketRimY) * 0.22;
    final slotSpacing = w * 0.115;
    final slotStartX = w * 0.50 - (slotSpacing * 1.5);

    final slotFill = Paint()..color = const Color(0xFF240046);
    final slotRim = Paint()
      ..color = const Color(0xFFC77DFF).withValues(alpha: 0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (int i = 0; i < 4; i++) {
      final sx = slotStartX + (i * slotSpacing);
      final slotRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(sx - slotWidth / 2, slotTop, slotWidth, slotHeight),
        Radius.circular(slotWidth / 2),
      );
      canvas.drawRRect(slotRRect, slotFill);
      canvas.drawRRect(slotRRect, slotRim);
    }

    // Side perspective accent lines
    final sideLinePaint = Paint()
      ..color = const Color(0xFFC77DFF).withValues(alpha: 0.30)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(w * 0.22, basketRimY + 2), Offset(w * 0.27, basketBottomY - 2), sideLinePaint);
    canvas.drawLine(Offset(w * 0.78, basketRimY + 2), Offset(w * 0.73, basketBottomY - 2), sideLinePaint);

    // Thick Glossy Front Rim
    final rimRect = Rect.fromLTWH(w * 0.11, basketRimY - h * 0.035, w * 0.78, h * 0.075);
    final rimRRect = RRect.fromRectAndRadius(rimRect, Radius.circular(h * 0.038));

    final rimPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFE1BEE7), // top metallic shine
          Color(0xFFAB47BC), // lavender purple
          Color(0xFF8E24AA), // primary body tone
          Color(0xFF4A148C), // rim underside shadow
        ],
        stops: [0.0, 0.30, 0.70, 1.0],
      ).createShader(rimRect);

    canvas.drawRRect(rimRRect, rimPaint);

    // Specular highlight line along top edge of rim
    final highlightLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.18, basketRimY - h * 0.025),
      Offset(w * 0.82, basketRimY - h * 0.025),
      highlightLinePaint,
    );
  }

  // --- DRAWING: BASKET LID & HANDLE ---
  void _drawBasketLidAndHandle(
    Canvas canvas,
    double w,
    double h,
    double basketRimY,
    double lidOpen,
  ) {
    canvas.save();

    // Hinge Pivot at the rear-left rim
    final hingeX = w * 0.18;
    final hingeY = basketRimY - h * 0.01;

    if (lidOpen > 0.001) {
      canvas.translate(hingeX, hingeY);
      // Opens upward and backward up to ~52 degrees (0.92 rad)
      canvas.rotate(-lidOpen * 0.92);
      canvas.translate(-hingeX, -hingeY);
    }

    // 1. Arched Handle
    final handlePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFE0AAFF), // top bright lilac
          Color(0xFF9850F1), // brand purple
          Color(0xFF5A189A), // base dark
        ],
      ).createShader(Rect.fromLTRB(w * 0.18, basketRimY - h * 0.30, w * 0.82, basketRimY))
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.05).clamp(2.5, 4.2)
      ..strokeCap = StrokeCap.round;

    final handlePath = Path()
      ..moveTo(w * 0.18, basketRimY)
      ..cubicTo(
        w * 0.18,
        basketRimY - h * 0.30,
        w * 0.82,
        basketRimY - h * 0.30,
        w * 0.82,
        basketRimY,
      );
    canvas.drawPath(handlePath, handlePaint);

    // Handle Grip on top
    final gripRect = Rect.fromCenter(
      center: Offset(w * 0.50, basketRimY - h * 0.22),
      width: w * 0.30,
      height: h * 0.045,
    );
    final gripPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFBA68C8), Color(0xFF7B1FA2), Color(0xFF4A148C)],
      ).createShader(gripRect);
    canvas.drawRRect(RRect.fromRectAndRadius(gripRect, const Radius.circular(3)), gripPaint);

    // Handle Hinge brackets
    final hingePaint = Paint()..color = const Color(0xFFE0AAFF);
    canvas.drawCircle(Offset(w * 0.18, basketRimY), 2.8, hingePaint);
    canvas.drawCircle(Offset(w * 0.82, basketRimY), 2.8, hingePaint);

    // 2. Protective Lid Plate
    final lidPlateRect = Rect.fromLTWH(w * 0.14, basketRimY - h * 0.045, w * 0.72, h * 0.06);
    final lidPlatePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFD1C4E9),
          Color(0xFF9850F1),
          Color(0xFF6A1B9A),
        ],
      ).createShader(lidPlateRect);

    canvas.drawRRect(RRect.fromRectAndRadius(lidPlateRect, const Radius.circular(3)), lidPlatePaint);

    // Lid top glossy sheen
    final lidSheenPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(w * 0.18, basketRimY - h * 0.038),
      Offset(w * 0.82, basketRimY - h * 0.038),
      lidSheenPaint,
    );

    canvas.restore(); // end hinge rotation
  }

  // --- DRAWING: SERVICE ICONS ---

  /// 1. Hair Service: Elegant woman silhouette profile with lush glowing purple hair
  void _drawHairIcon(Canvas canvas, double size, double alpha) {
    canvas.save();
    final s = size / 28.0;
    canvas.scale(s);

    // Soft glowing energy wisp behind hair
    final auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFE040FB).withValues(alpha: 0.40 * alpha),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: const Offset(0, 0), radius: 18));
    canvas.drawCircle(const Offset(0, 0), 18, auraPaint);

    // Voluminous cascading purple hair waves
    final hairBasePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFE0AAFF), // lilac highlight
          Color(0xFF9850F1), // primary
          Color(0xFF6A0DAD), // deep purple
          Color(0xFF3C096C), // dark shadow
        ],
      ).createShader(const Rect.fromLTWH(-14, -14, 28, 28))
      ..style = PaintingStyle.fill;

    // Hair outer silhouette path
    final hairPath = Path()
      ..moveTo(2, -12)
      ..cubicTo(10, -12, 13, -4, 11, 4)
      ..cubicTo(9, 10, 4, 14, -3, 14)
      ..cubicTo(-10, 14, -13, 8, -12, 0)
      ..cubicTo(-11, -8, -5, -12, 2, -12)
      ..close();
    canvas.drawPath(hairPath, hairBasePaint);

    // Elegant female face & neck silhouette (in crisp white/ivory)
    final facePath = Path()
      ..moveTo(-1, -8)
      ..lineTo(3, -4) // forehead to nose
      ..lineTo(1, -2) // nose bridge
      ..lineTo(3, 0)  // lips
      ..lineTo(2, 3)  // chin
      ..lineTo(-1, 8) // neck
      ..lineTo(-5, 8)
      ..lineTo(-3, -2)
      ..close();

    final facePaint = Paint()..color = Colors.white.withValues(alpha: 0.95 * alpha);
    canvas.drawPath(facePath, facePaint);

    // Sweeping hair strands framing face
    final waveStroke = Paint()
      ..color = const Color(0xFFE0AAFF).withValues(alpha: 0.85 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final strand = Path()
      ..moveTo(-6, -10)
      ..quadraticBezierTo(0, -6, 2, -2);
    canvas.drawPath(strand, waveStroke);

    final strand2 = Path()
      ..moveTo(-8, -4)
      ..quadraticBezierTo(-4, 4, -2, 12);
    canvas.drawPath(strand2, waveStroke);

    // Hair sparkle
    _drawSparkleStar(canvas, const Offset(6, -6), 2.4, Colors.white, alpha);

    canvas.restore();
  }

  /// 2. Skin Service: Luminous crystal water droplet with fresh green botanical leaves
  void _drawSkinIcon(Canvas canvas, double size, double alpha) {
    canvas.save();
    final s = size / 28.0;
    canvas.scale(s);

    // 1. Teardrop Path
    final dropPath = Path()
      ..moveTo(0, -12)
      ..cubicTo(7, -4, 11, 4, 8, 9)
      ..cubicTo(6, 13, -6, 13, -8, 9)
      ..cubicTo(-11, 4, -7, -4, 0, -12)
      ..close();

    final dropPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF80DEEA), // cyan light
          Color(0xFF42A5F5), // crisp sky blue
          Color(0xFFBA68C8), // iridescent lavender
          Color(0xFF7B1FA2), // deep purple base
        ],
        stops: [0.0, 0.35, 0.70, 1.0],
      ).createShader(const Rect.fromLTWH(-10, -12, 20, 25));

    canvas.drawPath(dropPath, dropPaint);

    // Specular highlight crescent
    final dropHighlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.85 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final highlightPath = Path()
      ..moveTo(-2, -8)
      ..quadraticBezierTo(-7, -2, -6, 4);
    canvas.drawPath(highlightPath, dropHighlight);

    // 2. Two Botanical Fresh Green Leaves at lower right
    final leafPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF81C784), Color(0xFF388E3C)],
      ).createShader(const Rect.fromLTWH(3, 1, 10, 12));

    final mainLeaf = Path()
      ..moveTo(4, 5)
      ..quadraticBezierTo(10, 2, 12, 7)
      ..quadraticBezierTo(10, 12, 5, 10)
      ..close();
    canvas.drawPath(mainLeaf, leafPaint);

    final secondLeaf = Path()
      ..moveTo(6, 9)
      ..quadraticBezierTo(12, 9, 13, 13)
      ..quadraticBezierTo(9, 15, 6, 12)
      ..close();
    canvas.drawPath(secondLeaf, leafPaint);

    // Leaf vein
    final veinPaint = Paint()
      ..color = const Color(0xFFA5D6A7).withValues(alpha: 0.9 * alpha)
      ..strokeWidth = 0.8;
    canvas.drawLine(const Offset(4, 5), const Offset(11, 7), veinPaint);

    // Dewdrop glint
    _drawSparkleStar(canvas, const Offset(-2, -4), 2.2, Colors.white, alpha);

    canvas.restore();
  }

  /// 3. Nails Service: Chic cosmetic nail polish bottle with glossy pink lacquer
  void _drawNailsIcon(Canvas canvas, double size, double alpha) {
    canvas.save();
    final s = size / 28.0;
    canvas.scale(s);

    // Bottle Glass Body (tilted chic aesthetic)
    final bodyRect = Rect.fromCenter(center: const Offset(0, 3.5), width: 13, height: 13);
    final bodyRRect = RRect.fromRectAndRadius(bodyRect, const Radius.circular(2.5));

    // Radiant pink lacquer fill
    final polishPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFF80AB), // luminous pink
          Color(0xFFE91E63), // vibrant magenta
          Color(0xFFC2185B), // deep lacquer
        ],
      ).createShader(bodyRect);
    canvas.drawRRect(bodyRRect, polishPaint);

    // Glass shine reflection
    final glassShine = Paint()
      ..color = Colors.white.withValues(alpha: 0.60 * alpha)
      ..strokeWidth = 1.0;
    canvas.drawLine(const Offset(-3.5, 0), const Offset(-3.5, 7), glassShine);

    // Gold collar
    final collarRect = Rect.fromLTWH(-3.5, -4.5, 7, 2.5);
    final collarPaint = Paint()..color = const Color(0xFFFFD54F);
    canvas.drawRect(collarRect, collarPaint);

    // Sleek black cap wand
    final capRect = Rect.fromLTWH(-2.2, -12, 4.4, 7.5);
    final capPaint = Paint()..color = const Color(0xFF212121);
    canvas.drawRRect(RRect.fromRectAndRadius(capRect, const Radius.circular(1.5)), capPaint);

    // Cap specular stripe
    final capShine = Paint()..color = Colors.white.withValues(alpha: 0.40 * alpha);
    canvas.drawLine(const Offset(-0.8, -11), const Offset(-0.8, -6), capShine);

    // Angled brush tip with pink polish drop
    final brushPaint = Paint()
      ..color = const Color(0xFFFF4081).withValues(alpha: 0.90 * alpha)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(4.5, -10), 1.6, brushPaint);

    canvas.restore();
  }

  /// 4. Spa Service: Stack of smooth polished zen stones with plumeria flower
  void _drawSpaIcon(Canvas canvas, double size, double alpha) {
    canvas.save();
    final s = size / 28.0;
    canvas.scale(s);

    // 1. Stacked 3 River Stones
    // Bottom stone (wide)
    final stone1 = Rect.fromCenter(center: const Offset(-2, 7), width: 17, height: 7.5);
    final stone1Paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF455A64), Color(0xFF212121)],
      ).createShader(stone1);
    canvas.drawOval(stone1, stone1Paint);

    // Middle stone (medium)
    final stone2 = Rect.fromCenter(center: const Offset(-3, 1), width: 13, height: 6.5);
    final stone2Paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF546E7A), Color(0xFF263238)],
      ).createShader(stone2);
    canvas.drawOval(stone2, stone2Paint);

    // Top stone (small)
    final stone3 = Rect.fromCenter(center: const Offset(-3.5, -4.5), width: 9.5, height: 5.5);
    final stone3Paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF607D8B), Color(0xFF37474F)],
      ).createShader(stone3);
    canvas.drawOval(stone3, stone3Paint);

    // Polished specular highlights on top of each stone
    final stoneHighlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.45 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawArc(stone1, math.pi * 1.1, math.pi * 0.8, false, stoneHighlight);
    canvas.drawArc(stone2, math.pi * 1.1, math.pi * 0.8, false, stoneHighlight);
    canvas.drawArc(stone3, math.pi * 1.1, math.pi * 0.8, false, stoneHighlight);

    // 2. Tropical Plumeria / Frangipani Flower nestled at right
    final flowerCenter = const Offset(6.5, 4.5);
    final petalPaint = Paint()..color = Colors.white.withValues(alpha: 0.95 * alpha);

    for (int i = 0; i < 5; i++) {
      final rad = (i * 72.0) * math.pi / 180.0;
      final px = flowerCenter.dx + math.cos(rad) * 4.0;
      final py = flowerCenter.dy + math.sin(rad) * 4.0;
      canvas.drawCircle(Offset(px, py), 2.8, petalPaint);
    }

    // Flower warm yellow/orange center
    final centerPaint = Paint()..color = const Color(0xFFFFC107).withValues(alpha: 0.95 * alpha);
    canvas.drawCircle(flowerCenter, 2.2, centerPaint);

    final innerCenter = Paint()..color = const Color(0xFFFF9800).withValues(alpha: 0.95 * alpha);
    canvas.drawCircle(flowerCenter, 1.2, innerCenter);

    canvas.restore();
  }

  // --- DRAWING: SPARKLES ---
  void _drawSparkles(Canvas canvas, double w, double h, double basketRimY, double alpha) {
    final wave = t * 6.0;

    // 4 sparkles orbiting the composition during reveal
    _drawSparkleStar(
      canvas,
      Offset(w * 0.22, basketRimY - h * 0.44),
      (2.5 + math.sin(wave) * 1.0).clamp(1.5, 3.5),
      const Color(0xFFFFEE58),
      alpha * 0.85,
    );

    _drawSparkleStar(
      canvas,
      Offset(w * 0.50, basketRimY - h * 0.52),
      (3.0 + math.sin(wave + 1.5) * 1.2).clamp(1.5, 4.2),
      Colors.white,
      alpha,
    );

    _drawSparkleStar(
      canvas,
      Offset(w * 0.80, basketRimY - h * 0.42),
      (2.5 + math.sin(wave + 3.0) * 1.0).clamp(1.5, 3.5),
      const Color(0xFFE040FB),
      alpha * 0.80,
    );

    _drawSparkleStar(
      canvas,
      Offset(w * 0.52, basketRimY - h * 0.22),
      (2.2 + math.sin(wave + 4.5) * 0.8).clamp(1.5, 3.0),
      const Color(0xFFFFD54F),
      alpha * 0.70,
    );
  }

  /// 4-point diamond sparkle star
  static void _drawSparkleStar(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double alpha,
  ) {
    if (alpha <= 0.01) return;

    final starPath = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(center.dx, center.dy, center.dx + radius, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy + radius)
      ..quadraticBezierTo(center.dx, center.dy, center.dx - radius, center.dy)
      ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy - radius)
      ..close();

    final fill = Paint()
      ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;
    canvas.drawPath(starPath, fill);
  }

  @override
  bool shouldRepaint(covariant _ComboFullScenePainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

class _IconAnimState {
  final double scale;
  final Offset pos;
  final double rotation;
  final double alpha;

  const _IconAnimState({
    required this.scale,
    required this.pos,
    required this.rotation,
    required this.alpha,
  });
}
