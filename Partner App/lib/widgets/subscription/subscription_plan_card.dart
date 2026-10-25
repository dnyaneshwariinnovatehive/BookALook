import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/subscription_plan.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'plan_feature_item.dart';

/// An interactive, expandable card presenting a subscription plan and its features.
class SubscriptionPlanCard extends StatefulWidget {
  final SubscriptionPlan plan;
  final bool isSelected;
  final bool isCurrentPlan;
  final VoidCallback onSelect;
  final int previewFeatureCount;

  const SubscriptionPlanCard({
    super.key,
    required this.plan,
    required this.isSelected,
    this.isCurrentPlan = false,
    required this.onSelect,
    this.previewFeatureCount = 3,
  });

  @override
  State<SubscriptionPlanCard> createState() => _SubscriptionPlanCardState();
}

class _SubscriptionPlanCardState extends State<SubscriptionPlanCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final plan = widget.plan;
    final isSelected = widget.isSelected;
    final isCurrentPlan = widget.isCurrentPlan;

    // Every feature, included or not, so plans can be compared side by side.
    final included = plan.allFeatures;
    final hasMoreFeatures = included.length > widget.previewFeatureCount;
    final previewFeatures = hasMoreFeatures
        ? included.take(widget.previewFeatureCount).toList()
        : included;
    final remainingFeatures = hasMoreFeatures
        ? included.skip(widget.previewFeatureCount).toList()
        : <PlanFeature>[];

    final cardBorderColor = isSelected
        ? AppTheme.accentColor
        : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder);

    return InkWell(
      onTap: widget.onSelect,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? AppTheme.accentColor.withValues(alpha: 0.10)
                  : AppTheme.accentColor.withValues(alpha: 0.04))
              : colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cardBorderColor,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.accentColor.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Radio selection, Plan Name, and Badges
            Row(
              children: [
                // Radio indicator
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppTheme.accentColor : colors.textTertiary,
                      width: 2.0,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: isSelected
                      ? Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.accentColor,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),

                // Plan Name
                Expanded(
                  child: Text(
                    '${plan.name} Plan',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                ),

                // Current Plan Badge (if active)
                if (isCurrentPlan)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.infoBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.info.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'CURRENT PLAN',
                      style: GoogleFonts.outfit(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: colors.info,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Price and Duration
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  plan.formattedPrice,
                  style: GoogleFonts.outfit(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: isSelected ? AppTheme.accentColor : colors.textPrimary,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  ' / ${plan.formattedDuration}',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            Divider(height: 1, thickness: 1, color: colors.border),
            const SizedBox(height: 14),

            // Section label
            Text(
              'FEATURES · ${plan.includedFeatures.length} OF ${included.length} INCLUDED',
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),

            // Feature list or Neutral Empty State
            if (included.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Standard salon booking, catalog, staff, and wallet features included.',
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    color: colors.textSecondary,
                    height: 1.35,
                  ),
                ),
              )
            else ...[
              // Preview features (always visible)
              ...previewFeatures.map((f) => PlanFeatureItem(feature: f, showExcludedState: true)),

              // Collapsible extra features
              if (hasMoreFeatures)
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    children: remainingFeatures
                        .map((f) => PlanFeatureItem(feature: f, showExcludedState: true))
                        .toList(),
                  ),
                  crossFadeState: _isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                ),

              // Expand / Collapse Toggle button
              if (hasMoreFeatures) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    // Important: Expanding or collapsing must NOT change selection or navigate
                    onTap: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isExpanded
                                ? 'Show less'
                                : 'View all ${included.length} features',
                            style: GoogleFonts.outfit(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accentColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _isExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: AppTheme.accentColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
