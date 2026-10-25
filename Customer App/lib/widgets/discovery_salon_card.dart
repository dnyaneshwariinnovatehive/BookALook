import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/salon_detail_screen.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../utils/app_haptics.dart';

class DiscoverySalonCard extends StatelessWidget {
  final Map<String, dynamic> salon;
  final bool isFavourited;
  final bool showFavourite;
  final VoidCallback onToggleFavourite;
  final String? categoryId;
  final String? categoryName;
  final String? serviceId;
  // Kept for backward compatibility
  final String? selectedServiceId;
  final ValueChanged<Map<String, dynamic>>? onServiceSelected;
  final ValueChanged<Map<String, dynamic>>? onServiceDeselected;

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
    this.onServiceDeselected,
  });

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

  void _openSalon(BuildContext context) {
    AppHaptics.selectionClick();
    final id = salon['id'].toString();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SalonDetailScreen(
          salonId: id,
          categoryId: categoryId,
          categoryName: categoryName,
          serviceId: serviceId ?? selectedServiceId,
          initialScrollToServices: true,
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
    final isServiceable = salon['is_serviceable'] != false;
    final count = (salon['review_count'] as num?)?.toInt() ?? 0;
    final avg = (salon['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final distance = salon['distance_km'];
    final coverPhoto = salon['cover_photo_url'] as String? ?? '';
    final name = salon['name'] as String? ?? 'Unnamed Salon';
    final locationText = _formatLocation(salon);

    final photosCount =
        (salon['photos_count'] as num?)?.toInt() ??
        (count > 0 ? (count ~/ 10).clamp(5, 20) : 8);

    final isOpen = salon['is_open_now'] == true ||
        salon['is_open_now'] == 1 ||
        (salon['open_status_label'] != null &&
            (salon['open_status_label'] as String).toLowerCase().contains('open'));

    final openLabel = salon['open_status_label'] as String? ??
        (isOpen ? 'Open' : 'Closed');

    final distanceText = distance != null
        ? '${salon['distance_is_approximate'] == true ? '~' : ''}$distance km'
        : '2.5 km';

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _openSalon(context),
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
          padding: const EdgeInsets.all(12),
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
                const SizedBox(width: 12),
                // 2. Right Salon Info Column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                            onTap: onToggleFavourite,
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
                                isFavourited
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 15.5,
                                color: isFavourited
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
                          const SizedBox(width: 3),
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
                      const SizedBox(height: 2),
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
                      const SizedBox(height: 8),
                      // View Salon & Book Action Button
                      GestureDetector(
                        onTap: () => _openSalon(context),
                        child: Container(
                          width: double.infinity,
                          height: 36,
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
