import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/audience_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// A one-line strip saying the list is narrowed to one gender, with a way out.
///
/// Shown wherever results follow the session's gender choice without a filter
/// button of their own (Explore, search), so the narrowing is never silent.
/// Hidden when everyone is shown. Redraws itself when the choice changes.
class AudienceBanner extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  const AudienceBanner({super.key, this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 0)});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AudienceService.changes,
      builder: (context, _, _) {
        final audience = AudienceService.apiParam(
          AudienceService.homeFilterFor(AudienceService.browsingGenderNow),
        );
        if (audience == null) return const SizedBox.shrink();

        return Padding(
          key: const ValueKey('audience-banner'),
          padding: padding,
          child: Row(
            children: [
              Icon(Icons.person_outline, size: 16, color: AppTheme.accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Showing salons and services for $audience',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => AudienceService.choose('All'),
                child: Text('Show all', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      },
    );
  }
}
