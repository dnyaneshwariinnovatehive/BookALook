import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/utils/app_haptics.dart';
import '../more_menu_catalog.dart';
import '../more_search_engine.dart';

/// Renders the list of matching results or an empty-state with suggestion chips
/// when an admin is searching the More tab.
class MoreSearchResultsView extends StatelessWidget {
  final List<MoreSearchResult> results;
  final String query;
  final Map<String, dynamic> salonData;
  final Function(Map<String, dynamic>)? onSalonUpdated;
  final ValueChanged<String> onQuerySelected;
  final VoidCallback onClear;

  const MoreSearchResultsView({
    super.key,
    required this.results,
    required this.query,
    required this.salonData,
    this.onSalonUpdated,
    required this.onQuerySelected,
    required this.onClear,
  });

  static const List<String> _popularSuggestions = [
    'Working hours',
    'Offers',
    'Wallet',
    'Staff Payroll',
    'QR Code',
    'WhatsApp',
    'Dark Mode',
    'Upgrade Plan',
  ];

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return _buildEmptyState(context);
    }

    return Column(
      children: [
        for (var i = 0; i < results.length; i++) ...[
          _buildResultTile(context, results[i]),
          if (i < results.length - 1) _buildDivider(context),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildResultTile(BuildContext context, MoreSearchResult result) {
    final item = result.item;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headingColor = isDark
        ? AppTheme.darkTextHeading
        : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;

    return InkWell(
      onTap: item.type == MenuItemType.inlineToggle
          ? null
          : () {
              AppHaptics.selectionClick();
              item.onSelect?.call(context, salonData, onSalonUpdated);
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Leading Icon Container
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: item.iconColor.withValues(alpha: isDark ? 0.20 : 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(item.icon, color: item.iconColor, size: 22),
            ),
            const SizedBox(width: 14),

            // Title and Subtitle / Breadcrumb
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHighlightedTitle(item.title, headingColor),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      // Category Tag
                      Text(
                        item.category.toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: AppTheme.accentColor,
                        ),
                      ),
                      Text(
                        ' · ',
                        style: TextStyle(fontSize: 10, color: bodyColor),
                      ),
                      Expanded(
                        child: Text(
                          item.subtitle,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: bodyColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Trailing Control
            if (item.type == MenuItemType.inlineToggle &&
                item.inlineWidgetBuilder != null)
              item.inlineWidgetBuilder!(context, salonData)
            else
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightedTitle(String title, Color headingColor) {
    final cleanQuery = query.trim().toLowerCase();
    final lowerTitle = title.toLowerCase();

    if (cleanQuery.isEmpty || !lowerTitle.contains(cleanQuery)) {
      return Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: headingColor,
        ),
      );
    }

    final startIndex = lowerTitle.indexOf(cleanQuery);
    final endIndex = startIndex + cleanQuery.length;

    return Text.rich(
      TextSpan(
        style: GoogleFonts.outfit(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: headingColor,
        ),
        children: [
          if (startIndex > 0) TextSpan(text: title.substring(0, startIndex)),
          TextSpan(
            text: title.substring(startIndex, endIndex),
            style: const TextStyle(
              color: AppTheme.accentColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (endIndex < title.length)
            TextSpan(text: title.substring(endIndex)),
        ],
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: 74,
      color: isDark ? Colors.white12 : Colors.black12,
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark
        ? AppTheme.darkTextHeading
        : AppTheme.lightTextHeading;
    final subColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.darkAccentSoft
                  : AppTheme.lightAccentSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 32,
              color: AppTheme.accentColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No settings found for "$query"',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Check for spelling or try searching for another feature.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(fontSize: 13, color: subColor),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () {
              AppHaptics.selectionClick();
              onClear();
            },
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Clear search'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.accentColor),
          ),
          const SizedBox(height: 28),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'POPULAR SEARCHES',
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: subColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _popularSuggestions.map((suggestion) {
              return ActionChip(
                label: Text(
                  suggestion,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                backgroundColor: isDark
                    ? AppTheme.darkSurface
                    : AppTheme.lightSurface,
                side: BorderSide(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                onPressed: () {
                  AppHaptics.selectionClick();
                  onQuerySelected(suggestion);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
