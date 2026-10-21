import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/salon_detail_screen.dart';
import '../screens/phone_screen.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../utils/app_haptics.dart';
import '../utils/error_text.dart';

class DiscoverySalonCard extends StatefulWidget {
  final Map<String, dynamic> salon;
  final bool isFavourited;
  final bool showFavourite;
  final VoidCallback onToggleFavourite;
  final String? categoryId;
  final String? categoryName;
  final String? serviceId;
  final String? selectedServiceId;
  final ValueChanged<Map<String, dynamic>>? onServiceSelected;

  const DiscoverySalonCard({
    super.key,
    required this.salon,
    this.isFavourited = false,
    this.showFavourite = false,
    required this.onToggleFavourite,
    this.categoryId,
    this.categoryName,
    this.serviceId,
    this.selectedServiceId,
    this.onServiceSelected,
  });

  @override
  State<DiscoverySalonCard> createState() => _DiscoverySalonCardState();
}

class _DiscoverySalonCardState extends State<DiscoverySalonCard> {
  final CartService _cartService = CartService();
  String? _selectedServiceId;
  final Set<String> _addingServiceIds = {};

  @override
  void initState() {
    super.initState();
    _selectedServiceId = widget.selectedServiceId ?? widget.serviceId;
    CartService.globalCartNotifier.addListener(_onCartChanged);
  }

