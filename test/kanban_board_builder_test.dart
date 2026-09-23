import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/models/subject.dart';
import 'package:se_knowledge/models/transcript_entry.dart';
import 'package:se_knowledge/services/kanban_board_builder.dart';

/// Kiểm thử file board `.md` cho plugin Obsidian Kanban.
void main() {
  final now = DateTime(2026, 9, 23);

  Subject subject(String code, int semester, {int credits = 3}) => Subject(
    id: code.hashCode,
    code: code,
    name: 'Môn $code',
    semester: semester,
    credits: credits,
    createdAt: now,
    updatedAt: now,
  );

  TranscriptEntry grade(String code, double? g, SubjectStatus status) =>
      TranscriptEntry(
        subjectCode: code,
        credits: 3,
        grade: g,
        status: status,
        countsTowardGpa: status == SubjectStatus.passed && g != null,
        importedAt: now,
      );

  final semesters = {
    2: [subject('MAD101', 2), subject('NWC204', 2)],
    1: [subject('PRF192', 1), subject('MAE101', 1)],
  };
  final grades = {
    'PRF192': grade('PRF192', 8.5, SubjectStatus.passed),
    'MAE101': grade('MAE101', 6.5, SubjectStatus.passed),
    'MAD101': grade('MAD101', 3.0, SubjectStatus.notPassed),
  };

  String build({Set<int> collapsed = const {}}) => KanbanBoardBuilder.build(
    curriculumCode: 'BIT_SE_K18C',
    curriculumName: 'Software Engineering',
    semesters: semesters,
    gradeByCode: grades,
    targetGpa: 8.0,
    collapsedSemesters: collapsed,
    generatedAt: now,
  );

  test('front matter đánh dấu đây là board của plugin Kanban', () {
    final md = build();
    expect(md.startsWith('---\n\nkanban-plugin: board\n'), isTrue);
    expect(md, contains('curriculum: BIT_SE_K18C'));
    expect(md, contains('target-gpa: 8.0'));
  });

  test('mỗi học kỳ là một cột, xếp theo thứ tự kỳ', () {
    final md = build();
    final lanes = RegExp(
      r'^## (.+)$',
      multiLine: true,
    ).allMatches(md).map((m) => m.group(1)).toList();
    expect(lanes, ['HK1 · 6 TC', 'HK2 · 6 TC']);
  });

  test('môn đã qua được tích, thẻ gắn tag màu theo mục tiêu', () {
    final md = build();
    expect(
      md,
      contains(
        '- [x] [[PRF192]] Môn PRF192 · 3 TC · điểm **8.5** '
        '${KanbanBoardBuilder.tagReached}',
      ),
    );
    expect(
      md,
      contains(
        '- [x] [[MAE101]] Môn MAE101 · 3 TC · điểm **6.5** '
        '${KanbanBoardBuilder.tagImprove}',
      ),
    );
    expect(
      md,
      contains(
        '- [ ] [[MAD101]] Môn MAD101 · 3 TC · điểm **3** '
        '${KanbanBoardBuilder.tagFailed}',
      ),
    );
    expect(
      md,
      contains(
        '- [ ] [[NWC204]] Môn NWC204 · 3 TC '
        '${KanbanBoardBuilder.tagNotStarted}',
      ),
    );
  });

  test('khối cài đặt giữ cột thu gọn và bảng màu tag', () {
    final md = build(collapsed: {2});
    final match = RegExp(r'%% kanban:settings\n```\n(.+)\n```\n%%')
        .firstMatch(md);
    expect(match, isNotNull);
    final settings = jsonDecode(match!.group(1)!) as Map<String, dynamic>;
    expect(settings['kanban-plugin'], 'board');
    expect(settings['list-collapse'], [false, true]);
    final tags = (settings['tag-colors'] as List)
        .map((e) => (e as Map)['tagKey'])
        .toList();
    expect(tags, contains(KanbanBoardBuilder.tagReached));
    expect(tags, contains(KanbanBoardBuilder.tagFailed));
  });

  test('mã có ký tự cấm trỏ vào đúng tên file đã gọt', () {
    expect(KanbanBoardBuilder.wikiLink('PRF192'), '[[PRF192]]');
    expect(KanbanBoardBuilder.wikiLink('PHE_COM*1'), '[[PHE_COM-1|PHE_COM*1]]');
  });

  test('tên file an toàn cho Windows', () {
    expect(
      KanbanBoardBuilder.fileNameFor('BIT_SE_K18C'),
      'BIT_SE_K18C_Board.md',
    );
    expect(KanbanBoardBuilder.fileNameFor('a/b:c'), 'a_b_c_Board.md');
  });
}
