import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/subscription_plan.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// A reusable display widget for a single subscription plan feature.
class PlanFeatureItem extends StatelessWidget {
  final PlanFeature feature;
  final bool isCompact;
  final bool showDescription;
  final bool showExcludedState;

  const PlanFeatureItem({
    super.key,
    required this.feature,
    this.isCompact = false,
    this.showDescription = true,
    this.showExcludedState = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isIncluded = feature.isIncluded;

    // If excluded and we are not showing excluded state, render nothing
    if (!isIncluded && !showExcludedState) {
      return const SizedBox.shrink();
    }

    final titleColor = isIncluded ? colors.textPrimary : colors.textTertiary;
    final iconColor = isIncluded
        ? (isDark ? AppTheme.darkSuccess : AppTheme.lightSuccess)
        : colors.textTertiary;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: isCompact ? 3.0 : 5.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 18,
            height: 18,
            alignment: Alignment.center,
            child: Icon(
              isIncluded ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
              size: 16,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        feature.label,
                        style: GoogleFonts.outfit(
                          fontSize: isCompact ? 13 : 14,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                          decoration: isIncluded ? null : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    if (feature.tierBadge != null && isIncluded) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.accentSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          feature.tierBadge!,
                          style: GoogleFonts.outfit(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (!isCompact && showDescription && feature.description != null && isIncluded) ...[
                  const SizedBox(height: 1.5),
                  Text(
                    feature.description!,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: colors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
