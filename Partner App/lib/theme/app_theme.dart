import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Colors
  static const Color accentColor = Color(0xFF9C54F2);
  static const Color accentGradientStart = Color(0xFF9C54F2);
  static const Color accentGradientEnd = Color(0xFF7B32EC);
  static const Color accentGradientLightEnd = Color(0xFFB885FC);

  // Light Mode Colors
  static const Color lightBg = Color(0xFFF8F7FC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightAccentSoft = Color(0xFFF3EBFE);
  static const Color lightAccentSoftHover = Color(0xFFE9DAFD);
  static const Color lightTextHeading = Color(0xFF1C1726);
  static const Color lightTextBody = Color(0xFF7C758D);
  static const Color lightTextLight = Color(0xFFB7B2C5);
  static const Color lightBorder = Color(0xFFECEAF2);

  // Dark Mode Colors
  static const Color darkBg = Color(0xFF13111A);
  static const Color darkSurface = Color(0xFF1D1A26);
  static const Color darkAccentSoft = Color(0xFF2C223C);
  static const Color darkAccentSoftHover = Color(0xFF3B2D50);
  static const Color darkTextHeading = Color(0xFFF3F0FA);
  static const Color darkTextBody = Color(0xFFA7A1B8);
  static const Color darkTextLight = Color(0xFF676275);
  static const Color darkBorder = Color(0xFF2B2738);

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
  static const Color darkSuccess = Color(0xFF81C784);
  static const Color darkSuccessBg = Color(0xFF1B3F22);
  static const Color darkWarning = Color(0xFFFFB74D);
  static const Color darkWarningBg = Color(0xFF3E2712);
  static const Color darkDanger = Color(0xFFE57373);
  static const Color darkDangerBg = Color(0xFF4A1C1C);
  static const Color darkInfo = Color(0xFF64B5F6);
  static const Color darkInfoBg = Color(0xFF0D2744);
  static const Color darkNotesBg = Color(0xFF3E2712);

  // Secondary Warm Brown Palette
  static const Color brownDark = Color(0xFF2A2320);
  static const Color brownMedium = Color(0xFF4E403B);
  static const Color brownGoldText = Color(0xFFF5DEC2);
  static const Color brownMuted = Color(0xFF8A8078);
  static const Color brownLightBg = Color(0xFFE3D9CE);
  
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
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        side: BorderSide.none,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentColor, // Note: We will use a custom container for gradient buttons when needed, but this acts as fallback
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        elevation: 0,
        shadowColor: const Color(0x4D9C54F2), // rgba(156, 84, 242, 0.3)
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: lightBorder, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: lightBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: accentColor, width: 2),
      ),
      labelStyle: TextStyle(color: lightTextLight),
      hintStyle: TextStyle(color: lightTextLight),
    ),
    cardTheme: CardThemeData(
      color: lightSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
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
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        side: BorderSide.none,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        elevation: 0,
        shadowColor: const Color(0x4D9C54F2),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: darkBorder, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: darkBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: accentColor, width: 2),
      ),
      labelStyle: TextStyle(color: darkTextLight),
      hintStyle: TextStyle(color: darkTextLight),
    ),
    cardTheme: CardThemeData(
      color: darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
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
  );
}
