import 'package:flutter/material.dart';

import '../models/transcript_entry.dart';

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
  static Color get obsidianCard =>
      isDark ? const Color(0xFF1E1E24) : Colors.white;
  static Color get obsidianAccent => primary;

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
  // Vàng amber chuẩn (0xFFFFC107) quá sáng, chói mắt khi đặt trên nền trắng
  // của Giao diện Sáng — hạ độ sáng, ngả cam cho giao diện sáng để vẫn đọc
  // được mà không cần đổi từng chỗ gọi.
  static Color get warning =>
      isDark ? const Color(0xFFFFC107) : const Color(0xFFB8790A);
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

  // ------------------------------------------------------------------
  // BẢNG MÀU PHÂN LOẠI CHO BIỂU ĐỒ
  // ------------------------------------------------------------------

  /// Bảng màu phân loại 7 ô đã chạy qua bộ kiểm tra mù màu, **đúng thứ tự
  /// này**: hai ô liền nhau trong danh sách phân biệt được cả với người mù
  /// màu đỏ-lục, trên cả nền sáng lẫn nền tối. Đổi thứ tự là mất bảo đảm đó,
  /// nên biểu đồ cột chồng luôn xếp đoạn theo đúng thứ tự ô.
  static const List<Color> _categoricalLight = [
    Color(0xFF2A78D6), // xanh dương
    Color(0xFFEB6834), // cam
    Color(0xFF1BAF7A), // xanh ngọc
    Color(0xFFEDA100), // vàng
    Color(0xFFE87BA4), // hồng
    Color(0xFF008300), // xanh lá
    Color(0xFF4A3AA7), // tím
  ];

  static const List<Color> _categoricalDark = [
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFFC98500),
    Color(0xFFD55181),
    Color(0xFF008300),
    Color(0xFF9085E9),
  ];

  /// Xám "phần còn lại" cho nhóm Khác — không bao giờ là một màu thứ tám.
  static Color get categoricalOther =>
      isDark ? const Color(0xFF6E6E7A) : const Color(0xFFA3A1AE);

  static Color categorical(int slot) {
    final list = isDark ? _categoricalDark : _categoricalLight;
    if (slot < 0 || slot >= list.length) return categoricalOther;
    return list[slot];
  }

  /// Thứ tự nhóm năng lực (theo tiền tố mã môn) trên mọi biểu đồ — cũng là
  /// thứ tự xếp đoạn trong cột chồng.
  static const List<String> domainOrder = [
    'Lập trình',
    'Toán & nền tảng',
    'Kỹ nghệ phần mềm',
    'Cơ sở dữ liệu',
    'Kỹ năng & ngoại ngữ',
    'Chính trị & đạo đức',
  ];

  /// Màu đi theo **tên nhóm**, không theo thứ hạng: lọc bớt nhóm nào thì các
  /// nhóm còn lại vẫn giữ nguyên màu.
  static Color domainColor(String domain) =>
      categorical(domainOrder.indexOf(domain));

  // ------------------------------------------------------------------
  // MÀU TRẠNG THÁI (luôn đi kèm biểu tượng + nhãn, không đứng một mình)
  // ------------------------------------------------------------------

  static const Color statusGood = Color(0xFF0CA30C);
  static const Color statusWarning = Color(0xFFFAB219);
  static const Color statusSerious = Color(0xFFEC835A);
  static const Color statusCritical = Color(0xFFD03B3B);

  /// Chữ màu "đạt" đọc được trên nền sáng (xanh trạng thái quá nhạt để làm
  /// chữ trên nền trắng).
  static Color get statusGoodText =>
      isDark ? statusGood : const Color(0xFF006300);

  // ------------------------------------------------------------------
  // THANG MÀU THEO ĐIỂM
  // ------------------------------------------------------------------

  /// Màu đại diện cho một môn theo điểm và trạng thái học.
  ///
  /// Định nghĩa **một chỗ duy nhất** ở đây vì thang màu này xuất hiện ở ba
  /// nơi: node đồ thị, chip trong panel chi tiết và bảng điểm ở tab Học lực.
  /// Ba chỗ lệch màu nhau thì người dùng không đọc được thang nữa.
  ///
  /// Bản Sáng dùng tông đậm hơn: mấy màu vừa mắt trên nền đen (vàng, xanh lá)
  /// nhạt thếch trên nền trắng.
  static Color gradeColor(double? grade, SubjectStatus status) {
    switch (status) {
      case SubjectStatus.notPassed:
        return isDark ? const Color(0xFFE2445C) : const Color(0xFFC62842);
      case SubjectStatus.studying:
        return isDark ? const Color(0xFFB388FF) : const Color(0xFF6D3FD1);
      case SubjectStatus.notStarted:
      case SubjectStatus.unknown:
        return isDark ? const Color(0xFF6E6E82) : const Color(0xFF9195A6);
      case SubjectStatus.passed:
        break;
    }

    // Đã qua môn nhưng không được chấm điểm (TRS601, LAB211) — không xếp được
    // vào thang nào nên dùng màu trung tính của trạng thái "đã học xong".
    if (grade == null) {
      return isDark ? const Color(0xFF7E8894) : const Color(0xFF6B7280);
    }
    if (grade >= 9.0) {
      return isDark ? const Color(0xFF3DD68C) : const Color(0xFF15803D);
    }
    if (grade >= 8.0) {
      return isDark ? const Color(0xFF4C9AFF) : const Color(0xFF1D4ED8);
    }
    if (grade >= 7.0) {
      return isDark ? const Color(0xFFF2C94C) : const Color(0xFF9A6700);
    }
    return isDark ? const Color(0xFFFF9F1C) : const Color(0xFFC2410C);
  }

  /// Nhãn xếp loại đi kèm [gradeColor], để phần chú giải không chỉ có màu —
  /// chỉ dùng màu thì người mù màu không đọc được thang.
  static String gradeRankLabel(double? grade, SubjectStatus status) {
    switch (status) {
      case SubjectStatus.notPassed:
        return 'Chưa qua';
      case SubjectStatus.studying:
        return 'Đang học';
      case SubjectStatus.notStarted:
      case SubjectStatus.unknown:
        return 'Chưa học';
      case SubjectStatus.passed:
        break;
    }
    if (grade == null) return 'Đã qua (không chấm điểm)';
    if (grade >= 9.0) return 'Xuất sắc';
    if (grade >= 8.0) return 'Giỏi';
    if (grade >= 7.0) return 'Khá';
    return 'Cần cải thiện';
  }
}
