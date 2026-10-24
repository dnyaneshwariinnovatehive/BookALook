import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  // Brand Colors
  static const Color accentColor = Color(0xFF9850F1);
  static const Color accentGradientStart = Color(0xFF9850F1);
  static const Color accentGradientEnd = Color(0xFF7B32EC);
  static const Color accentGradientLightEnd = Color(0xFFB088FF);

  // Light Mode Colors
  static const Color lightBg = Color(0xFFFCFAFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightAccentSoft = Color(0xFFEEE3FD);
  static const Color lightAccentSoftHover = Color(0xFFE9DAFD);
  static const Color lightTextHeading = Color(0xFF18151D);
  static const Color lightTextBody = Color(0xFF7C758D);
  static const Color lightTextLight = Color(0xFFB7B2C5);
  static const Color lightBorder = Color(0xFFECEAF2);
  static const Color lightCardBg = Color(0xFFFFFFFF);

  // Dark Mode Colors
  static const Color darkBg = Color(0xFF121018);
  static const Color darkSurface = Color(0xFF1C1824);
  static const Color darkAccentSoft = Color(0xFF24202D);
  static const Color darkAccentSoftHover = Color(0xFF332B40);
  static const Color darkTextHeading = Color(0xFFEEE3FD);
  static const Color darkTextBody = Color(0xFFA7A1B8);
  static const Color darkTextLight = Color(0xFF756E85);
  static const Color darkBorder = Color(0xFF3A3048);

  // Semantic Colors (Light)
  static const Color lightSuccess = Color(0xFF2E7D32);
  static const Color lightSuccessBg = Color(0xFFE8F5E9);
  static const Color lightWarning = Color(0xFFEF6C00);
  static const Color lightWarningBg = Color(0xFFFFF3E0);
  static const Color lightDanger = Color(0xFFC62828);
  static const Color lightDangerBg = Color(0xFFFFEBEE);
  static const Color lightInfo = Color(0xFF1565C0);
  static const Color lightInfoBg = Color(0xFFE3F2FD);
  static const Color lightNotesBg = Color(0xFFFFF8E1);

  // Semantic Colors (Dark)
  static const Color darkSuccess = Color(0xFF4ADE80);
  static const Color darkSuccessBg = Color(0xFF142E1F);
  static const Color darkWarning = Color(0xFFFBBF24);
  static const Color darkWarningBg = Color(0xFF33200D);
  static const Color darkDanger = Color(0xFFF87171);
  static const Color darkDangerBg = Color(0xFF381519);
  static const Color darkInfo = Color(0xFF9850F1);
  static const Color darkInfoBg = Color(0xFF28183B);
  static const Color darkNotesBg = Color(0xFF33200D);

  // Secondary Warm Brown Palette
  static const Color brownDark = Color(0xFF2A2320);
  static const Color brownMedium = Color(0xFF4E403B);
  static const Color brownGoldText = Color(0xFFD4A24C);
  static const Color brownMuted = Color(0xFF8A8078);
  static const Color brownLightBg = Color(0xFFE3D9CE);
  
  // Custom Dark Button Color
  static const Color darkButtonBg = Color(0xFF2A2831);
  static const Color lightPurpleBorder = Color(0xFFEFE8FC);

  // Misc
  static const Color starRating = Color(0xFFFFB300);
  static const Color femaleColor = Color(0xFFC2185B);
  static const Color femaleBg = Color(0xFFFCE4EC);
  static const Color maleColor = Color(0xFF1565C0);
  static const Color maleBg = Color(0xFFE3F2FD);
  static const Color statusAvailable = Color(0xFF16A34A);
  static const Color statusBreak = Color(0xFFF59E0B);
  static const Color statusBusy = Color(0xFFDC2626);

  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    extensions: const [AppColors.light],
    scaffoldBackgroundColor: lightBg,
    primaryColor: accentColor,
    dividerColor: lightBorder,
    colorScheme: const ColorScheme.light(
      primary: accentColor,
      surface: lightSurface,
      background: lightBg,
      onPrimary: Colors.white,
      onSurface: lightTextHeading,
    ),
    textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme).copyWith(
      displayLarge: GoogleFonts.outfit(color: lightTextHeading, fontWeight: FontWeight.bold),
      bodyLarge: GoogleFonts.outfit(color: lightTextBody),
      bodyMedium: GoogleFonts.outfit(color: lightTextBody),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: lightBg,
      elevation: 0,
      iconTheme: const IconThemeData(color: lightTextHeading),
      titleTextStyle: GoogleFonts.outfit(
        color: lightTextHeading,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accentColor,
        backgroundColor: lightAccentSoft,
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
        side: BorderSide.none,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        elevation: 0,
        shadowColor: const Color.fromRGBO(212, 162, 76, 0.35),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: lightBorder, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: lightBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: accentColor, width: 2),
      ),
      labelStyle: TextStyle(color: lightTextLight),
      hintStyle: TextStyle(color: lightTextLight),
    ),
    cardTheme: CardThemeData(
      color: lightSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: lightBorder),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: lightBorder,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: lightSurface,
      contentTextStyle: TextStyle(color: lightTextHeading, fontWeight: FontWeight.w500),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    extensions: const [AppColors.dark],
    scaffoldBackgroundColor: darkBg,
    primaryColor: accentColor,
    dividerColor: darkBorder,
    colorScheme: const ColorScheme.dark(
      primary: accentColor,
      surface: darkSurface,
      background: darkBg,
      onPrimary: Colors.white,
      onSurface: darkTextHeading,
    ),
    textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).copyWith(
      displayLarge: GoogleFonts.outfit(color: darkTextHeading, fontWeight: FontWeight.bold),
      bodyLarge: GoogleFonts.outfit(color: darkTextBody),
      bodyMedium: GoogleFonts.outfit(color: darkTextBody),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: darkBg,
      elevation: 0,
      iconTheme: const IconThemeData(color: darkTextHeading),
      titleTextStyle: GoogleFonts.outfit(
        color: darkTextHeading,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accentColor,
        backgroundColor: darkAccentSoft,
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
        side: const BorderSide(color: darkBorder, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        elevation: 0,
        shadowColor: const Color.fromRGBO(212, 162, 76, 0.35),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: darkBorder, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: darkBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: accentColor, width: 2),
      ),
      labelStyle: TextStyle(color: darkTextLight),
      hintStyle: TextStyle(color: darkTextLight),
    ),
    cardTheme: CardThemeData(
      color: darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: darkBorder),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: darkBorder,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: darkSurface,
      contentTextStyle: TextStyle(color: darkTextHeading, fontWeight: FontWeight.w500),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: darkBorder, width: 1),
      ),
      titleTextStyle: GoogleFonts.outfit(
        color: darkTextHeading,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      contentTextStyle: GoogleFonts.outfit(
        color: darkTextBody,
        fontSize: 14,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: darkSurface,
      modalBackgroundColor: darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}
