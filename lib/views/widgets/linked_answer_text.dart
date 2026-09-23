import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/subject.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';

/// Hiển thị văn bản trả lời của AI với định dạng Markdown đầy đủ:
/// - In đậm: `**văn bản**` hoặc `__văn bản__`
/// - In nghiêng: `*văn bản*` hoặc `_văn bản_`
/// - Đậm + Nghiêng: `***văn bản***` hoặc `___văn bản___`
/// - Inline Code: `` `mã code` ``
/// - Highlight: `==văn bản==`
/// - Gạch ngang: `~~văn bản~~`
/// - WikiLink: `[[MÃ MÔN]]` hoặc tự động nhận diện mã môn học trong CSDL để tạo liên kết bấm mở note/chi tiết.
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
  /// Giữ theo mã môn và tái dùng qua các lần build để tránh rò rỉ bộ nhớ.
  final Map<String, TapGestureRecognizer> _recognizers = {};

  // Regex nhận diện các token markdown inline
  static final _tokenRegex = RegExp(
    r'(\[\[[^\]]+\]\])' // 1: [[WikiLink]]
    r'|(\*\*\*[^*]+\*\*\*|___[^_]+___)' // 2: ***bold italic***
    r'|(\*\*[^*]+\*\*|__[^_]+__)' // 3: **bold**
    r'|(\*[^*]+\*|(?<=\s|^)_[^_]+_(?=\s|$|[.,!?;:]))' // 4: *italic*
    r'|(==[^=]+==)' // 5: ==highlight==
    r'|(~~[^~]+~~)' // 6: ~~strikethrough~~
    r'|(`[^`]+`)', // 7: `code`
  );

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

  List<InlineSpan> _parseMarkdown(
    String content,
    TextStyle baseStyle,
    Map<String, Subject> byCode,
  ) {
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in _tokenRegex.allMatches(content)) {
      if (match.start > cursor) {
        spans.addAll(_parsePlainWithSubjectLinks(
          content.substring(cursor, match.start),
          baseStyle,
          byCode,
        ));
      }
      cursor = match.end;
      final matchedText = match.group(0)!;

      if (match.group(1) != null) {
        // [[WikiLink]]
        final inner = matchedText.substring(2, matchedText.length - 2);
        final code = inner.split(RegExp(r'[|#]')).first.trim().toUpperCase();
        final subject = byCode[code];
        if (subject != null) {
          spans.add(_buildSubjectLinkSpan(subject, baseStyle));
        } else {
          spans.add(TextSpan(text: inner, style: baseStyle));
        }
      } else if (match.group(2) != null) {
        // ***Bold Italic***
        final inner = matchedText.substring(3, matchedText.length - 3);
        final style = baseStyle.copyWith(
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.italic,
        );
        spans.addAll(_parseMarkdown(inner, style, byCode));
      } else if (match.group(3) != null) {
        // **Bold**
        final inner = matchedText.substring(2, matchedText.length - 2);
        final style = baseStyle.copyWith(
          fontWeight: FontWeight.w700,
        );
        spans.addAll(_parseMarkdown(inner, style, byCode));
      } else if (match.group(4) != null) {
        // *Italic*
        final inner = matchedText.substring(1, matchedText.length - 1);
        final style = baseStyle.copyWith(
          fontStyle: FontStyle.italic,
        );
        spans.addAll(_parseMarkdown(inner, style, byCode));
      } else if (match.group(5) != null) {
        // ==Highlight==
        final inner = matchedText.substring(2, matchedText.length - 2);
        final isDark = AppColors.isDark;
        final style = baseStyle.copyWith(
          backgroundColor: isDark
              ? AppColors.primary.withValues(alpha: 0.28)
              : AppColors.primary.withValues(alpha: 0.15),
          color: isDark ? const Color(0xFFE0D8FF) : AppColors.primaryDark,
          fontWeight: FontWeight.w600,
        );
        spans.addAll(_parseMarkdown(inner, style, byCode));
      } else if (match.group(6) != null) {
        // ~~Strikethrough~~
        final inner = matchedText.substring(2, matchedText.length - 2);
        final style = baseStyle.copyWith(
          decoration: TextDecoration.lineThrough,
        );
        spans.addAll(_parseMarkdown(inner, style, byCode));
      } else if (match.group(7) != null) {
        // `Code`
        final inner = matchedText.substring(1, matchedText.length - 1);
        final isDark = AppColors.isDark;
        spans.add(
          TextSpan(
            text: inner,
            style: baseStyle.copyWith(
              fontFamily: 'monospace',
              fontSize: (baseStyle.fontSize ?? 13.5) * 0.92,
              backgroundColor: isDark
                  ? const Color(0xFF23232C)
                  : const Color(0xFFEBE9F2),
              color: isDark ? const Color(0xFFE2E0EE) : const Color(0xFF2A2838),
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
    }

    if (cursor < content.length) {
      spans.addAll(_parsePlainWithSubjectLinks(
        content.substring(cursor),
        baseStyle,
        byCode,
      ));
    }

    return spans;
  }

  /// Tự động nhận diện mã môn viết rời trong câu (VD: JPD113, PRJ301...) nếu AI không bọc [[ ]]
  List<InlineSpan> _parsePlainWithSubjectLinks(
    String plainText,
    TextStyle baseStyle,
    Map<String, Subject> byCode,
  ) {
    if (plainText.isEmpty) return const [];

    final subjectCodeRegex = RegExp(r'\b([A-Z]{2,4}\d{3}[A-Z0-9_]*)\b');
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in subjectCodeRegex.allMatches(plainText)) {
      final code = match.group(1)!;
      final subject = byCode[code];

      if (subject != null) {
        if (match.start > cursor) {
          spans.add(TextSpan(
            text: plainText.substring(cursor, match.start),
            style: baseStyle,
          ));
        }
        cursor = match.end;
        spans.add(_buildSubjectLinkSpan(subject, baseStyle));
      }
    }

    if (cursor < plainText.length) {
      spans.add(TextSpan(
        text: plainText.substring(cursor),
        style: baseStyle,
      ));
    }

    return spans;
  }

  InlineSpan _buildSubjectLinkSpan(Subject subject, TextStyle baseStyle) {
    return TextSpan(
      text: subject.code,
      style: baseStyle.copyWith(
        color: AppColors.primary,
        fontWeight: FontWeight.w700,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dotted,
        decorationColor: AppColors.primary.withValues(alpha: 0.6),
      ),
      recognizer: _recognizerFor(subject),
    );
  }

  @override
  Widget build(BuildContext context) {
    final byCode = AppState.instance.graph.byCode;
    final spans = _parseMarkdown(widget.text, widget.style, byCode);

    return SelectableText.rich(
      TextSpan(style: widget.style, children: spans),
    );
  }
}
