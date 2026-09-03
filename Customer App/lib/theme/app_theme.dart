import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Colors
  static const Color accentColor = Color(0xFF9C54F2);
  static const Color accentGradientStart = Color(0xFF9C54F2);
  static const Color accentGradientEnd = Color(0xFF7B32EC);

  // Light Mode Colors
  static const Color lightBg = Color(0xFFF8F7FC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightAccentSoft = Color(0xFFF3EBFE);
  static const Color lightTextHeading = Color(0xFF1C1726);
  static const Color lightTextBody = Color(0xFF7C758D);
  static const Color lightTextLight = Color(0xFFB7B2C5);
  static const Color lightBorder = Color(0xFFECEAF2);

  // Dark Mode Colors
  static const Color darkBg = Color(0xFF13111A);
  static const Color darkSurface = Color(0xFF1D1A26);
  static const Color darkAccentSoft = Color(0xFF2C223C);
  static const Color darkTextHeading = Color(0xFFF3F0FA);
  static const Color darkTextBody = Color(0xFFA7A1B8);
  static const Color darkTextLight = Color(0xFF676275);
  static const Color darkBorder = Color(0xFF2B2738);

  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: lightBg,
    primaryColor: accentColor,
    colorScheme: ColorScheme.light(
      primary: accentColor,
      surface: lightSurface,
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
      iconTheme: IconThemeData(color: lightTextHeading),
      titleTextStyle: GoogleFonts.outfit(
        color: lightTextHeading,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: lightBg,
        backgroundColor: lightTextHeading,
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        side: BorderSide.none,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(50),
        borderSide: BorderSide(color: lightBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(50),
        borderSide: BorderSide(color: lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(50),
        borderSide: BorderSide(color: accentColor, width: 2),
      ),
      labelStyle: TextStyle(color: lightTextLight),
    ),
    cardTheme: CardThemeData(
      color: lightSurface,
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: lightBorder),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: lightBorder,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: darkBg,
      contentTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: darkBg,
    primaryColor: accentColor,
    colorScheme: ColorScheme.dark(
      primary: accentColor,
      surface: darkSurface,
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
      iconTheme: IconThemeData(color: darkTextHeading),
      titleTextStyle: GoogleFonts.outfit(
        color: darkTextHeading,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: darkBg,
        backgroundColor: darkTextHeading,
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        side: BorderSide.none,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(50),
        borderSide: BorderSide(color: darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(50),
        borderSide: BorderSide(color: darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(50),
        borderSide: BorderSide(color: accentColor, width: 2),
      ),
      labelStyle: TextStyle(color: darkTextLight),
    ),
    cardTheme: CardThemeData(
      color: darkSurface,
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: darkBorder),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: darkBorder,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: lightBg,
      contentTextStyle: TextStyle(color: Colors.black, fontWeight: FontWeight.w500),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
    ),
  );
}