  @override
  void didUpdateWidget(covariant DiscoverySalonCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedServiceId != null &&
        widget.selectedServiceId != _selectedServiceId) {
      _selectedServiceId = widget.selectedServiceId;
    }
  }

  @override
  void dispose() {
    CartService.globalCartNotifier.removeListener(_onCartChanged);
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  String _formatLocation(Map<String, dynamic> salon) {
    final addr = (salon['address'] as String?)?.trim() ?? '';
    if (addr.isEmpty) {
      final city =
          salon['city'] as String? ??
          LocationService.instance.city?.name ??
          '';
      return city.isNotEmpty ? city : 'Pune';
    }

    final parts = addr
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      final area = parts[parts.length - 2];
      final city = parts[parts.length - 1]
          .replaceAll(RegExp(r'\d+'), '')
          .trim();
      if (area.isNotEmpty && city.isNotEmpty) {
        return '$area, $city';
      }
    }
    return addr;
  }

  Future<void> _handleServiceClick(Map<String, dynamic> service) async {
    final sId = service['id'].toString();
    final salonId = widget.salon['id'].toString();
    AppHaptics.selectionClick();

    setState(() {
      _selectedServiceId = sId;
    });

    widget.onServiceSelected?.call(service);

    // If already in cart, nothing further needed
    if (CartService.isServiceInCart(sId)) return;

    // Check auth
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const PhoneScreen(isModal: true)),
      );
      if (loggedIn != true || !mounted) return;
    }

    if (_addingServiceIds.contains(sId)) return;
    setState(() => _addingServiceIds.add(sId));

    try {
      await _cartService.addItem(salonId, sId);
      if (!mounted) return;
      AppHaptics.lightImpact();
      setState(() {});
    } on CartConflictException catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      _confirmReplaceCart(e, service);
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            describeError(e, fallback: 'Could not select service'),
            style: GoogleFonts.outfit(),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _addingServiceIds.remove(sId));
      }
    }
  }

  void _confirmReplaceCart(
    CartConflictException e,
    Map<String, dynamic> service,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Replace cart items?',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
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
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(color: context.colors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              AppHaptics.lightImpact();
              Navigator.pop(ctx);
              try {
                await _cartService.clearGlobalCart();
                if (!mounted) return;
                await _handleServiceClick(service);
              } catch (_) {}
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Replace',
              style: GoogleFonts.outfit(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _openSalon() {
    AppHaptics.selectionClick();
    final id = widget.salon['id'].toString();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SalonDetailScreen(
          salonId: id,
          categoryId: widget.categoryId,
          categoryName: widget.categoryName,
          serviceId: _selectedServiceId ?? widget.serviceId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = context.colors.surface;
    final cardBorderColor = Theme.of(context).brightness == Brightness.dark
        ? context.colors.border
        : const Color(0xFFE9E6F2);
    final headingColor = context.colors.textPrimary;
    final bodyColor = context.colors.textSecondary;
    final isServiceable = widget.salon['is_serviceable'] != false;
    final count = (widget.salon['review_count'] as num?)?.toInt() ?? 0;
    final avg = (widget.salon['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final distance = widget.salon['distance_km'];
    final coverPhoto = widget.salon['cover_photo_url'] as String? ?? '';
    final name = widget.salon['name'] as String? ?? 'Unnamed Salon';
    final locationText = _formatLocation(widget.salon);

    final photosCount =
        (widget.salon['photos_count'] as num?)?.toInt() ??
        (count > 0 ? (count ~/ 10).clamp(5, 20) : 8);

    final isOpen = widget.salon['is_open_now'] == true ||
        widget.salon['is_open_now'] == 1 ||
        (widget.salon['open_status_label'] != null &&
            (widget.salon['open_status_label'] as String).toLowerCase().contains('open'));

    final openLabel = widget.salon['open_status_label'] as String? ??
        (isServiceable ? 'Open • Closes 9:00 PM' : 'Closed');

    final distanceText = distance != null
        ? '${widget.salon['distance_is_approximate'] == true ? '~' : ''}$distance km'
        : '2.5 km';

    final categoryServices =
        (widget.salon['category_services'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _openSalon,
      child: Opacity(
        opacity: isServiceable ? 1.0 : 0.7,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cardBorderColor, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(10),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Left Salon Photo Column
                SizedBox(
                  width: 115,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          coverPhoto,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: context.colors.imagePlaceholder,
                            child: const Icon(
                              Icons.storefront,
                              color: AppTheme.accentColor,
                              size: 32,
                            ),
                          ),
                        ),
                        // Photo count badge at bottom left
                        Positioned(
                          bottom: 7,
                          left: 7,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.photo_library_outlined,
                                  size: 11,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 3.5),
                                Text(
                                  '$photosCount+ Photos',
                                  style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                // 2. Right Salon Info Column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Salon Name & Wishlist Heart Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                                color: headingColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onToggleFavourite,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: surfaceColor,
                                border: Border.all(
                                  color: cardBorderColor,
                                  width: 1.1,
                                ),
                              ),
                              child: Icon(
                                widget.isFavourited
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 15.5,
                                color: widget.isFavourited
                                    ? Colors.red
                                    : bodyColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // Rating & Reviews Row
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 15,
                            color: AppTheme.starRating,
                          ),
                          const SizedBox(width: 2.5),
                          Text(
                            avg > 0 ? avg.toStringAsFixed(1) : 'New',
                            style: GoogleFonts.outfit(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: headingColor,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            count > 0 ? '($count reviews)' : '(New)',
                            style: GoogleFonts.outfit(
                              fontSize: 11.5,
                              color: bodyColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // Location Row
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 13.5,
                            color: AppTheme.accentColor,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              locationText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 11.5,
                                color: bodyColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      // Status & Distance Row
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isOpen
                                  ? const Color(0xFF10B981)
                                  : context.colors.danger,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              openLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isOpen
                                    ? const Color(0xFF10B981)
                                    : bodyColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            distanceText,
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: bodyColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Services Chips Row
                      if (categoryServices.isNotEmpty)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: categoryServices.take(6).map((service) {
                              final sId = service['id'].toString();
                              final sName = service['name'] ?? 'Service';
                              final double price =
                                  (service['price'] as num?)?.toDouble() ?? 0;
                              final bool isSelected =
                                  _selectedServiceId == sId ||
                                  CartService.isServiceInCart(sId);
                              final bool isAdding =
                                  _addingServiceIds.contains(sId);

                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: GestureDetector(
                                  onTap: () => _handleServiceClick(service),
                                  child: Container(
                                    constraints:
                                        const BoxConstraints(minWidth: 62),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppTheme.accentColor
                                          : const Color(0xFFF5F3FF),
                                      borderRadius:
                                          BorderRadius.circular(9),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF6D28D9)
                                            : const Color(0xFFEDE9FE),
                                        width: isSelected ? 1.4 : 1.0,
                                      ),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: AppTheme.accentColor
                                                    .withValues(alpha: 0.25),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          sName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.outfit(
                                            fontSize: 10,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.w600,
                                            color: isSelected
                                                ? Colors.white
                                                : headingColor,
                                          ),
                                        ),
                                        const SizedBox(height: 1.5),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isAdding)
                                              Container(
                                                width: 8,
                                                height: 8,
                                                margin: const EdgeInsets.only(
                                                  right: 3,
                                                ),
                                                child:
                                                    const CircularProgressIndicator(
                                                  strokeWidth: 1.5,
                                                  color: Colors.white,
                                                ),
                                              )
                                            else if (isSelected) ...[
                                              const Icon(
                                                Icons.check_circle_rounded,
                                                size: 10,
                                                color: Colors.white,
                                              ),
                                              const SizedBox(width: 2),
                                            ],
                                            Text(
                                              '₹${price.toStringAsFixed(0)}',
                                              style: GoogleFonts.outfit(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: isSelected
                                                    ? Colors.white
                                                    : AppTheme.accentColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      const SizedBox(height: 7),
                      // View Salon & Book Action Button
                      GestureDetector(
                        onTap: _openSalon,
                        child: Container(
                          width: double.infinity,
                          height: 35,
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'View Salon & Book',
                                style: GoogleFonts.outfit(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
