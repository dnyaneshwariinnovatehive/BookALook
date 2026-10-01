import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Semantic colour tokens, paired per brightness.
///
/// Ported from the Partner App's file of the same name, plus the two tokens
/// only the Customer App uses ([accentSoftHover], [cardBorder]).
///
/// The app defines both [AppTheme.lightTheme] and [AppTheme.darkTheme], but
/// screens used to pick colours with a `brightness == Brightness.dark` check at
/// every call site — and where a check was forgotten, hardcoded the light
/// value, so a customer in dark mode got light cards on a dark page. Naming the
/// role instead of the palette removes the decision from the widget: a card
/// asks for `surface` and gets the right one for the theme, without a branch.
///
/// Read them through `context.colors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// Cards, sheets, and anything sitting on [surfaceMuted].
  final Color surface;

  /// The scaffold itself, and the fill of inputs resting on a card.
  final Color surfaceMuted;

  /// A tinted accent for icons and pills on [surface]. Used at low alpha too.
  final Color accentSoft;

  /// [accentSoft] one step stronger, for pressed and selected states.
  final Color accentSoftHover;

  /// Hairlines and card outlines. Deliberately low contrast — a border should
  /// define an edge, not draw attention to itself.
  final Color border;

  /// The lavender outline on discovery and booking cards. In dark mode a tint
  /// would glow, so it falls back to the ordinary [border].
  final Color cardBorder;

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
  final Color notesBg;

  /// Neutral drop shadow under home-tab cards: black at 4% (light) or 20%
  /// (dark), baked to the old 8-bit alpha.
  final Color dropShadow;

  /// Idle state of a small toggle icon (e.g. the favourite heart): Colors.grey
  /// shade600 in light mode, shade400 in dark.
  final Color iconIdle;

  /// Background of a service tile in the category service strip.
  final Color serviceTileBg;

  /// Fill of a secondary filled action (retry): accent in light mode, the
  /// charcoal button colour in dark mode.
  final Color actionFill;

  /// Large decorative icon in an empty or error state.
  final Color emptyIcon;

  /// Page behind a rendered document (the invoice): paper-white in light mode.
  final Color documentBg;

  /// Initials on [avatarDimmedFill].
  final Color avatarDimmedText;

  /// Fill of a dimmed (inactive) initials avatar.
  final Color avatarDimmedFill;

  /// Decorative radial glow in the corner of booking cards: lilac at 45%
  /// (light) / deep violet at 35% (dark), baked to the old 8-bit alpha.
  final Color cardGlow;

  /// Softer danger fill for destructive buttons (cancel, log out).
  final Color dangerSoft;

  /// Fill shown where a salon photo is missing or failed to load.
  final Color imagePlaceholder;

  /// The neutral page behind booking lists and booking details.
  final Color pageNeutral;

  /// The faintly lavender page behind explore, favourites and profile.
  final Color pageTint;

  /// Outline of discovery list cards (explore, category, search results).
  final Color listBorder;

  /// Icons drawn on [success]. Dark mode's success green is pale enough that
  /// white on it loses contrast.
  final Color onSuccess;

  /// Label on [segmentKnob].
  final Color segmentKnobLabel;

  /// The sliding knob of a segmented control: a white pill in light mode, the
  /// brand accent in dark mode where a dark pill would not stand off the track.
  final Color segmentKnob;

  /// Soft shadow under cards and docked bars: the text colour at 4% (light)
  /// or 20% (dark), baked in to match the old withOpacity values exactly.
  final Color cardShadow;

  /// Outline for floating surfaces. Light mode lifts them with a shadow alone;
  /// a shadow does not read on a dark page, so dark mode adds a hairline.
  final Color raisedOutline;

  /// Unselected icons and labels in the bottom navigation pill.
  final Color navIdle;

  const AppColors({
    required this.surface,
    required this.surfaceMuted,
    required this.accentSoft,
    required this.accentSoftHover,
    required this.border,
    required this.cardBorder,
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
    required this.dropShadow,
    required this.iconIdle,
    required this.serviceTileBg,
    required this.actionFill,
    required this.emptyIcon,
    required this.documentBg,
    required this.avatarDimmedText,
    required this.avatarDimmedFill,
    required this.cardGlow,
    required this.dangerSoft,
    required this.imagePlaceholder,
    required this.pageNeutral,
    required this.pageTint,
    required this.listBorder,
    required this.onSuccess,
    required this.segmentKnobLabel,
    required this.segmentKnob,
    required this.cardShadow,
    required this.raisedOutline,
    required this.navIdle,
  });

  static const AppColors light = AppColors(
    surface: AppTheme.lightSurface,
    surfaceMuted: AppTheme.lightBg,
    accentSoft: AppTheme.lightAccentSoft,
    accentSoftHover: AppTheme.lightAccentSoftHover,
    border: AppTheme.lightBorder,
    cardBorder: AppTheme.lightPurpleBorder,
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
    dropShadow: Color(0x0A000000),
    iconIdle: Color(0xFF757575),
    serviceTileBg: Color(0xFFFAF9FF),
    actionFill: AppTheme.accentColor,
    emptyIcon: Color(0xFFBDBDBD),
    documentBg: Colors.white,
    avatarDimmedText: AppTheme.lightTextLight,
    avatarDimmedFill: AppTheme.lightBorder,
    cardGlow: Color(0x73CBA4F2),
    dangerSoft: Color(0xFFFEE8EA),
    imagePlaceholder: Color(0xFFF3F0FF),
    pageNeutral: Color(0xFFF9F9FC),
    pageTint: Color(0xFFFBF9FF),
    listBorder: Color(0xFFEBE8F6),
    onSuccess: Colors.white,
    segmentKnobLabel: AppTheme.accentColor,
    segmentKnob: AppTheme.lightSurface,
    cardShadow: Color(0x0A1C1726),
    raisedOutline: Color(0x00000000),
    navIdle: Color(0xFF9E98AE),
  );

  static const AppColors dark = AppColors(
    surface: AppTheme.darkSurface,
    surfaceMuted: AppTheme.darkBg,
    accentSoft: AppTheme.darkAccentSoft,
    accentSoftHover: AppTheme.darkAccentSoftHover,
    border: AppTheme.darkBorder,
    cardBorder: AppTheme.darkBorder,
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
    dropShadow: Color(0x33000000),
    iconIdle: Color(0xFFBDBDBD),
    serviceTileBg: AppTheme.darkBg,
    actionFill: AppTheme.darkButtonBg,
    emptyIcon: AppTheme.darkTextLight,
    documentBg: AppTheme.darkBg,
    avatarDimmedText: AppTheme.darkSurface,
    avatarDimmedFill: AppTheme.darkTextLight,
    cardGlow: Color(0x597451A4),
    dangerSoft: AppTheme.darkDangerBg,
    imagePlaceholder: AppTheme.darkAccentSoft,
    pageNeutral: AppTheme.darkBg,
    pageTint: AppTheme.darkBg,
    listBorder: AppTheme.darkBorder,
    onSuccess: AppTheme.darkBg,
    segmentKnobLabel: Colors.white,
    segmentKnob: AppTheme.accentColor,
    cardShadow: Color(0x33F3F0FA),
    raisedOutline: AppTheme.darkBorder,
    navIdle: AppTheme.darkTextBody,
  );

  /// Whether surfaces separate from the page with an outline rather than a
  /// shadow. True in dark mode, where a shadow on a near-black page does not
  /// read. For the few places that choose between a border and a shadow.
  bool get prefersOutline => raisedOutline.a > 0;

  @override
  AppColors copyWith({
    Color? surface,
    Color? surfaceMuted,
    Color? accentSoft,
    Color? accentSoftHover,
    Color? border,
    Color? cardBorder,
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
    Color? dropShadow,
    Color? iconIdle,
    Color? serviceTileBg,
    Color? actionFill,
    Color? emptyIcon,
    Color? documentBg,
    Color? avatarDimmedText,
    Color? avatarDimmedFill,
    Color? cardGlow,
    Color? dangerSoft,
    Color? imagePlaceholder,
    Color? pageNeutral,
    Color? pageTint,
    Color? listBorder,
    Color? onSuccess,
    Color? segmentKnobLabel,
    Color? segmentKnob,
    Color? cardShadow,
    Color? raisedOutline,
    Color? navIdle,
  }) {
    return AppColors(
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      accentSoft: accentSoft ?? this.accentSoft,
      accentSoftHover: accentSoftHover ?? this.accentSoftHover,
      border: border ?? this.border,
      cardBorder: cardBorder ?? this.cardBorder,
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
      dropShadow: dropShadow ?? this.dropShadow,
      iconIdle: iconIdle ?? this.iconIdle,
      serviceTileBg: serviceTileBg ?? this.serviceTileBg,
      actionFill: actionFill ?? this.actionFill,
      emptyIcon: emptyIcon ?? this.emptyIcon,
      documentBg: documentBg ?? this.documentBg,
      avatarDimmedText: avatarDimmedText ?? this.avatarDimmedText,
      avatarDimmedFill: avatarDimmedFill ?? this.avatarDimmedFill,
      cardGlow: cardGlow ?? this.cardGlow,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      imagePlaceholder: imagePlaceholder ?? this.imagePlaceholder,
      pageNeutral: pageNeutral ?? this.pageNeutral,
      pageTint: pageTint ?? this.pageTint,
      listBorder: listBorder ?? this.listBorder,
      onSuccess: onSuccess ?? this.onSuccess,
      segmentKnobLabel: segmentKnobLabel ?? this.segmentKnobLabel,
      segmentKnob: segmentKnob ?? this.segmentKnob,
      cardShadow: cardShadow ?? this.cardShadow,
      raisedOutline: raisedOutline ?? this.raisedOutline,
      navIdle: navIdle ?? this.navIdle,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;

    return AppColors(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentSoftHover: Color.lerp(accentSoftHover, other.accentSoftHover, t)!,
      border: Color.lerp(border, other.border, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
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
      dropShadow: Color.lerp(dropShadow, other.dropShadow, t)!,
      iconIdle: Color.lerp(iconIdle, other.iconIdle, t)!,
      serviceTileBg: Color.lerp(serviceTileBg, other.serviceTileBg, t)!,
      actionFill: Color.lerp(actionFill, other.actionFill, t)!,
      emptyIcon: Color.lerp(emptyIcon, other.emptyIcon, t)!,
      documentBg: Color.lerp(documentBg, other.documentBg, t)!,
      avatarDimmedText: Color.lerp(avatarDimmedText, other.avatarDimmedText, t)!,
      avatarDimmedFill: Color.lerp(avatarDimmedFill, other.avatarDimmedFill, t)!,
      cardGlow: Color.lerp(cardGlow, other.cardGlow, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      imagePlaceholder: Color.lerp(imagePlaceholder, other.imagePlaceholder, t)!,
      pageNeutral: Color.lerp(pageNeutral, other.pageNeutral, t)!,
      pageTint: Color.lerp(pageTint, other.pageTint, t)!,
      listBorder: Color.lerp(listBorder, other.listBorder, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      segmentKnobLabel: Color.lerp(segmentKnobLabel, other.segmentKnobLabel, t)!,
      segmentKnob: Color.lerp(segmentKnob, other.segmentKnob, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
      raisedOutline: Color.lerp(raisedOutline, other.raisedOutline, t)!,
      navIdle: Color.lerp(navIdle, other.navIdle, t)!,
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
