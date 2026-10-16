import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_version_service.dart';
import '../theme/app_theme.dart';

class OptionalUpdateDialog extends StatelessWidget {
  final AppUpdateInfo updateInfo;

  const OptionalUpdateDialog({
    super.key,
    required this.updateInfo,
  });

  static Future<void> showIfEligible(BuildContext context, AppUpdateInfo info) async {
    final shouldPrompt = await AppVersionService.instance.shouldPromptOptional(info.targetVersion);
    if (!shouldPrompt) return;

    if (!context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => OptionalUpdateDialog(updateInfo: info),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final textColor = isDark ? AppTheme.darkTextHeading : AppTheme.lightTextHeading;
    final bodyColor = isDark ? AppTheme.darkTextBody : AppTheme.lightTextBody;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: bgColor,
      elevation: 12,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Top Badge Icon
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppTheme.accentGradientStart, AppTheme.accentGradientEnd],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentColor.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),

            const SizedBox(height: 18),

            Text(
              'Update Available',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkAccentSoft : AppTheme.lightAccentSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Version ${updateInfo.targetVersion}',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentColor,
                ),
              ),
            ),

            const SizedBox(height: 12),

            Text(
              updateInfo.message ??
                  'A new version of BookALook is ready with speed enhancements and the latest features.',
              style: GoogleFonts.inter(
                fontSize: 13.5,
                height: 1.45,
                color: bodyColor,
              ),
              textAlign: TextAlign.center,
            ),

            if (updateInfo.releaseNotes != null && updateInfo.releaseNotes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "What's New:",
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      updateInfo.releaseNotes!,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: bodyColor,
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Actions
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      AppVersionService.instance.postponeOptionalUpdate(updateInfo.targetVersion);
                      Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Later',
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: bodyColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await AppVersionService.launchStoreUrl(updateInfo.storeUrl);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Update Now',
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
