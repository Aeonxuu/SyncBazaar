import 'package:flutter/material.dart';

import '../constants/colors.dart';

class AppTheme {
  /// The bundled family declared in `pubspec.yaml`.
  ///
  /// Was `google_fonts`, which downloads Inter on first use. That is the wrong
  /// trade for a till: a bazaar has no dependable network, and the fetch fails
  /// loudly rather than quietly — an offline tablet could not print a receipt
  /// at all because the font request threw before anything was drawn. The
  /// files now ship with the app, so typography never depends on connectivity.
  static const String fontFamily = 'Inter';

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = base.textTheme
        .apply(fontFamily: fontFamily)
        .copyWith(
          headlineLarge: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
          headlineMedium: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
          headlineSmall: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
          bodyLarge: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: AppColors.text,
          ),
          bodyMedium: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.text,
          ),
          labelLarge: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.text,
          ),
        );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: AppColors.text,
        onSurface: AppColors.text,
      ),
      cardColor: AppColors.surface,
      cardTheme: const CardThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.text,
        elevation: 1,
        titleTextStyle: textTheme.headlineSmall,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF5F1FB),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primary,
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }
}
