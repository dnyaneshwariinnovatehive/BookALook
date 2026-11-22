import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// "We're not in your area yet" — shown when "Use my current location" finds
/// the customer outside every city BookALook serves and the app falls back to
/// the nearest one.
///
/// This used to be a dark grey snackbar at the bottom of the screen, easy to
/// miss and out of keeping with the rest of the app. Returns true when the
/// customer wants to pick a different city instead.
Future<bool> showOutOfAreaDialog(BuildContext context, {required String cityName}) async {
  final changeCity = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => _OutOfAreaDialog(cityName: cityName),
  );
  return changeCity ?? false;
}

class _OutOfAreaDialog extends StatelessWidget {
  const _OutOfAreaDialog({required this.cityName});

  final String cityName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Dialog(
      backgroundColor: colors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: colors.accentSoft, shape: BoxShape.circle),
              child: const Icon(Icons.travel_explore_rounded, color: AppTheme.accentColor, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              "We're not in your area yet",
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700, color: colors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: "We're coming to more cities soon. For now, you're seeing salons in "),
                  TextSpan(
                    text: cityName,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.accentColor),
                  ),
                  const TextSpan(text: ', the nearest city we serve.'),
                ],
              ),
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 14.5, height: 1.45, color: colors.textSecondary),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const ValueKey('out_of_area_explore'),
                onPressed: () => Navigator.of(context).pop(false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  'Explore $cityName',
                  style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              key: const ValueKey('out_of_area_change'),
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppTheme.accentColor),
              child: Text(
                'Choose another city',
                style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
