import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_role.dart';
import 'app_constants.dart';

/// AppTheme configured with GoogleFonts.poppins typography and strict design tokens.
/// Supports role-based automatic dynamic theme adaptation:
/// - Patient: Royal Blue and White
/// - Doctor: Medical Emerald Green and White
/// - Operator: Warm Golden Ochre/Amber and White
/// - Admin: Crimson Red and White
class AppTheme {
  AppTheme._();

  static TextStyle get screenTitle => GoogleFonts.poppins(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get sectionTitle => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get cardTitle => GoogleFonts.poppins(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get body => GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );

  static TextStyle get bodyBold => GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get caption => GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );

  static TextStyle get captionSmall => GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );

  static TextStyle get buttonText => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      );

  static ThemeData themeForRole(UserRole role) {
    final (primary, primaryTint, primaryDark) = switch (role) {
      UserRole.patient => (
          const Color(0xFF0284C7), // Blue
          const Color(0xFFE0F2FE),
          const Color(0xFF0369A1),
        ),
      UserRole.doctor => (
          const Color(0xFF16A34A), // Medical Green
          const Color(0xFFDCFCE7),
          const Color(0xFF15803D),
        ),
      UserRole.operator => (
          const Color(0xFFEA580C), // Vibrant Orange
          const Color(0xFFFFEDD5),
          const Color(0xFF9A3412),
        ),
      UserRole.admin => (
          const Color(0xFF581C87), // Dark Purple
          const Color(0xFFF3E8FF),
          const Color(0xFF3B0764),
        ),
    };

    final baseTextTheme = GoogleFonts.poppinsTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primary,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme(
        brightness: Brightness.light,
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: primaryTint,
        onPrimaryContainer: primaryDark,
        secondary: primaryDark,
        onSecondary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
        onError: Colors.white,
      ),
      textTheme: baseTextTheme.copyWith(
        titleLarge: screenTitle,
        titleMedium: sectionTitle,
        titleSmall: cardTitle,
        bodyMedium: body,
        bodySmall: caption,
        labelLarge: buttonText,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusButton),
          ),
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary, width: 1.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusButton),
          ),
          textStyle: buttonText,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusChip),
        ),
        backgroundColor: primaryTint,
        selectedColor: primary,
        labelStyle: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: caption,
        labelStyle: caption,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusInput),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  static ThemeData get lightTheme => themeForRole(UserRole.patient);
}
