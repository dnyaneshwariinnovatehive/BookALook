import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/category.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';

/// The category picker on the home screen.
///
/// Four fixed, motionless cards: Combo, Hair, Grooming, and View More. The row
/// used to be an endless marquee, but a strip that slides under the finger
/// cannot be aimed at, and a customer hunting for "Hair" should not have to
/// wait for it to come round.
///
/// Combo is not a catalogue category — it is a package a salon builds out of
/// its own services — so it always carries [comboSentinelId] and the directory
/// resolves it to "salons offering a combo". Hair and Grooming are looked up in
/// the categories the API sent.
class CategoryGrid extends StatelessWidget {
  final List<ServiceCategory> categories;
  final void Function(ServiceCategory category) onTap;
  final VoidCallback onViewMore;

  const CategoryGrid({
    super.key,
    required this.categories,
    required this.onTap,
    required this.onViewMore,
  });

  /// `category_id` the directory reads as "salons with a combo package".
  static const String comboSentinelId = 'combo';

  /// A sensible picture when a category has no icon yet.
  static IconData fallbackIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('combo')) return Icons.card_giftcard_rounded;
    if (n.contains('hair')) return Icons.content_cut_rounded;
    if (n.contains('skin') || n.contains('facial')) return Icons.face_retouching_natural;
    if (n.contains('nail')) return Icons.back_hand_outlined;
    if (n.contains('spa') || n.contains('massage')) return Icons.spa_rounded;
    if (n.contains('groom') || n.contains('beard') || n.contains('shave')) {
      return Icons.face_rounded;
    }
    if (n.contains('makeup') || n.contains('bridal')) return Icons.brush_rounded;
    if (n.contains('wax') || n.contains('thread')) return Icons.auto_fix_high_rounded;
    return Icons.category_rounded;
  }

  /// Soft backgrounds behind the icons.
  static const List<(Color, Color)> _tints = [
    (Color(0xFFF3EBFE), Color(0xFF9C54F2)), // lavender
    (Color(0xFFFFF1E6), Color(0xFFEF6C00)), // peach
    (Color(0xFFE6F6EF), Color(0xFF2E7D32)), // mint
    (Color(0xFFFDE8EF), Color(0xFFD81B60)), // rose
  ];

  /// How many tiles fit across the screen at once.
  static const int _visibleTiles = 4;
  static const double _gap = 12;

  /// The catalogue row behind one of the fixed cards.
  ///
  /// Matched on the exact name first and only then on a substring, so a
  /// SuperAdmin renaming "Hair" to "Hair Services" keeps the card working while
  /// a "Braids & Hair Colour" row cannot hijack it.
  ServiceCategory? _match(List<String> needles) {
    for (final needle in needles) {
      for (final category in categories) {
        if (category.name.toLowerCase() == needle) return category;
      }
    }
    for (final needle in needles) {
      for (final category in categories) {
        if (category.name.toLowerCase().contains(needle)) return category;
      }
    }
    return null;
  }

  /// The three filterable cards, in the order they are shown.
  List<_FeaturedSlot> _featured() => [
        _FeaturedSlot(
          label: 'Combo',
          category: ServiceCategory(id: comboSentinelId, name: 'Combo'),
        ),
        _FeaturedSlot(label: 'Hair', category: _match(const ['hair'])),
        _FeaturedSlot(
          label: 'Grooming',
          category: _match(const ['groom', 'beard', 'shave']),
        ),
      ];

  void _handleFeaturedTap(_FeaturedSlot slot) {
    final category = slot.category;

    // No catalogue row behind this card, so there is nothing to filter the
    // directory by. The full category list is the honest place to send them.
    if (category == null) {
      onViewMore();
      return;
    }

    onTap(category);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        if (viewportWidth <= 0) return const SizedBox.shrink();

        // Tiles are square, so the label under them just hangs off the bottom
        // of the icon box.
        final tileWidth =
            (viewportWidth - _gap * (_visibleTiles - 1)) / _visibleTiles;
        final tileHeight = tileWidth + 7 + 32;

        final featured = _featured();

        return SizedBox(
          height: tileHeight,
          child: Row(
            children: [
              for (var i = 0; i < featured.length; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                // The square icon box needs a known width to size itself from,
                // so each card is pinned rather than left to the Row.
                SizedBox(
                  width: tileWidth,
                  child: _CategoryTile(
                    // The label is fixed so the three cards always read
                    // "Combo, Hair, Grooming". The catalogue row behind the
                    // card only supplies the id to filter on and the artwork —
                    // a row renamed to "Hair Services" must not rename the card
                    // out from under the customer.
                    label: featured[i].label,
                    iconUrl: featured[i].category?.iconUrl,
                    tint: _tints[i % _tints.length],
                    isDark: isDark,
                    onTap: () => _handleFeaturedTap(featured[i]),
                  ),
                ),
              ],
              const SizedBox(width: _gap),
              SizedBox(
                width: tileWidth,
                child: _ViewMoreTile(
                  isDark: isDark,
                  onTap: onViewMore,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One of the three fixed category cards.
class _FeaturedSlot {
  final String label;
  final ServiceCategory? category;

  const _FeaturedSlot({required this.label, required this.category});
}

class _CategoryTile extends StatelessWidget {
  final String label;
  final String? iconUrl;
  final (Color, Color) tint;
  final bool isDark;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.label,
    required this.iconUrl,
    required this.tint,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = tint;
    final hasIcon = iconUrl != null && iconUrl!.isNotEmpty;
    final isCombo = label.toLowerCase().contains('combo');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: isDark ? foreground.withValues(alpha: 0.16) : background,
                borderRadius: BorderRadius.circular(18),
              ),
              child: isCombo
                  ? _AnimatedCombosIllustration(
                      primaryColor: foreground,
                      backgroundColor: isDark ? foreground.withValues(alpha: 0.16) : background,
                    )
                  : (hasIcon
                      ? Image.network(
                          iconUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) => Icon(
                            CategoryGrid.fallbackIcon(label),
                            color: foreground,
                            size: 26,
                          ),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Icon(
                              CategoryGrid.fallbackIcon(label),
                              color: foreground.withValues(alpha: 0.35),
                              size: 26,
                            );
                          },
                        )
                      : Icon(
                          CategoryGrid.fallbackIcon(label),
                          color: foreground,
                          size: 26,
                        )),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedCombosIllustration extends StatefulWidget {
  final Color primaryColor;
  final Color backgroundColor;

  const _AnimatedCombosIllustration({
    required this.primaryColor,
    required this.backgroundColor,
  });

  @override
  State<_AnimatedCombosIllustration> createState() => _AnimatedCombosIllustrationState();
}

class _AnimatedCombosIllustrationState extends State<_AnimatedCombosIllustration> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _basketScaleYAnim;
  late Animation<double> _basketScaleXAnim;
  late Animation<double> _productsPopAnim;

  @override
  void initState() {
    super.initState();
    // Approximately 3.5 seconds per cycle for a premium rhythm
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );

    // Basket tiny reaction
    _basketScaleYAnim = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.95).chain(CurveTween(curve: Curves.easeOut)), weight: 5),
      TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.02).chain(CurveTween(curve: Curves.easeOut)), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 1.02, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
    ]).animate(_controller);

    _basketScaleXAnim = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.05).chain(CurveTween(curve: Curves.easeOut)), weight: 5),
      TweenSequenceItem(tween: Tween(begin: 1.05, end: 0.98).chain(CurveTween(curve: Curves.easeOut)), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 0.98, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
    ]).animate(_controller);

    // Pop animation: 0 -> 1 -> 0
    _productsPopAnim = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 25), // pop up
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.9).chain(CurveTween(curve: Curves.easeInOutSine)), weight: 15), // float
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 0.0).chain(CurveTween(curve: Curves.easeInOutQuad)), weight: 30), // return
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 15),
    ]).animate(_controller);

    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // 1. Basket Back Rim
            Positioned.fill(
              child: Transform.scale(
                scaleX: _basketScaleXAnim.value,
                scaleY: _basketScaleYAnim.value,
                alignment: const Alignment(0.0, 0.6),
                child: CustomPaint(
                  painter: _BasketBackPainter(
                    primaryColor: widget.primaryColor,
                    backgroundColor: widget.backgroundColor,
                  ),
                ),
              ),
            ),
            
            // 2. Beauty Products (Popping out)
            Positioned.fill(
              child: CustomPaint(
                painter: _BeautyProductsPainter(
                  progress: _productsPopAnim.value,
                  primaryColor: widget.primaryColor,
                  backgroundColor: widget.backgroundColor,
                ),
              ),
            ),
            
            // 3. Basket Front Body & Bow
            Positioned.fill(
              child: Transform.scale(
                scaleX: _basketScaleXAnim.value,
                scaleY: _basketScaleYAnim.value,
                alignment: const Alignment(0.0, 0.6),
                child: CustomPaint(
                  painter: _BasketFrontPainter(
                    primaryColor: widget.primaryColor,
                    backgroundColor: widget.backgroundColor,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BasketBackPainter extends CustomPainter {
  final Color primaryColor;
  final Color backgroundColor;
  
  _BasketBackPainter({required this.primaryColor, required this.backgroundColor});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    
    final basketY = h * 0.62;

    final backRim = Path();
    backRim.moveTo(w * 0.2, basketY);
    backRim.quadraticBezierTo(w * 0.5, basketY - h * 0.08, w * 0.8, basketY);
    
    final innerFill = Paint()..color = backgroundColor..style = PaintingStyle.fill;
    final inside = Path();
    inside.moveTo(w * 0.2, basketY);
    inside.quadraticBezierTo(w * 0.5, basketY - h * 0.08, w * 0.8, basketY);
    inside.lineTo(w * 0.8, basketY + h * 0.1);
    inside.lineTo(w * 0.2, basketY + h * 0.1);
    inside.close();
    
    canvas.drawPath(inside, innerFill);
    canvas.drawPath(backRim, stroke);
  }

  @override
  bool shouldRepaint(covariant _BasketBackPainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor || 
           oldDelegate.backgroundColor != backgroundColor;
  }
}

class _BeautyProductsPainter extends CustomPainter {
  final double progress; // 0 -> 1 -> 0
  final Color primaryColor;
  final Color backgroundColor;

  static final _pumpHead = Path()
    ..moveTo(-5, -14)
    ..lineTo(5, -14)
    ..lineTo(5, -17)
    ..lineTo(-7, -17)
    ..lineTo(-7, -15)
    ..lineTo(-5, -15)
    ..close();

  static final _brushHandle = Path()
    ..moveTo(-2, 0)
    ..lineTo(2, 0)
    ..lineTo(1.5, 20)
    ..lineTo(-1.5, 20)
    ..close();

  static final _brushBristles = Path()
    ..moveTo(-3, 0)
    ..lineTo(3, 0)
    ..quadraticBezierTo(5, -12, 0, -18)
    ..quadraticBezierTo(-5, -12, -3, 0)
    ..close();

  static final _leaf1 = Path()
    ..moveTo(0, 10)
    ..quadraticBezierTo(-8, 5, -10, -2)
    ..quadraticBezierTo(-2, -8, 2, 0)
    ..close();

  static final _leaf2 = Path()
    ..moveTo(0, 10)
    ..quadraticBezierTo(8, 0, 12, -8)
    ..quadraticBezierTo(4, -10, 2, -2)
    ..close();

  _BeautyProductsPainter({
    required this.progress,
    required this.primaryColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    
    final basketY = h * 0.62;

    // HARD VISUAL BOUNDARY: Create a safe zone so products cannot possibly peek
    // out from the bottom or the sloped sides of the basket body.
    // The front basket painter covers from basketY down to basketBottomY.
    // By clipping just below the rim (basketY + h * 0.08), the cut-off is entirely
    // hidden behind the opaque front basket, but guarantees no element drops below it.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, w, basketY + h * 0.08));

    // BRUSH: launches diagonally left/up, subtle rotation, reaches a moderate peak, gently returns
    canvas.save();
    final brushX = w * 0.45 - (progress * w * 0.12);
    // Adjusted origin to start higher, remaining within the safe zone
    final brushY = basketY + (h * 0.03) - (progress * h * 0.35); 
    canvas.translate(brushX, brushY);
    canvas.rotate(-0.35 * progress);
    _drawBrush(canvas, primaryColor, backgroundColor);
    canvas.restore();

    // PUMP BOTTLE: launches upward/right, slightly slower, subtle rotation
    canvas.save();
    final bottleProgress = math.pow(progress, 0.85).toDouble(); 
    final bottleX = w * 0.55 + (bottleProgress * w * 0.12);
    // Adjusted origin
    final bottleY = basketY + (h * 0.03) - (bottleProgress * h * 0.3);
    canvas.translate(bottleX, bottleY);
    canvas.rotate(0.2 * bottleProgress);
    _drawPumpBottle(canvas, primaryColor, backgroundColor);
    canvas.restore();

    // CREAM CONTAINER: shorter vertical pop, small soft bounce
    canvas.save();
    final creamProgress = math.pow(progress, 1.2).toDouble();
    final creamX = w * 0.48;
    // Adjusted origin
    final creamY = basketY + (h * 0.02) - (creamProgress * h * 0.22);
    canvas.translate(creamX, creamY);
    _drawCreamJar(canvas, primaryColor, backgroundColor);
    canvas.restore();

    // LEAVES LEFT: fan outward, gentle rotation
    canvas.save();
    final leafProgress = math.pow(progress, 0.9).toDouble();
    final leafX = w * 0.35 - (leafProgress * w * 0.15);
    // Adjusted origin
    final leafY = basketY + (h * 0.03) - (leafProgress * h * 0.22);
    canvas.translate(leafX, leafY);
    canvas.rotate(-0.5 * leafProgress);
    _drawLeaves(canvas, primaryColor, backgroundColor);
    canvas.restore();
    
    // LEAVES RIGHT: extra visual balance
    canvas.save();
    final rightLeafProgress = math.pow(progress, 1.1).toDouble();
    final rLeafX = w * 0.65 + (rightLeafProgress * w * 0.15);
    // Adjusted origin
    final rLeafY = basketY + (h * 0.03) - (rightLeafProgress * h * 0.18);
    canvas.translate(rLeafX, rLeafY);
    canvas.rotate(0.6 + (0.4 * rightLeafProgress));
    _drawLeaves(canvas, primaryColor, backgroundColor);
    canvas.restore();

    // Small sparkles as secondary accents
    if (progress > 0.2) {
       final sparkleAlpha = ((progress - 0.2) / 0.8).clamp(0.0, 1.0);
       _drawSparkle(canvas, Offset(w * 0.28, basketY - h * 0.25), primaryColor, sparkleAlpha, progress);
       _drawSparkle(canvas, Offset(w * 0.72, basketY - h * 0.3), primaryColor, sparkleAlpha * 0.8, progress * 1.2);
       _drawSparkle(canvas, Offset(w * 0.52, basketY - h * 0.4), primaryColor, sparkleAlpha * 0.6, progress * 0.9);
    }
    
    // Restore the canvas state that was saved before applying the bounding clip
    canvas.restore();
  }

  void _drawPumpBottle(Canvas canvas, Color primary, Color bg) {
    final fill = Paint()..color = bg..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final thinStroke = Paint()
      ..color = primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final body = Rect.fromLTWH(-8, -10, 16, 20);
    canvas.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(3)), fill);
    canvas.drawRRect(RRect.fromRectAndRadius(body, const Radius.circular(3)), stroke);
    
    canvas.drawRect(const Rect.fromLTWH(-3, -14, 6, 4), fill);
    canvas.drawRect(const Rect.fromLTWH(-3, -14, 6, 4), stroke);
    
    canvas.drawPath(_pumpHead, fill);
    canvas.drawPath(_pumpHead, stroke);
    
    canvas.drawLine(const Offset(-4, -2), const Offset(4, -2), thinStroke);
    canvas.drawLine(const Offset(-4, 2), const Offset(4, 2), thinStroke);
  }

  void _drawBrush(Canvas canvas, Color primary, Color bg) {
    final fill = Paint()..color = bg..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final thinStroke = Paint()
      ..color = primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawPath(_brushHandle, fill);
    canvas.drawPath(_brushHandle, stroke);

    canvas.drawPath(_brushBristles, fill);
    canvas.drawPath(_brushBristles, stroke);
    
    canvas.drawLine(const Offset(-2.5, -4), const Offset(2.5, -4), thinStroke);
  }

  void _drawCreamJar(Canvas canvas, Color primary, Color bg) {
    final fill = Paint()..color = bg..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final base = Rect.fromLTWH(-10, 0, 20, 12);
    canvas.drawRRect(RRect.fromRectAndRadius(base, const Radius.circular(3)), fill);
    canvas.drawRRect(RRect.fromRectAndRadius(base, const Radius.circular(3)), stroke);
    
    final lid = Rect.fromLTWH(-11, -5, 22, 5);
    canvas.drawRRect(RRect.fromRectAndRadius(lid, const Radius.circular(2)), fill);
    canvas.drawRRect(RRect.fromRectAndRadius(lid, const Radius.circular(2)), stroke);
    
    canvas.drawCircle(const Offset(0, 6), 1.5, Paint()..color = primary..style = PaintingStyle.fill);
  }

  void _drawLeaves(Canvas canvas, Color primary, Color bg) {
    final fill = Paint()..color = bg..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(_leaf1, fill);
    canvas.drawPath(_leaf1, stroke);
    
    canvas.drawPath(_leaf2, fill);
    canvas.drawPath(_leaf2, stroke);
    
    canvas.drawLine(const Offset(0, 10), const Offset(2, -8), stroke);
  }

  void _drawSparkle(Canvas canvas, Offset center, Color primary, double alpha, double t) {
    final flash = math.sin(t * math.pi * 3).clamp(0.0, 1.0) * alpha;
    if (flash <= 0.0) return;
    
    final size = 2.0 + (flash * 3.0);
    final stroke = Paint()
      ..color = primary.withValues(alpha: flash)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
      
    canvas.drawLine(center + Offset(0, -size), center + Offset(0, size), stroke);
    canvas.drawLine(center + Offset(-size, 0), center + Offset(size, 0), stroke);
  }

  @override
  bool shouldRepaint(covariant _BeautyProductsPainter oldDelegate) {
    return oldDelegate.progress != progress ||
           oldDelegate.primaryColor != primaryColor ||
           oldDelegate.backgroundColor != backgroundColor;
  }
}

class _BasketFrontPainter extends CustomPainter {
  final Color primaryColor;
  final Color backgroundColor;
  
  _BasketFrontPainter({required this.primaryColor, required this.backgroundColor});

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = backgroundColor..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    final basketY = h * 0.62;
    final basketBottomY = h * 0.88;

    final body = Path();
    body.moveTo(w * 0.2, basketY); 
    body.lineTo(w * 0.8, basketY); 
    body.lineTo(w * 0.7, basketBottomY); 
    body.lineTo(w * 0.3, basketBottomY); 
    body.close();
    
    final rim = Rect.fromLTWH(w * 0.15, basketY - h * 0.03, w * 0.7, h * 0.08);
    final rimRRect = RRect.fromRectAndRadius(rim, const Radius.circular(4));

    canvas.drawPath(body, fill);
    canvas.drawRRect(rimRRect, fill);

    canvas.drawPath(body, stroke);
    canvas.drawRRect(rimRRect, stroke);

    final linePaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
      
    for (int i = 1; i <= 2; i++) {
      double y = basketY + ((basketBottomY - basketY) * (i / 3));
      double inset = (w * 0.1) * (i / 3);
      canvas.drawLine(Offset(w * 0.2 + inset, y), Offset(w * 0.8 - inset, y), linePaint);
    }
    for (int i = 1; i <= 3; i++) {
      double topX = w * 0.2 + (w * 0.6 * (i / 4));
      double bottomX = w * 0.3 + (w * 0.4 * (i / 4));
      canvas.drawLine(Offset(topX, basketY + h * 0.05), Offset(bottomX, basketBottomY), linePaint);
    }

    final bowFill = Paint()..color = primaryColor..style = PaintingStyle.fill;
    final bowY = basketY + h * 0.12;
    
    canvas.drawLine(Offset(w * 0.22, bowY), Offset(w * 0.78, bowY), stroke);
    
    final bowCenter = Offset(w * 0.5, bowY);
    
    final leftLoop = Path();
    leftLoop.moveTo(bowCenter.dx, bowCenter.dy);
    leftLoop.quadraticBezierTo(w * 0.35, bowY - h * 0.07, w * 0.4, bowY);
    leftLoop.quadraticBezierTo(w * 0.35, bowY + h * 0.07, bowCenter.dx, bowCenter.dy);
    canvas.drawPath(leftLoop, bowFill);
    
    final rightLoop = Path();
    rightLoop.moveTo(bowCenter.dx, bowCenter.dy);
    rightLoop.quadraticBezierTo(w * 0.65, bowY - h * 0.07, w * 0.6, bowY);
    rightLoop.quadraticBezierTo(w * 0.65, bowY + h * 0.07, bowCenter.dx, bowCenter.dy);
    canvas.drawPath(rightLoop, bowFill);
    
    canvas.drawCircle(bowCenter, 3, fill);
    canvas.drawCircle(bowCenter, 3, stroke);
  }

  @override
  bool shouldRepaint(covariant _BasketFrontPainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor ||
           oldDelegate.backgroundColor != backgroundColor;
  }
}

/// The fourth card: every category the platform has, on its own page.
class _ViewMoreTile extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;

  const _ViewMoreTile({required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? accent.withValues(alpha: 0.16) : context.colors.accentSoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.grid_view_rounded, color: accent, size: 26),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'View More',
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
