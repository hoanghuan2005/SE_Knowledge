import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../services/obsidian_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';

/// Hiển thị câu trả lời của AI: render Markdown và biến `[[MÃ MÔN]]` thành
/// liên kết bấm được, bấm vào là mở note của môn đó.
///
/// Trước đây chỗ này vẽ chữ thô, nên `**đậm**`, `### tiêu đề` và gạch đầu
/// dòng của model hiện ra nguyên dấu sao — câu trả lời đầy `*` rất khó đọc.
///
/// Mã nào không có trong CSDL thì để nguyên chữ thường, không tạo link chết.
///
/// Dùng chung cho tab Trợ lý AI, chat theo môn và tab Học lực: ba màn hình
/// cùng hiển thị câu trả lời của AI, chép đôi thì sửa một chỗ quên chỗ kia.
/// Giao thức tự đặt cho liên kết nội bộ. Cố tình không dùng `http` để chắc
/// chắn không có gì mở trình duyệt ngoài.
const String subjectLinkScheme = 'se-subject:';

/// Đổi `[[MÃ MÔN]]` thành liên kết Markdown trỏ vào [subjectLinkScheme].
///
/// Mã không có trong [knownCodes] thì trả về chữ thường, không tạo link chết.
///
/// Hàm thuần, tách khỏi widget để test được mà không cần dựng UI hay CSDL.
String wikiLinksToMarkdown(String text, Set<String> knownCodes) {
  // Mã môn thật có thể chứa `*` và `_` (`SE_COM*2`, `PHE_COM*1`) — đúng hai
  // ký tự Markdown dùng cho in nghiêng/đậm. Không thoát thì nhãn link vỡ.
  String escape(String value) =>
      value.replaceAll('*', r'\*').replaceAll('_', r'\_');

  return text.replaceAllMapped(ObsidianService.wikiLinkPattern, (match) {
    final raw = match.group(1) ?? '';
    // Chấp nhận cả "[[CSD201|Cấu trúc dữ liệu]]" lẫn "[[CSD201#Mục]]".
    final code = raw.split(RegExp(r'[|#]')).first.trim().toUpperCase();
    if (!knownCodes.contains(code)) return escape(raw);
    return '[${escape(code)}]($subjectLinkScheme$code)';
  });
}

class LinkedAnswerText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const LinkedAnswerText({
    super.key,
    required this.text,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final byCode = AppState.instance.graph.byCode;

    return MarkdownBody(
      data: wikiLinksToMarkdown(text, byCode.keys.toSet()),
      selectable: true,
      styleSheet: _sheet(context),
      onTapLink: (label, href, title) {
        if (href == null || !href.startsWith(subjectLinkScheme)) return;
        final subject = byCode[href.substring(subjectLinkScheme.length)];
        if (subject != null) AppState.instance.openNoteTab(subject);
      },
    );
  }

  MarkdownStyleSheet _sheet(BuildContext context) {
    final base = style;
    // Tiêu đề chỉ nhỉnh hơn chữ thường một chút: khung chat hẹp, để cỡ mặc
    // định của theme thì `###` chiếm gần hết bề ngang.
    TextStyle heading(double size) =>
        base.copyWith(fontSize: size, fontWeight: FontWeight.w700);

    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      listBullet: base,
      strong: base.copyWith(fontWeight: FontWeight.w700),
      em: base.copyWith(fontStyle: FontStyle.italic),
      a: base.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
      ),
      code: base.copyWith(
        fontFamily: 'monospace',
        fontSize: base.fontSize == null ? null : base.fontSize! - 0.5,
        backgroundColor: AppColors.background,
      ),
      h1: heading((base.fontSize ?? 13.5) + 3),
      h2: heading((base.fontSize ?? 13.5) + 2),
      h3: heading((base.fontSize ?? 13.5) + 1),
      h4: heading(base.fontSize ?? 13.5),
      blockquoteDecoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
      ),
      pPadding: const EdgeInsets.only(bottom: 2),
    );
  }
}
