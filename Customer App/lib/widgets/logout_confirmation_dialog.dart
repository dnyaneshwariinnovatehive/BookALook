import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../utils/app_haptics.dart';

/// Confirmation dialog shown before signing out of BookALook.
///
/// Clearly displays the authenticated account identity (display name and
/// registered phone number), an explanatory notice of what is required to sign
/// back in, an assurance regarding saved bookings/cart data, and balanced
/// dismissal/confirmation action buttons.
class LogoutConfirmationDialog extends StatelessWidget {
  final String? name;
  final String? phone;
  final String? explanation;
  final String? secondaryNote;

  const LogoutConfirmationDialog({
    super.key,
    this.name,
    this.phone,
    this.explanation,
    this.secondaryNote = 'Your bookings and cart stay saved to your account.',
  });

  /// Displays the confirmation dialog.
  ///
  /// Returns `true` if the user confirmed logging out, `false` if they tapped
  /// 'Stay signed in', or `null` if dismissed via barrier tap.
  static Future<bool?> show(
    BuildContext context, {
    String? name,
    String? phone,
    String? explanation,
    String? secondaryNote =
        'Your bookings and cart stay saved to your account.',
  }) {
    AppHaptics.lightImpact();
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => LogoutConfirmationDialog(
        name: name,
        phone: phone,
        explanation: explanation,
        secondaryNote: secondaryNote,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textHeading = colors.textPrimary;
    final textBody = colors.textSecondary;
    final textLight = colors.textTertiary;
    final danger = colors.danger;
    final surface = colors.surface;

    final trimmedName = (name ?? '').trim();
    final trimmedPhone = (phone ?? '').trim();

    final resolvedExplanation =
        (explanation != null && explanation!.trim().isNotEmpty)
        ? explanation!.trim()
        : (trimmedPhone.isNotEmpty
              ? 'You will need to sign in again with $trimmedPhone to access your bookings, wallet and profile on this device.'
              : 'You will need to sign in again to access your bookings, wallet and profile on this device.');

    final resolvedSecondaryNote =
        secondaryNote ?? 'Your bookings and cart stay saved to your account.';

    final hasAccountInfo = trimmedName.isNotEmpty || trimmedPhone.isNotEmpty;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.border, width: 1),
      ),
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      title: Text(
        'Log out of BookALook?',
        textAlign: TextAlign.left,
        style: GoogleFonts.outfit(
          fontWeight: FontWeight.bold,
          fontSize: 20,
          color: textHeading,
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasAccountInfo) ...[
              if (trimmedName.isNotEmpty)
                Text(
                  trimmedName,
                  textAlign: TextAlign.left,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textHeading,
                  ),
                ),
              if (trimmedPhone.isNotEmpty) ...[
                if (trimmedName.isNotEmpty) const SizedBox(height: 3),
                Text(
                  trimmedPhone,
                  textAlign: TextAlign.left,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    color: textBody,
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
            Text(
              resolvedExplanation,
              textAlign: TextAlign.left,
              style: GoogleFonts.outfit(
                fontSize: 14,
                height: 1.45,
                color: textBody,
              ),
            ),
            if (resolvedSecondaryNote.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                resolvedSecondaryNote.trim(),
                textAlign: TextAlign.left,
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  height: 1.4,
                  color: textLight,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            AppHaptics.lightImpact();
            Navigator.of(context).pop(false);
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            'Stay signed in',
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textBody,
            ),
          ),
        ),
        const SizedBox(width: 4),
        TextButton(
          onPressed: () {
            AppHaptics.lightImpact();
            Navigator.of(context).pop(true);
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            'Log out',
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: danger,
            ),
          ),
        ),
      ],
    );
  }
}
