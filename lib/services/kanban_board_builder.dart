import 'dart:convert';

import '../models/subject.dart';
import '../models/transcript_entry.dart';
import 'obsidian_service.dart';

/// Sinh file `.md` theo **định dạng board** của plugin Obsidian Kanban.
///
/// Mỗi học kỳ là một cột (`## HK1`), mỗi môn là một thẻ (`- [ ] [[PRF192]]`).
/// Mở file trong Obsidian có cài plugin Kanban là thấy đúng bảng HK1 → HK9
/// như trong app; không cài plugin thì nó vẫn là một danh sách Markdown đọc
/// được, và mọi `[[MÃ MÔN]]` vẫn là link tới ghi chú của môn.
///
/// Định dạng lấy theo mã nguồn của plugin: front matter `kanban-plugin: board`,
/// khối cài đặt JSON bọc trong `%% kanban:settings ... %%` ở cuối file.
/// `list-collapse` giữ đúng các cột đang thu gọn trong app, `tag-colors` tô
/// màu thẻ theo trạng thái điểm — xanh là đạt mục tiêu, đỏ là chưa qua.
class KanbanBoardBuilder {
  KanbanBoardBuilder._();

  static const String tagReached = '#dat-muc-tieu';
  static const String tagImprove = '#can-cai-thien';
  static const String tagFailed = '#chua-qua';
  static const String tagStudying = '#dang-hoc';
  static const String tagNotStarted = '#chua-hoc';

  /// Màu nền thẻ theo tag, cùng bảng trạng thái với giao diện app.
  static const List<Map<String, String>> tagColors = [
    {
      'tagKey': tagReached,
      'color': '',
      'backgroundColor': 'rgba(12, 163, 12, 0.22)',
    },
    {
      'tagKey': tagImprove,
      'color': '',
      'backgroundColor': 'rgba(236, 131, 90, 0.25)',
    },
    {
      'tagKey': tagFailed,
      'color': '',
      'backgroundColor': 'rgba(208, 59, 59, 0.28)',
    },
    {
      'tagKey': tagStudying,
      'color': '',
      'backgroundColor': 'rgba(124, 92, 255, 0.22)',
    },
  ];

  /// Tên file mặc định: `BIT_SE_K18C_Board.md`.
  static String fileNameFor(String curriculumCode) {
    final safe = curriculumCode.trim().isEmpty
        ? 'CURRICULUM'
        : curriculumCode.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    return '${safe}_Board.md';
  }

  static String build({
    required String curriculumCode,
    String curriculumName = '',
    required Map<int, List<Subject>> semesters,
    Map<String, TranscriptEntry> gradeByCode = const {},
    double? targetGpa,
    Set<int> collapsedSemesters = const {},
    DateTime? generatedAt,
  }) {
    final terms = semesters.keys.toList()..sort();
    final date = (generatedAt ?? DateTime.now()).toIso8601String().substring(
      0,
      10,
    );

    final sb = StringBuffer()
      ..writeln('---')
      ..writeln()
      ..writeln('kanban-plugin: board')
      ..writeln('curriculum: ${_yaml(curriculumCode)}');
    if (curriculumName.trim().isNotEmpty) {
      sb.writeln('name: ${_yaml(curriculumName.trim())}');
    }
    if (targetGpa != null) {
      sb.writeln('target-gpa: ${targetGpa.toStringAsFixed(1)}');
    }
    sb
      ..writeln('generated: $date')
      ..writeln('tags: [board, curriculum]')
      ..writeln()
      ..writeln('---')
      ..writeln();

    for (final term in terms) {
      final subjects = [...semesters[term]!]
        ..sort((a, b) => a.code.compareTo(b.code));
      final credits = subjects.fold<int>(0, (s, x) => s + x.credits);
      sb
        ..writeln('## ${laneTitle(term)} · $credits TC')
        ..writeln();
      for (final s in subjects) {
        sb.writeln(_card(s, gradeByCode[s.code.toUpperCase()], targetGpa));
      }
      sb
        ..writeln()
        ..writeln();
    }

    final settings = {
      'kanban-plugin': 'board',
      'list-collapse': [for (final t in terms) collapsedSemesters.contains(t)],
      'show-checkboxes': true,
      'tag-colors': tagColors,
    };
    sb
      ..writeln('%% kanban:settings')
      ..writeln('```')
      ..writeln(jsonEncode(settings))
      ..writeln('```')
      ..writeln('%%');
    return sb.toString();
  }

  /// Link tới ghi chú của môn. Mã có ký tự Windows cấm dùng trong tên file
  /// (`PHE_COM*1`) được ghi ra Vault dưới tên đã gọt (`PHE_COM-1.md`), nên
  /// link phải trỏ vào tên file đó và giữ mã gốc làm chữ hiển thị.
  static String wikiLink(String code) {
    final stem = ObsidianService.sanitizeFileStem(code);
    return stem == code ? '[[$code]]' : '[[$stem|$code]]';
  }

  /// Tên cột: kỳ 0 là kỳ dự bị/định hướng của FPTU.
  static String laneTitle(int term) => term <= 0 ? 'HK0 · Dự bị' : 'HK$term';

  static String _card(Subject s, TranscriptEntry? grade, double? target) {
    final done = grade?.status == SubjectStatus.passed;
    final parts = <String>[
      '${wikiLink(s.code)} ${_inline(s.name)}',
      '${s.credits} TC',
      if (grade?.grade != null) 'điểm **${grade!.displayGrade}**',
    ];
    final tag = _tagFor(grade, target);
    return '- [${done ? 'x' : ' '}] ${parts.join(' · ')}'
        '${tag == null ? '' : ' $tag'}';
  }

  static String? _tagFor(TranscriptEntry? e, double? target) {
    if (e == null) return tagNotStarted;
    switch (e.status) {
      case SubjectStatus.notPassed:
        return tagFailed;
      case SubjectStatus.studying:
        return tagStudying;
      case SubjectStatus.notStarted:
      case SubjectStatus.unknown:
        return tagNotStarted;
      case SubjectStatus.passed:
        final g = e.grade;
        if (g == null || target == null) return null;
        return g >= target ? tagReached : tagImprove;
    }
  }

  /// Tên môn nằm trên một dòng thẻ: bỏ xuống dòng và dấu `_` nối hai thứ
  /// tiếng của FAP, để thẻ không bị vỡ thành nhiều dòng.
  static String _inline(String name) =>
      name.replaceAll('_', ' — ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _yaml(String value) {
    final v = value.replaceAll('"', r'\"');
    return RegExp(r'[:#\[\]{},&*!|>%@`]').hasMatch(v) ? '"$v"' : v;
  }
}
