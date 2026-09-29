import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../screens/salon_detail_screen.dart';
import '../theme/app_theme.dart';
import 'category_service_strip.dart';

class DiscoverySalonCard extends StatelessWidget {
  final Map<String, dynamic> salon;
  final bool isFavourited;
  final bool showFavourite;
  final VoidCallback onToggleFavourite;

  /// Category/sub-service context from a discovery screen. When set, the salon
  /// page opens on that category's services so browsing a category leads to
  /// that category inside the salon, not every service the salon lists.
  final String? categoryId;
  final String? categoryName;
  final String? serviceId;

  const DiscoverySalonCard({
    super.key,
    required this.salon,
    this.isFavourited = false,
    this.showFavourite = false,
    required this.onToggleFavourite,
    this.categoryId,
    this.categoryName,
    this.serviceId,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.darkSurface : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFEBE8F6);
    final headingColor = isDark
        ? AppTheme.darkTextHeading
        : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final isServiceable = salon['is_serviceable'] != false;
    final count = (salon['review_count'] as num?)?.toInt() ?? 0;
    final avg = (salon['avg_rating'] as num?)?.toDouble() ?? 0;
    final distance = salon['distance_km'];
    final id = salon['id'].toString();

    // Present only when a category is being browsed; the plain directory leaves
    // the key null and the card looks exactly as it did before.
    final categoryServices =
        (salon['category_services'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SalonDetailScreen(
                salonId: id,
                categoryId: categoryId,
                categoryName: categoryName,
                serviceId: serviceId,
              ),
            ),
          );
        },
        child: Opacity(
          opacity: isServiceable ? 1.0 : 0.65,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 100,
                        height: 114,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              salon['cover_photo_url'] ?? '',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: isDark
                                    ? AppTheme.darkAccentSoft
                                    : const Color(0xFFF3F0FF),
                                child: const Icon(
                                  Icons.storefront,
                                  color: AppTheme.accentColor,
                                  size: 32,
                                ),
                              ),
                            ),
                            if (showFavourite)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: GestureDetector(
                                  onTap: onToggleFavourite,
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppTheme.darkSurface.withOpacity(
                                              0.85,
                                            )
                                          : Colors.white.withOpacity(0.85),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isFavourited
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      size: 16,
                                      color: isFavourited
                                          ? AppTheme.lightDanger
                                          : (isDark
                                                ? Colors.grey.shade400
                                                : Colors.grey.shade600),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  salon['name'] ?? 'Unnamed Salon',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: headingColor,
                                  ),
                                ),
                              ),
                              if (count > 0) ...[
                                const Icon(
                                  Icons.star,
                                  size: 15,
                                  color: AppTheme.starRating,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  avg.toStringAsFixed(1),
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: headingColor,
                                  ),
                                ),
                              ] else
                                Text(
                                  'New',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: bodyColor,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 15,
                                color: AppTheme.accentColor,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  salon['address'] ?? 'No address',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: bodyColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (!isServiceable)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppTheme.darkWarningBg
                                    : AppTheme.lightWarningBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                salon['unavailable_reason'] ??
                                    'Not taking bookings',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppTheme.darkWarning
                                      : AppTheme.lightWarning,
                                ),
                              ),
                            )
                          else
                            Row(
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  size: 13,
                                  color: AppTheme.statusAvailable,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Bookable online',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: bodyColor,
                                    ),
                                  ),
                                ),
                                if (distance != null)
                                  Text(
                                    '${salon['distance_is_approximate'] == true ? '~' : ''}$distance km',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.accentColor,
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Full width below the card's own row, so the strip is not
                // squeezed into the column beside the photo.
                if (categoryServices.isNotEmpty)
                  CategoryServiceStrip(
                    salonId: id,
                    services: categoryServices,
                    categoryName: categoryName,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
