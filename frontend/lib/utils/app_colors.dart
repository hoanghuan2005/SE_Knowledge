import 'package:flutter/material.dart';

/// Định nghĩa các mã màu dùng chung trong toàn bộ ứng dụng.
/// Các thành viên nên dùng màu từ đây thay vì hardcode Color(0xFF...) ở các widget.
class AppColors {
  AppColors._();

  // Primary colors
  static const Color primary = Color(0xFF1E88E5);
  static const Color primaryDark = Color(0xFF1565C0);
  static const Color primaryLight = Color(0xFFBBDEFB);

  // Secondary / Accent colors
  static const Color accent = Color(0xFFFF9800);

  // Neutral colors
  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = Colors.white;
  static const Color card = Colors.white;

  // Text colors
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textHint = Color(0xFF9E9E9E);

  // Status colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFE53935);
  static const Color info = Color(0xFF00ACC1);

  // Border & Divider
  static const Color border = Color(0xFFE0E0E0);
  static const Color divider = Color(0xFFEEEEEE);
}
