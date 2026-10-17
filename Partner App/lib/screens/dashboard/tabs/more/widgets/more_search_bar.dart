import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:partner_app/theme/app_theme.dart';
import 'package:partner_app/utils/app_haptics.dart';
import 'package:partner_app/widgets/animated_search_field.dart';

/// A search bar for the More tab featuring the same pill-shaped stadium UI,
/// drop shadows, and animated typewriter suggestion hints from the Customer App,
/// while preserving 100% of the existing Partner search logic.
class MoreSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final String hintText;
  final List<String> suggestions;

  const MoreSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onChanged,
    this.onClear,
    this.hintText = 'Search settings and features',
    this.suggestions = const [
      "offers",
      "discount",
      "timings",
      "working hours",
      "staff",
      "salary",
      "payroll",
      "wallet",
      "payout",
      "whatsapp",
      "subscription",
      "services",
      "holidays",
      "bank details",
    ],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder.withValues(alpha: 0.6);
    final surfaceColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final hintColor = isDark ? AppTheme.darkTextLight : AppTheme.lightTextLight;
    final textColor = isDark
        ? AppTheme.darkTextHeading
        : AppTheme.lightTextHeading;

    return Semantics(
      label: 'Search settings and features',
      textField: true,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.25)
                  : const Color(0x0F000000),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 22, color: hintColor),
            const SizedBox(width: 10),
            Expanded(
              child: AnimatedSearchField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                suggestions: suggestions,
                style: GoogleFonts.outfit(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: GoogleFonts.outfit(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w400,
                    color: hintColor,
                  ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
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
