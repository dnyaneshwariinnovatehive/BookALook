import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/utils/app_haptics.dart';

/// An Instagram Settings-style search bar for the More tab.
///
/// Features:
/// - Prominent rounded container with theme-aware borders and background.
/// - Prefix search icon and animated clear button.
/// - Accessible semantics and Outfit typography.
class MoreSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final String hintText;

  const MoreSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onChanged,
    this.onClear,
    this.hintText = 'Search settings and features',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final hintColor = isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight;
    final textColor = isDark
        ? AppTheme.darkTextHeading
        : AppTheme.lightTextHeading;

    return Semantics(
      label: 'Search settings and features',
      textField: true,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 20, color: hintColor),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                enableSuggestions: true,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: hintColor,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.text.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Semantics(
                  button: true,
                  label: 'Clear search',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      AppHaptics.selectionClick();
                      controller.clear();
                      onChanged?.call('');
                      onClear?.call();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        Icons.cancel_rounded,
                        size: 18,
                        color: hintColor,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
