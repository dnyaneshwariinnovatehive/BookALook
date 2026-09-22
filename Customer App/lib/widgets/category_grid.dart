import 'package:flutter/material.dart';

import '../models/category.dart';
import '../theme/app_theme.dart';

/// The category picker on the home screen.
///
/// A grid rather than the row of chips it replaces, because the two do
/// different jobs. A horizontal strip shows three categories and hides the
/// rest behind a swipe most people never make; a grid shows a customer
/// everything the app can do for them in one glance, which is the whole point
/// of putting categories on a home screen.
///
/// Each tile is an image in a soft tinted square with the name underneath —
/// the pattern every Indian services app uses, and the one customers already
/// know how to read.
class CategoryGrid extends StatelessWidget {
  final List<ServiceCategory> categories;
  final void Function(ServiceCategory category) onTap;

  const CategoryGrid({super.key, required this.categories, required this.onTap});

  /// Soft backgrounds behind the icons.
  ///
  /// Rotated by position rather than chosen per category, so the palette stays
  /// balanced however many categories SuperAdmin adds, and a new one never
  /// arrives looking out of place.
  static const List<(Color, Color)> _tints = [
    (Color(0xFFF3EBFE), Color(0xFF9C54F2)), // lavender
    (Color(0xFFFFF1E6), Color(0xFFEF6C00)), // peach
    (Color(0xFFE6F6EF), Color(0xFF2E7D32)), // mint
    (Color(0xFFFDE8EF), Color(0xFFD81B60)), // rose
    (Color(0xFFE7F0FD), Color(0xFF1565C0)), // sky
    (Color(0xFFFFF6DA), Color(0xFFF59E0B)), // honey
  ];

  /// A sensible picture when a category has no icon yet.
  ///
  /// Better than one generic shape on every tile: a customer can still tell
  /// Hair from Nails while SuperAdmin is still uploading artwork.
  static IconData fallbackIcon(String name) {
    final n = name.toLowerCase();
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Four across on a normal phone, five on a wide one. Deriving it from
          // the width rather than hard-coding four keeps the tiles from
          // stretching absurdly on a tablet.
          final columns = constraints.maxWidth > 520 ? 5 : 4;
          const gap = 12.0;
          final tileWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;

          return Wrap(
            spacing: gap,
            runSpacing: 18,
            children: List.generate(categories.length, (index) {
              return SizedBox(
                width: tileWidth,
                child: _CategoryTile(
                  category: categories[index],
                  tint: _tints[index % _tints.length],
                  isDark: isDark,
                  onTap: () => onTap(categories[index]),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final ServiceCategory category;
  final (Color, Color) tint;
  final bool isDark;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.tint,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = tint;
    final hasIcon = category.iconUrl != null && category.iconUrl!.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            // Square, so every tile lines up however wide the screen is.
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? foreground.withValues(alpha: 0.16) : background,
                borderRadius: BorderRadius.circular(18),
              ),
              // The padding is what makes uploaded artwork sit consistently:
              // the icon breathes inside the tile instead of touching its
              // edges, whatever its own margins happen to be.
              padding: const EdgeInsets.all(14),
              child: hasIcon
                  ? Image.network(
                      category.iconUrl!,
                      fit: BoxFit.contain,
                      // Deliberately no colour filter. Tinting the image was
                      // flattening every uploaded icon into a single-colour
                      // silhouette, which is why the artwork never showed.
                      errorBuilder: (context, error, stack) => Icon(
                        CategoryGrid.fallbackIcon(category.name),
                        color: foreground,
                        size: 26,
                      ),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        // A spinner per tile would make the whole grid flicker
                        // on every home-screen visit; the fallback shape holds
                        // the space quietly instead.
                        return Icon(
                          CategoryGrid.fallbackIcon(category.name),
                          color: foreground.withValues(alpha: 0.35),
                          size: 26,
                        );
                      },
                    )
                  : Icon(
                      CategoryGrid.fallbackIcon(category.name),
                      color: foreground,
                      size: 26,
                    ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            category.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading,
            ),
          ),
        ],
      ),
    );
  }
}
