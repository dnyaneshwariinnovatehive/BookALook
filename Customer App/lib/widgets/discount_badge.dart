import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Presentation style of the animated discount badge.
enum DiscountBadgeStyle {
  /// Compact presentation for combo discovery cards in lists.
  /// Uses a soft accent background tint and 10pt typography.
  compact,

  /// Prominent presentation for combo detail hero pricing cards.
  /// Uses a solid accent fill with 13pt white typography.
  prominent,
}

/// A reusable, animated badge that highlights verified discounts with a
/// restrained, premium spring entrance and zero layout shift.
///
/// Animation details:
/// * Total duration: ~400ms.
/// * Scaled spring entrance (0.85 -> 1.0) with [Curves.easeOutBack] and opacity fade.
/// * Layout footprint is strictly reserved up-front to eliminate reflows and jumping.
/// * Only displays if [originalPrice] > [price], both are valid positive values,
///   and the calculated percentage is > 0.
/// * Respects [MediaQuery.disableAnimations] by rendering the completed visual state immediately.
/// * Lifecycle-safe: plays once on initial mount and does not replay on parent
///   `setState()`, rebuilds, or favorite toggles.
class DiscountBadge extends StatefulWidget {
  final num? originalPrice;
  final num? price;
  final int? discountPercent;
  final DiscountBadgeStyle style;
  final EdgeInsetsGeometry? padding;
  final TextStyle? textStyle;
  final Color? backgroundColor;
  final Color? textColor;
  final String? customLabel;

  const DiscountBadge({
    super.key,
    this.originalPrice,
    this.price,
    this.discountPercent,
    this.style = DiscountBadgeStyle.compact,
    this.padding,
    this.textStyle,
    this.backgroundColor,
    this.textColor,
    this.customLabel,
  });

  /// Calculates the rounded integer discount percentage based on valid pricing.
  /// Returns 0 if prices are invalid, equal, negative, or if no positive discount exists.
  static int calculateDiscountPercent(num? originalPrice, num? price) {
    if (originalPrice == null || price == null) return 0;
    final orig = originalPrice.toDouble();
    final curr = price.toDouble();
    if (orig <= 0 || curr < 0 || curr >= orig) return 0;
    final percent = ((orig - curr) / orig * 100).round();
    return percent > 0 ? percent : 0;
  }

  /// Verifies if a legitimate discount exists.
  static bool hasDiscount(num? originalPrice, num? price) {
    return calculateDiscountPercent(originalPrice, price) > 0;
  }

  @override
  State<DiscountBadge> createState() => _DiscountBadgeState();
}

class _DiscountBadgeState extends State<DiscountBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;
  bool _hasStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Subtle spring-like curve from 0.85 to 1.0 with a slight stagger
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutBack),
      ),
    );

    // Smooth opacity fade
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.15, 0.75, curve: Curves.easeOut),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasStarted) return;
    _hasStarted = true;

    final media = MediaQuery.maybeOf(context);
    if (media?.disableAnimations == true) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final percent = widget.discountPercent ??
        DiscountBadge.calculateDiscountPercent(
          widget.originalPrice,
          widget.price,
        );

    // Never render an empty or negative discount
    if (percent <= 0 && widget.customLabel == null) {
      return const SizedBox.shrink();
    }

    final isCompact = widget.style == DiscountBadgeStyle.compact;
    final label = widget.customLabel ?? '$percent% OFF';

    final defaultPadding = isCompact
        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 4);

    final defaultBg = isCompact
        ? AppTheme.accentColor.withValues(alpha: 0.1)
        : AppTheme.accentColor;

    final defaultTextStyle = isCompact
        ? GoogleFonts.outfit(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: widget.textColor ?? AppTheme.accentColor,
          )
        : GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: widget.textColor ?? Colors.white,
          );

    final badgeContent = Container(
      padding: widget.padding ?? defaultPadding,
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? defaultBg,
        borderRadius: BorderRadius.circular(isCompact ? 4 : 6),
      ),
      child: Text(
        label,
        style: widget.textStyle ?? defaultTextStyle,
      ),
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
      child: badgeContent,
    );
  }
}

/// A companion widget that smoothly renders the struck-through original price
/// in synchronization with the discount animation.
class AnimatedOriginalPrice extends StatefulWidget {
  final num? originalPrice;
  final num? price;
  final TextStyle? style;

  const AnimatedOriginalPrice({
    super.key,
    required this.originalPrice,
    required this.price,
    this.style,
  });

  @override
  State<AnimatedOriginalPrice> createState() => _AnimatedOriginalPriceState();
}

class _AnimatedOriginalPriceState extends State<AnimatedOriginalPrice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  bool _hasStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasStarted) return;
    _hasStarted = true;

    final media = MediaQuery.maybeOf(context);
    if (media?.disableAnimations == true) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!DiscountBadge.hasDiscount(widget.originalPrice, widget.price)) {
      return const SizedBox.shrink();
    }

    final orig = widget.originalPrice!.toDouble();

    final defaultStyle = GoogleFonts.outfit(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      decoration: TextDecoration.lineThrough,
    );

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Text(
        '₹${orig.toStringAsFixed(0)}',
        style: widget.style ?? defaultStyle,
      ),
    );
  }
}
