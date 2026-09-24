import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/app_state.dart';
import '../../utils/app_colors.dart';

/// Hiển thị câu trả lời của AI: render Markdown và biến mã môn thành liên kết
/// bấm được, bấm vào là mở note của môn đó.
///
/// Trước đây chỗ này vẽ chữ thô, nên `**đậm**`, `### tiêu đề` và gạch đầu
/// dòng của model hiện ra nguyên dấu sao — câu trả lời đầy `*` rất khó đọc.
///
/// Dùng chung cho tab Trợ lý AI, chat theo môn và tab Học lực: ba màn hình
/// cùng hiển thị câu trả lời của AI, chép đôi thì sửa một chỗ quên chỗ kia.

/// Giao thức tự đặt cho liên kết nội bộ. Cố tình không dùng `http` để chắc
/// chắn không có gì mở trình duyệt ngoài.
const String subjectLinkScheme = 'se-subject:';

/// Một lượt quét duy nhất, phân biệt năm thứ cần xử lý khác nhau.
///
/// Thứ tự các nhánh là thứ tự ưu tiên: khối code và link có sẵn phải được
/// nhận ra **trước** mã môn viết rời, nếu không thì `PRF192` nằm trong
/// `` `PRF192` `` hay trong đích của một link cũng bị bọc thêm lần nữa.
final RegExp _tokenPattern = RegExp(
  r'```[\s\S]*?```' // khối code nhiều dòng
  r'|`[^`\n]*`' // code trong dòng
  r'|\[\[([^\[\]]+?)\]\]' // [[MÃ MÔN]], kèm cả bí danh và neo
  r'|\[[^\]\n]*\]\([^)\n]*\)' // link Markdown đã có sẵn
  r'|(https?://[^\s<>()\[\]]+)' // URL viết trần
  r'|\b([A-Z]{2,4}\d{2,4}[A-Z0-9_]*)\b', // mã môn viết rời
);

/// Dấu câu dính vào cuối URL khi model viết "... xem tại https://a.vn/b."
/// Không cắt thì dấu chấm bị nuốt vào link và bấm ra trang 404.
final RegExp _trailingPunctuation = RegExp(r'[.,;:!?]+$');

/// Đổi mã môn trong [text] thành liên kết Markdown trỏ vào [subjectLinkScheme].
///
/// Nhận hai dạng:
/// - `[[CSD201]]` — dạng prompt dặn model viết ra;
/// - `CSD201` viết rời — lưới an toàn cho lúc model quên bọc ngoặc.
///
/// Mã không có trong [knownCodes] thì giữ nguyên chữ thường, không tạo link
/// chết. Phần trong khối code và trong link đã có sẵn được để yên.
///
/// Hàm thuần, tách khỏi widget để test được mà không cần dựng UI hay CSDL.
String wikiLinksToMarkdown(String text, Set<String> knownCodes) {
  // Mã môn thật có thể chứa `*` và `_` (`SE_COM*2`, `PHE_COM*1`) — đúng hai
  // ký tự Markdown dùng cho in nghiêng/đậm. Không thoát thì nhãn link vỡ.
  String escape(String value) =>
      value.replaceAll('*', r'\*').replaceAll('_', r'\_');

  String link(String code) => '[${escape(code)}]($subjectLinkScheme$code)';

  return text.replaceAllMapped(_tokenPattern, (match) {
    final whole = match.group(0)!;

    final wiki = match.group(1);
    if (wiki != null) {
      // Chấp nhận cả "[[CSD201|Cấu trúc dữ liệu]]" lẫn "[[CSD201#Mục]]".
      final code = wiki.split(RegExp(r'[|#]')).first.trim().toUpperCase();
      return knownCodes.contains(code) ? link(code) : escape(wiki);
    }

    final url = match.group(2);
    if (url != null) {
      final trailing = _trailingPunctuation.stringMatch(url) ?? '';
      final clean = url.substring(0, url.length - trailing.length);
      if (clean.isEmpty) return whole;
      return '[$clean]($clean)$trailing';
    }

    final bare = match.group(3);
    if (bare != null) {
      return knownCodes.contains(bare) ? link(bare) : whole;
    }

    // Khối code hoặc link đã có sẵn — không đụng vào.
    return whole;
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
        if (href == null) return;
        if (href.startsWith(subjectLinkScheme)) {
          final subject = byCode[href.substring(subjectLinkScheme.length)];
          if (subject != null) AppState.instance.openNoteTab(subject);
          return;
        }
        // Link tài liệu học tập trong đề cương (Coursera, trang sách, trang
        // đề cương gốc trên FLM). Mở bằng trình duyệt ngoài — app là desktop
        // local-first, không có WebView và cũng không nên có.
        final uri = Uri.tryParse(href);
        if (uri == null) return;
        if (uri.scheme != 'http' && uri.scheme != 'https') return;
        launchUrl(uri, mode: LaunchMode.externalApplication);
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
      // Gạch chân chấm lấy từ bản của nhánh kia: link mã môn phải nhìn ra
      // được là bấm được, chứ chỉ đổi màu thì dễ tưởng là chữ tô màu.
      a: base.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dotted,
        decorationColor: AppColors.primary.withValues(alpha: 0.6),
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
