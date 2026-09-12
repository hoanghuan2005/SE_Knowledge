import 'package:flutter/material.dart';

/// Bảng màu dùng chung hỗ trợ chuyển đổi giao diện Dark / Light.
/// Mặc định là giao diện đen (Obsidian Dark Theme) đồng bộ toàn bộ app.
class AppColors {
  AppColors._();

  /// Trạng thái theme hiện tại (đồng bộ với AppState). Mặc định là true (Dark).
  static bool isDark = true;

  // Primary
  static const Color primary = Color(0xFF7C5CFF);
  static const Color primaryDark = Color(0xFF5B3FD1);
  static const Color primaryLight = Color(0xFFE4DCFF);

  // Accent
  static const Color accent = Color(0xFFFF9F1C);

  // Static Constants Dark
  static const Color obsidianRibbonDark = Color(0xFF16161A);
  static const Color obsidianSidebarDark = Color(0xFF1E1E24);
  static const Color obsidianWorkspaceDark = Color(0xFF141416);
  static const Color obsidianBorderDark = Color(0xFF2B2B32);
  static const Color obsidianHoverDark = Color(0xFF282830);
  static const Color obsidianActiveDark = Color(0xFF32323D);
  static const Color obsidianTextDark = Color(0xFFDCDDDE);
  static const Color obsidianTextMutedDark = Color(0xFF8A8A93);

  // Static Constants Light
  static const Color obsidianRibbonLight = Color(0xFFE5E3EC);
  static const Color obsidianSidebarLight = Color(0xFFF0EFF5);
  static const Color obsidianWorkspaceLight = Color(0xFFF8F7FC);
  static const Color obsidianBorderLight = Color(0xFFDFDDE8);
  static const Color obsidianHoverLight = Color(0xFFE2E0EC);
  static const Color obsidianActiveLight = Color(0xFFDCD8E8);
  static const Color obsidianTextLight = Color(0xFF1A1A2E);
  static const Color obsidianTextMutedLight = Color(0xFF6B6B80);

  // Obsidian Theme Palette (Adaptive theo Theme)
  static Color get obsidianRibbon =>
      isDark ? obsidianRibbonDark : obsidianRibbonLight;
  static Color get obsidianSidebar =>
      isDark ? obsidianSidebarDark : obsidianSidebarLight;
  static Color get obsidianWorkspace =>
      isDark ? obsidianWorkspaceDark : obsidianWorkspaceLight;
  static Color get obsidianBorder =>
      isDark ? obsidianBorderDark : obsidianBorderLight;
  static Color get obsidianHover =>
      isDark ? obsidianHoverDark : obsidianHoverLight;
  static Color get obsidianActive =>
      isDark ? obsidianActiveDark : obsidianActiveLight;
  static Color get obsidianText =>
      isDark ? obsidianTextDark : obsidianTextLight;
  static Color get obsidianTextMuted =>
      isDark ? obsidianTextMutedDark : obsidianTextMutedLight;

  // Neutral (Adaptive theo Theme)
  static Color get background =>
      isDark ? const Color(0xFF141416) : const Color(0xFFF8F7FC);
  static Color get surface =>
      isDark ? const Color(0xFF1E1E24) : Colors.white;
  static Color get card =>
      isDark ? const Color(0xFF1E1E24) : Colors.white;
  static Color get sidebar =>
      isDark ? const Color(0xFF1E1E24) : const Color(0xFFF0EFF5);

  // Shell components (Map trực tiếp vào Obsidian Palette)
  static Color get shellRibbon => obsidianRibbon;
  static Color get shellSidebar => obsidianSidebar;
  static Color get shellWorkspace => obsidianWorkspace;
  static Color get shellBorder => obsidianBorder;
  static Color get shellHover => obsidianHover;
  static Color get shellActive => obsidianActive;
  static Color get shellText => obsidianText;
  static Color get shellTextMuted => obsidianTextMuted;

  // Text (Adaptive theo Theme)
  static Color get textPrimary =>
      isDark ? const Color(0xFFEEEEF2) : const Color(0xFF1A1A2E);
  static Color get textSecondary =>
      isDark ? const Color(0xFF9E9EB3) : const Color(0xFF6B6B80);
  static Color get textHint =>
      isDark ? const Color(0xFF6E6E82) : const Color(0xFF9E9EB3);

  // Status
  static const Color success = Color(0xFF2FB170);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFE2445C);
  static const Color info = Color(0xFF00ACC1);

  // Border & Divider (Adaptive theo Theme)
  static Color get border => obsidianBorder;
  static Color get divider =>
      isDark ? const Color(0xFF262630) : const Color(0xFFEDEBF3);

  // Đồ thị
  static const Color edgePrerequisite = Color(0xFF7C5CFF);
  static Color get edgeRelated =>
      isDark ? const Color(0xFF4A4A58) : const Color(0xFFB9B4CC);

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
