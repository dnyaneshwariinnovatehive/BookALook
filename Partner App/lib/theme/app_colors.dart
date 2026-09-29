import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Semantic colour tokens, paired per brightness.
///
/// The app already defines both [AppTheme.lightTheme] and [AppTheme.darkTheme],
/// and the login screens read them through `Theme.of(context).brightness`. But
/// most screens then hardcode `AppTheme.lightX` or `Colors.white` anyway, so a
/// user who set dark mode while signed in as an admin gets a light-coloured
/// app the moment they land somewhere else. Naming the roles instead of the
/// palette removes the decision from the widget: a card asks for `surface`, and
/// gets white in light mode and near-black in dark mode without a branch.
///
/// Register both palettes in the `extensions` list of their [ThemeData], then
/// read them through `context.colors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// Cards, sheets, and anything sitting on [surfaceMuted].
  final Color surface;

  /// The scaffold itself, and the fill of inputs resting on a card.
  final Color surfaceMuted;

  /// A tinted accent for icons and pills on [surface]. Used at low alpha too.
  final Color accentSoft;

  /// Hairlines and card outlines. Deliberately low contrast — a border should
  /// define an edge, not draw attention to itself.
  final Color border;

  final Color textPrimary;
  final Color textSecondary;

  /// Placeholders, disabled states, and captions that are supporting detail
  /// rather than content. Never use it for text a user must read to act.
  final Color textTertiary;

  /// Text and icons drawn on top of [AppTheme.accentColor].
  final Color onAccent;

  final Color success;
  final Color successBg;
  final Color warning;
  final Color warningBg;
  final Color danger;
  final Color dangerBg;
  final Color info;
  final Color infoBg;

  /// The annotation tint used for the onboarding wizard's note blocks.
  final Color notesBg;

  const AppColors({
    required this.surface,
    required this.surfaceMuted,
    required this.accentSoft,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.onAccent,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.danger,
    required this.dangerBg,
    required this.info,
    required this.infoBg,
    required this.notesBg,
  });

  static const AppColors light = AppColors(
    surface: AppTheme.lightSurface,
    surfaceMuted: AppTheme.lightBg,
    accentSoft: AppTheme.lightAccentSoft,
    border: AppTheme.lightBorder,
    textPrimary: AppTheme.lightTextHeading,
    textSecondary: AppTheme.lightTextBody,
    textTertiary: AppTheme.lightTextLight,
    onAccent: Colors.white,
    success: AppTheme.lightSuccess,
    successBg: AppTheme.lightSuccessBg,
    warning: AppTheme.lightWarning,
    warningBg: AppTheme.lightWarningBg,
    danger: AppTheme.lightDanger,
    dangerBg: AppTheme.lightDangerBg,
    info: AppTheme.lightInfo,
    infoBg: AppTheme.lightInfoBg,
    notesBg: AppTheme.lightNotesBg,
  );

  static const AppColors dark = AppColors(
    surface: AppTheme.darkSurface,
    surfaceMuted: AppTheme.darkBg,
    accentSoft: AppTheme.darkAccentSoft,
    border: AppTheme.darkBorder,
    textPrimary: AppTheme.darkTextHeading,
    textSecondary: AppTheme.darkTextBody,
    textTertiary: AppTheme.darkTextLight,
    onAccent: Colors.white,
    success: AppTheme.darkSuccess,
    successBg: AppTheme.darkSuccessBg,
    warning: AppTheme.darkWarning,
    warningBg: AppTheme.darkWarningBg,
    danger: AppTheme.darkDanger,
    dangerBg: AppTheme.darkDangerBg,
    info: AppTheme.darkInfo,
    infoBg: AppTheme.darkInfoBg,
    notesBg: AppTheme.darkNotesBg,
  );

  @override
  AppColors copyWith({
    Color? surface,
    Color? surfaceMuted,
    Color? accentSoft,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? onAccent,
    Color? success,
    Color? successBg,
    Color? warning,
    Color? warningBg,
    Color? danger,
    Color? dangerBg,
    Color? info,
    Color? infoBg,
    Color? notesBg,
  }) {
    return AppColors(
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      accentSoft: accentSoft ?? this.accentSoft,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      onAccent: onAccent ?? this.onAccent,
      success: success ?? this.success,
      successBg: successBg ?? this.successBg,
      warning: warning ?? this.warning,
      warningBg: warningBg ?? this.warningBg,
      danger: danger ?? this.danger,
      dangerBg: dangerBg ?? this.dangerBg,
      info: info ?? this.info,
      infoBg: infoBg ?? this.infoBg,
      notesBg: notesBg ?? this.notesBg,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;

    return AppColors(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      success: Color.lerp(success, other.success, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerBg: Color.lerp(dangerBg, other.dangerBg, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoBg: Color.lerp(infoBg, other.infoBg, t)!,
      notesBg: Color.lerp(notesBg, other.notesBg, t)!,
    );
  }
}

/// Shorthand for the tokens on the current [BuildContext].
///
/// `context.colors.surface` instead of a brightness check at every call site.
extension AppColorsContext on BuildContext {
  AppColors get colors {
    final extension = Theme.of(this).extension<AppColors>();
    assert(extension != null, 'AppColors is missing from this ThemeData.');
    return extension ?? AppColors.light;
  }
}
