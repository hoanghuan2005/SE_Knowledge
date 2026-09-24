import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_constants.dart';

/// ThemeData cho ứng dụng desktop hỗ trợ Dark Theme (Obsidian) và Light Theme.
class AppTheme {
  AppTheme._();

  /// Giao diện đen mặc định (Obsidian Dark Theme)
  static ThemeData get darkTheme {
    const scheme = ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: Colors.black,
      surface: AppColors.obsidianSidebarDark,
      onSurface: AppColors.obsidianTextDark,
      error: AppColors.error,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.obsidianWorkspaceDark,
      visualDensity: VisualDensity.compact,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.obsidianSidebarDark,
        foregroundColor: AppColors.obsidianTextDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF262630),
        thickness: 1,
        space: 1,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.obsidianSidebarDark,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF202028),
        disabledColor: const Color(0xFF16161A),
        selectedColor: AppColors.primary.withValues(alpha: 0.3),
        secondarySelectedColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: const TextStyle(
          color: AppColors.obsidianTextDark,
          fontSize: 12,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
        brightness: Brightness.dark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.obsidianBorderDark),
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.obsidianSidebarDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppConstants.borderRadius),
          ),
          side: BorderSide(color: AppColors.obsidianBorderDark),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.obsidianTextDark,
          side: const BorderSide(color: AppColors.obsidianBorderDark),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF16161A),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        hintStyle: const TextStyle(
          color: AppColors.obsidianTextMutedDark,
          fontSize: 12.5,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.obsidianBorderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.obsidianBorderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Giao diện sáng (Light Theme)
  static ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: Colors.white,
      error: AppColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF6F5FB),
      visualDensity: VisualDensity.compact,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF1A1A2E),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1A1A2E),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFEDEBF3),
        thickness: 1,
        space: 1,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: const TextStyle(
          color: Color(0xFF1A1A2E),
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE3E1EC)),
        ),
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppConstants.borderRadius),
          ),
          side: BorderSide(color: Color(0xFFE3E1EC)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF1A1A2E),
          side: const BorderSide(color: Color(0xFFE3E1EC)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE3E1EC)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE3E1EC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
