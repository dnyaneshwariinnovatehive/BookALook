import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/cart_service.dart';
import '../services/auth_service.dart';
import '../screens/phone_screen.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../utils/app_haptics.dart';
import '../utils/error_text.dart';
import '../utils/bottom_clearance.dart';

class ComboDetailScreen extends StatefulWidget {
  final Map<String, dynamic> salon;
  final Map<String, dynamic> combo;

  const ComboDetailScreen({
    super.key,
    required this.salon,
    required this.combo,
  });

  @override
  State<ComboDetailScreen> createState() => _ComboDetailScreenState();
}

class _ComboDetailScreenState extends State<ComboDetailScreen> {
  final CartService _cartService = CartService();
  bool _isAdding = false;

  Future<void> _addCombo() async {
    if (_isAdding) return;

    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const PhoneScreen(isModal: true)),
      );
      if (loggedIn != true || !mounted) return;
    }

    setState(() => _isAdding = true);
    final salonId = widget.salon['id'].toString();
    final comboId = widget.combo['id'].toString();

    try {
      await _cartService.addCombo(salonId, comboId);
      if (!mounted) return;
      AppHaptics.lightImpact();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('${widget.combo['name'] ?? 'Combo'} added to cart'),
          backgroundColor: context.colors.success,
        ));
    } on CartConflictException catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      _confirmReplace(e);
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(describeError(e, fallback: 'Could not add to cart.'))));
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  void _confirmReplace(CartConflictException e) {
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
              await _addCombo();
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
    final bool isServiceable = widget.salon['is_serviceable'] != false;
    
    return Scaffold(
      backgroundColor: context.colors.surfaceMuted,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _buildAppBar(),
              SliverToBoxAdapter(child: _buildComboIdentity()),
              SliverToBoxAdapter(child: _buildSalonInfo()),
              SliverToBoxAdapter(child: _buildPricingCard()),
              SliverToBoxAdapter(child: _buildIncludedServices()),
              SliverToBoxAdapter(child: SizedBox(height: 120)), // Bottom clearance
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomBar(isServiceable),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    final photoUrl = widget.salon['cover_photo_url'] ?? '';

    return SliverAppBar(
      expandedHeight: 250,
      pinned: true,
      backgroundColor: context.colors.surface,
      foregroundColor: context.colors.textPrimary,
      elevation: 0,
      title: Text('Combo Details',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
      leading: Padding(
        padding: const EdgeInsets.only(left: 12.0, top: 6.0, bottom: 6.0),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            tooltip: 'Back',
            icon: Icon(Icons.arrow_back, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (photoUrl.isEmpty)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.accentGradientLightEnd, AppTheme.accentGradientEnd],
                  ),
                ),
                child: Center(child: Icon(Icons.storefront, size: 90, color: Colors.white.withValues(alpha: 0.45))),
              )
            else
              Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: context.colors.imagePlaceholder,
                  child: const Icon(Icons.storefront, color: AppTheme.accentColor, size: 32),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComboIdentity() {
    final name = widget.combo['name'] ?? 'Combo';
    final salonName = widget.salon['name'] ?? 'Unnamed Salon';
    final count = (widget.salon['review_count'] as num?)?.toInt() ?? 0;
    final avg = (widget.salon['avg_rating'] as num?)?.toDouble() ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.listBorder),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: GoogleFonts.outfit(
                fontSize: 24, fontWeight: FontWeight.bold, color: context.colors.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'at $salonName',
            style: GoogleFonts.outfit(
                fontSize: 15, fontWeight: FontWeight.w500, color: context.colors.textSecondary),
          ),
          const SizedBox(height: 12),
          if (count > 0)
            Row(
              children: [
                const Icon(Icons.star_rounded, color: AppTheme.starRating, size: 20),
                const SizedBox(width: 6),
                Text(
                  avg.toStringAsFixed(1),
                  style: GoogleFonts.outfit(
                      fontSize: 15, fontWeight: FontWeight.bold, color: context.colors.textPrimary),
                ),
                const SizedBox(width: 6),
                Text(
                  '($count reviews)',
                  style: GoogleFonts.outfit(
                      fontSize: 14, color: context.colors.textSecondary),
                ),
              ],
            )
          else
            Row(
              children: [
                const Icon(Icons.star_border_rounded, color: AppTheme.starRating, size: 20),
                const SizedBox(width: 6),
                Text(
                  'New',
                  style: GoogleFonts.outfit(
                      fontSize: 15, fontWeight: FontWeight.w600, color: context.colors.textSecondary),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSalonInfo() {
    final address = widget.salon['address'] ?? '';
    final distance = widget.salon['distance_km'];
    final bool isServiceable = widget.salon['is_serviceable'] != false;
    final String unavailableReason = widget.salon['unavailable_reason'] ?? 'Not taking bookings';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (address.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_on_outlined, size: 18, color: context.colors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    distance != null ? '$address · ${widget.salon['distance_is_approximate'] == true ? '~' : ''}$distance km' : address,
                    style: GoogleFonts.outfit(fontSize: 14, color: context.colors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (!isServiceable)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: context.colors.warningBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, size: 14, color: context.colors.warning),
                  const SizedBox(width: 6),
                  Text(
                    unavailableReason,
                    style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.warning),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                const Icon(Icons.check_circle, size: 16, color: AppTheme.statusAvailable),
                const SizedBox(width: 6),
                Text(
                  'Bookable online',
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: context.colors.textSecondary),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPricingCard() {
    final price = (widget.combo['price'] as num?)?.toDouble() ?? 0;
    final originalPrice = (widget.combo['original_price'] as num?)?.toDouble() ?? 0;
    final duration = (widget.combo['duration_minutes'] as num?)?.toInt();

    int discountPercent = 0;
    double savings = 0;
    if (originalPrice > 0 && price < originalPrice) {
      savings = originalPrice - price;
      discountPercent = (savings / originalPrice * 100).round();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (originalPrice > price) ...[
                    Text(
                      '₹${originalPrice.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textSecondary,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '₹${price.toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accentColor,
                        ),
                      ),
                      if (discountPercent > 0) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$discountPercent% OFF',
                            style: GoogleFonts.outfit(
                                fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              if (duration != null && duration > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.colors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time_rounded, size: 14, color: context.colors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'Approx. $duration min',
                        style: GoogleFonts.outfit(
                            fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.textSecondary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (savings > 0) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: context.colors.success),
                const SizedBox(width: 8),
                Text(
                  '✨ You save ₹${savings.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(
                      fontSize: 14, fontWeight: FontWeight.w600, color: context.colors.success),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIncludedServices() {
    final services = (widget.combo['services'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What\'s included',
            style: GoogleFonts.outfit(
                fontSize: 18, fontWeight: FontWeight.bold, color: context.colors.textPrimary),
          ),
          const SizedBox(height: 16),
          ...services.map((service) {
            final name = service['name'] ?? 'Service';
            final desc = service['description'] as String?;
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, size: 14, color: AppTheme.accentColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.outfit(
                              fontSize: 15, fontWeight: FontWeight.w600, color: context.colors.textPrimary),
                        ),
                        if (desc != null && desc.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            desc,
                            style: GoogleFonts.outfit(
                                fontSize: 13, color: context.colors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool isServiceable) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: (isServiceable && !_isAdding) ? _addCombo : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  disabledBackgroundColor: context.colors.surfaceMuted,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _isAdding
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Book This Combo',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isServiceable ? Colors.white : context.colors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward,
                            size: 18,
                            color: isServiceable ? Colors.white : context.colors.textSecondary,
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
