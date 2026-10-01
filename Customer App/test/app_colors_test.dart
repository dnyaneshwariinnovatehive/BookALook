import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/theme/app_colors.dart';
import 'package:customer_app/theme/app_theme.dart';

/// The tokens are a structural refactor, not a restyle: each one must resolve
/// to exactly the AppTheme constant the call sites used before.
void main() {
  test('light tokens are the existing light palette', () {
    const c = AppColors.light;
    expect(c.surface, AppTheme.lightSurface);
    expect(c.surfaceMuted, AppTheme.lightBg);
    expect(c.accentSoft, AppTheme.lightAccentSoft);
    expect(c.accentSoftHover, AppTheme.lightAccentSoftHover);
    expect(c.border, AppTheme.lightBorder);
    expect(c.cardBorder, AppTheme.lightPurpleBorder);
    expect(c.textPrimary, AppTheme.lightTextHeading);
    expect(c.textSecondary, AppTheme.lightTextBody);
    expect(c.textTertiary, AppTheme.lightTextLight);
    expect(c.success, AppTheme.lightSuccess);
    expect(c.danger, AppTheme.lightDanger);
    expect(c.warning, AppTheme.lightWarning);
    expect(c.info, AppTheme.lightInfo);
    expect(c.notesBg, AppTheme.lightNotesBg);
  });

  test('dark tokens are the existing dark palette', () {
    const c = AppColors.dark;
    expect(c.surface, AppTheme.darkSurface);
    expect(c.surfaceMuted, AppTheme.darkBg);
    expect(c.accentSoft, AppTheme.darkAccentSoft);
    expect(c.accentSoftHover, AppTheme.darkAccentSoftHover);
    expect(c.border, AppTheme.darkBorder);
    expect(c.cardBorder, AppTheme.darkBorder);
    expect(c.textPrimary, AppTheme.darkTextHeading);
    expect(c.textSecondary, AppTheme.darkTextBody);
    expect(c.textTertiary, AppTheme.darkTextLight);
    expect(c.success, AppTheme.darkSuccess);
    expect(c.danger, AppTheme.darkDanger);
    expect(c.warning, AppTheme.darkWarning);
    expect(c.info, AppTheme.darkInfo);
    expect(c.notesBg, AppTheme.darkNotesBg);
  });

  testWidgets('both themes register their tokens and context.colors finds them',
      (tester) async {
    late AppColors light;
    late AppColors dark;

    Widget probe(ThemeData theme, void Function(AppColors) sink) => MaterialApp(
          theme: theme,
          home: Builder(builder: (context) {
            sink(context.colors);
            return const SizedBox();
          }),
        );

    await tester.pumpWidget(probe(AppTheme.lightTheme, (c) => light = c));
    await tester.pumpWidget(probe(AppTheme.darkTheme, (c) => dark = c));

    expect(light, same(AppColors.light));
    expect(dark, same(AppColors.dark));
  });
}
