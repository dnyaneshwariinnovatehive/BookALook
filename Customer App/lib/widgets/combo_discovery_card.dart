import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/salon_detail_screen.dart';
import '../screens/combo_detail_screen.dart';
import '../services/cart_service.dart';
import '../services/auth_service.dart';
import '../screens/phone_screen.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../utils/app_haptics.dart';
import '../utils/error_text.dart';

class ComboDiscoveryCard extends StatefulWidget {
  final Map<String, dynamic> salon;
  final bool isFavourited;
  final bool showFavourite;
  final VoidCallback onToggleFavourite;

  const ComboDiscoveryCard({
    super.key,
    required this.salon,
    this.isFavourited = false,
    this.showFavourite = false,
    required this.onToggleFavourite,
  });

  @override
  State<ComboDiscoveryCard> createState() => _ComboDiscoveryCardState();
}

class _ComboDiscoveryCardState extends State<ComboDiscoveryCard> {
  static const double _favouriteSlop = 11;
  final CartService _cartService = CartService();
  bool _expanded = false;
  final Set<String> _adding = {};

  Future<void> _addCombo(Map<String, dynamic> combo) async {
    final comboId = combo['id'].toString();
    if (_adding.contains(comboId)) return;

    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const PhoneScreen(isModal: true)),
      );
      if (loggedIn != true || !mounted) return;
    }

    setState(() => _adding.add(comboId));
    final salonId = widget.salon['id'].toString();

    try {
      await _cartService.addCombo(salonId, comboId);
      if (!mounted) return;
      AppHaptics.lightImpact();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${combo['name'] ?? 'Combo'} added to cart')));
    } on CartConflictException catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      _confirmReplace(e, combo);
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(describeError(e, fallback: 'Could not add to cart.'))));
    } finally {
      if (mounted) setState(() => _adding.remove(comboId));
    }
  }

  void _confirmReplace(CartConflictException e, Map<String, dynamic> combo) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Replace cart items?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'Your cart contains items from ${e.otherSalonName}. '
          'Do you want to discard that selection and add items from this salon?',
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              AppHaptics.lightImpact();
              Navigator.pop(ctx);
            },
            child: Text('Cancel', style: GoogleFonts.outfit(color: context.colors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              AppHaptics.lightImpact();
              Navigator.pop(ctx);
              try {
                await _cartService.clearGlobalCart();
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not clear cart.')));
                return;
              }
              if (!mounted) return;
              await _addCombo(combo);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentColor),
            child: Text('Replace', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = context.colors.surface;
    final borderColor = context.colors.listBorder;
    final headingColor = context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;
    final isServiceable = widget.salon['is_serviceable'] != false;
    final count = (widget.salon['review_count'] as num?)?.toInt() ?? 0;
    final avg = (widget.salon['avg_rating'] as num?)?.toDouble() ?? 0;
    final distance = widget.salon['distance_km'];
    final id = widget.salon['id'].toString();

    final combos = (widget.salon['combos'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SalonDetailScreen(
              salonId: id,
              categoryId: 'combo',
              categoryName: 'Combos',
            ),
          ),
        );
      },
      child: Opacity(
        opacity: isServiceable ? 1.0 : 0.65,
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 125,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            widget.salon['cover_photo_url'] ?? '',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: context.colors.imagePlaceholder,
                              child: const Icon(Icons.storefront, color: AppTheme.accentColor, size: 32),
                            ),
                          ),
                          if (widget.showFavourite)
                            Positioned(
                              top: 6 - _favouriteSlop,
                              right: 6 - _favouriteSlop,
                              child: Semantics(
                                button: true,
                                label: widget.isFavourited ? 'Remove from favourites' : 'Add to favourites',
                                excludeSemantics: true,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: widget.onToggleFavourite,
                                  child: Padding(
                                    padding: const EdgeInsets.all(_favouriteSlop),
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: context.colors.surface.withValues(alpha: 0.85),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        widget.isFavourited ? Icons.favorite : Icons.favorite_border,
                                        size: 16,
                                        color: widget.isFavourited ? context.colors.danger : context.colors.iconIdle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.salon['name'] ?? 'Unnamed Salon',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: headingColor),
                                  ),
                                ),
                                if (count > 0) ...[
                                  const Icon(Icons.star, size: 15, color: AppTheme.starRating),
                                  const SizedBox(width: 3),
                                  Text(
                                    avg.toStringAsFixed(1),
                                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: headingColor),
                                  ),
                                ] else
                                  Text('New', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: bodyColor)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.location_on_outlined, size: 15, color: AppTheme.accentColor),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    widget.salon['address'] ?? 'No address',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(fontSize: 13, color: bodyColor),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (!isServiceable)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: context.colors.warningBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  widget.salon['unavailable_reason'] ?? 'Not taking bookings',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: context.colors.warning),
                                ),
                              )
                            else
                              Row(
                                children: [
                                  const Icon(Icons.check_circle, size: 13, color: AppTheme.statusAvailable),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Bookable online',
                                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: bodyColor),
                                    ),
                                  ),
                                  if (distance != null)
                                    Text(
                                      '${widget.salon['distance_is_approximate'] == true ? '~' : ''}$distance km',
                                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accentColor),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (combos.isNotEmpty)
                _buildComboList(combos, isServiceable),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComboList(List<Map<String, dynamic>> combos, bool isServiceable) {
    final visibleCount = _expanded ? combos.length : (combos.length > 2 ? 2 : combos.length);
    final visibleCombos = combos.take(visibleCount).toList();

    return Container(
      color: context.colors.surfaceMuted.withValues(alpha: 0.3),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < visibleCombos.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _buildComboItem(visibleCombos[i], isServiceable),
                ],
              ],
            ),
          ),
          if (combos.length > 2) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                setState(() => _expanded = !_expanded);
                AppHaptics.lightImpact();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _expanded ? 'Show less' : '+ ${combos.length - 2} more combos',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accentColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 16,
                      color: AppTheme.accentColor,
                    ),
                  ],
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildComboItem(Map<String, dynamic> combo, bool isServiceable) {
    final isAdding = _adding.contains(combo['id'].toString());
    final services = (combo['services'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().toList();
    final serviceNames = services.map((s) => s['name'] as String?).whereType<String>().join(' + ');

    final price = (combo['price'] as num?)?.toDouble() ?? 0;
    final originalPrice = (combo['original_price'] as num?)?.toDouble() ?? 0;

    int discountPercent = 0;
    if (originalPrice > 0 && price < originalPrice) {
      discountPercent = ((originalPrice - price) / originalPrice * 100).round();
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ComboDetailScreen(
              salon: widget.salon,
              combo: combo,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.listBorder),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  combo['name'] ?? 'Combo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: context.colors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  serviceNames.isEmpty ? 'Multiple services' : serviceNames,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(fontSize: 12, color: context.colors.textSecondary),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '₹${price.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.accentColor),
                    ),
                    if (originalPrice > price) ...[
                      const SizedBox(width: 6),
                      Text(
                        '₹${originalPrice.toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textSecondary,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                    if (discountPercent > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$discountPercent% OFF',
                          style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentColor),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: isServiceable && !isAdding ? () => _addCombo(combo) : null,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isServiceable ? AppTheme.accentColor : context.colors.iconIdle,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: isAdding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    ));
  }
}
