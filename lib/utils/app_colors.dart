import 'package:flutter/material.dart';

/// Bảng màu dùng chung. Lấy tông tím than kiểu Obsidian cho đồ thị tri thức.
class AppColors {
  AppColors._();

  // Primary
  static const Color primary = Color(0xFF7C5CFF);
  static const Color primaryDark = Color(0xFF5B3FD1);
  static const Color primaryLight = Color(0xFFE4DCFF);

  // Accent
  static const Color accent = Color(0xFFFF9F1C);

  // Neutral
  static const Color background = Color(0xFFF6F5FB);
  static const Color surface = Colors.white;
  static const Color card = Colors.white;
  static const Color sidebar = Color(0xFF1E1B2E);

  // Text
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B6B80);
  static const Color textHint = Color(0xFF9E9EB3);

  // Status
  static const Color success = Color(0xFF2FB170);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFE2445C);
  static const Color info = Color(0xFF00ACC1);

  // Border & Divider
  static const Color border = Color(0xFFE3E1EC);
  static const Color divider = Color(0xFFEDEBF3);

  // Đồ thị
  static const Color edgePrerequisite = Color(0xFF7C5CFF);
  static const Color edgeRelated = Color(0xFFB9B4CC);

  /// Màu node phân biệt theo kỳ học, để đồ thị đọc được ngay bằng mắt.
  static const List<Color> semesterPalette = [
    Color(0xFF7C5CFF),
    Color(0xFF2FB170),
    Color(0xFF00ACC1),
    Color(0xFFFF9F1C),
    Color(0xFFE2445C),
    Color(0xFF8D6E63),
    Color(0xFF546E7A),
    Color(0xFFAB47BC),
  ];

  static Color forSemester(int semester) {
    if (semester < 1) return semesterPalette.first;
    return semesterPalette[(semester - 1) % semesterPalette.length];
  }
}
