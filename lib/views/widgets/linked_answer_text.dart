import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/subject.dart';
import '../../services/obsidian_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';

/// Bóc `[[MÃ MÔN]]` trong văn bản do AI sinh ra thành liên kết bấm được, bấm
/// vào là mở thẳng note của môn đó (giống wiki link trong Obsidian).
///
/// Mã nào không có trong CSDL thì để nguyên chữ thường, không tạo link chết.
///
/// Tách ra khỏi `ai_chat_page.dart` để tab Học lực dùng lại được: hai màn hình
/// cùng hiển thị câu trả lời của AI, chép đôi thì sửa một chỗ quên chỗ kia.
class LinkedAnswerText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const LinkedAnswerText({
    super.key,
    required this.text,
    required this.style,
  });

  @override
  State<LinkedAnswerText> createState() => _LinkedAnswerTextState();
}

class _LinkedAnswerTextState extends State<LinkedAnswerText> {
  /// Giữ theo mã môn và tái dùng qua các lần build. Tạo recognizer mới mỗi
  /// lần build sẽ rò rỉ, vì TextSpan không tự huỷ recognizer của nó.
  final Map<String, TapGestureRecognizer> _recognizers = {};

  @override
  void dispose() {
    for (final r in _recognizers.values) {
      r.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _recognizerFor(Subject subject) {
    return _recognizers.putIfAbsent(
      subject.code,
      () => TapGestureRecognizer()
        ..onTap = () => AppState.instance.openNoteTab(subject),
    );
  }

  @override
  Widget build(BuildContext context) {
    final byCode = AppState.instance.graph.byCode;
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in ObsidianService.wikiLinkPattern.allMatches(
      widget.text,
    )) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      cursor = match.end;

      final raw = match.group(1) ?? '';
      // Chấp nhận cả "[[CSD201|Cấu trúc dữ liệu]]" lẫn "[[CSD201#Mục]]".
      final code = raw.split(RegExp(r'[|#]')).first.trim().toUpperCase();
      final subject = byCode[code];

      if (subject == null) {
        spans.add(TextSpan(text: raw));
        continue;
      }
      spans.add(
        TextSpan(
          text: subject.code,
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
          recognizer: _recognizerFor(subject),
        ),
      );
    }

    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return SelectableText.rich(TextSpan(style: widget.style, children: spans));
  }
}
