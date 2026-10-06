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
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _pulseAnim = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.05).chain(CurveTween(curve: Curves.easeOut)), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.05, end: 0.96).chain(CurveTween(curve: Curves.easeInOut)), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 0.96, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 30),
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
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _BurstPainter(
                  progress: _controller.value,
                  primaryColor: widget.primaryColor,
                ),
              ),
            ),
            Transform.scale(
              scale: _pulseAnim.value,
              child: Padding(
                padding: const EdgeInsets.all(6.0),
                child: Image.asset(
                  'assets/images/combo_icon.jpg', // Uses the provided image
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BurstPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;

  _BurstPainter({required this.progress, required this.primaryColor});

  void _drawStar(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    path.moveTo(center.dx, center.dy - size);
    path.quadraticBezierTo(center.dx, center.dy, center.dx + size, center.dy);
    path.quadraticBezierTo(center.dx, center.dy, center.dx, center.dy + size);
    path.quadraticBezierTo(center.dx, center.dy, center.dx - size, center.dy);
    path.quadraticBezierTo(center.dx, center.dy, center.dx, center.dy - size);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 7; i++) {
      final angle = (i * math.pi * 2 / 7) + (progress * math.pi * 0.5);
      final localProgress = (progress + (i * 0.14)) % 1.0;
      final distance = 10 + (size.width * 0.7 * localProgress);
      final alpha = (1.0 - localProgress).clamp(0.0, 1.0);
      final particleSize = 6.0 * math.sin(localProgress * math.pi);
      
      if (particleSize > 0.5) {
        paint.color = primaryColor.withValues(alpha: alpha);
        final dx = center.dx + math.cos(angle) * distance;
        final dy = center.dy + math.sin(angle) * distance;
        
        // Alternate between circles and stars
        if (i % 2 == 0) {
          _drawStar(canvas, Offset(dx, dy), particleSize, paint);
        } else {
          canvas.drawCircle(Offset(dx, dy), particleSize * 0.5, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.primaryColor != primaryColor;
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
