import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/models/graph_data.dart';
import 'package:se_knowledge/models/prerequisite.dart';
import 'package:se_knowledge/models/subject.dart';
import 'package:se_knowledge/models/transcript_entry.dart';
import 'package:se_knowledge/services/academic_analytics_service.dart';
import 'package:se_knowledge/services/transcript_parser_service.dart';

/// Kiểm thử phần tính toán học lực.
///
/// Con số quan trọng nhất là GPA: sai một trong năm cái bẫy của file
/// transcript là GPA lệch ngay, nên bài test đầu tiên khoá chặt ba con số
/// 8.10 / 100 tín chỉ / 30 môn của file mẫu.
void main() {
  final analytics = AcademicAnalyticsService.instance;
  final now = DateTime(2026, 9, 1);

  late List<TranscriptEntry> fixtureEntries;

  setUpAll(() async {
    final bytes = await File(
      'test/fixtures/transcript/StudentTranscript_SE193040.xls',
    ).readAsBytes();
    fixtureEntries =
        TranscriptParserService.instance.parseBytes(bytes).entries;
  });

  /// Một dòng điểm dựng tay, đủ trường để đi qua quy tắc tính GPA.
  TranscriptEntry entry(
    String code, {
    double? grade,
    int credits = 3,
    SubjectStatus status = SubjectStatus.passed,
    String semester = 'Fall2024',
    int semesterOrder = 20243,
    bool graduationCondition = false,
    String name = '',
  }) {
    return TranscriptEntry(
      subjectCode: code,
      subjectName: name.isEmpty ? 'Môn $code' : name,
      term: 1,
      semesterLabel: semester,
      semesterOrder: semesterOrder,
      credits: credits,
      grade: grade,
      status: status,
      isGraduationCondition: graduationCondition,
      countsTowardGpa: TranscriptEntry.countsTowardGpaByDefault(
        status: status,
        grade: grade,
        credits: credits,
        isGraduationCondition: graduationCondition,
      ),
      importedAt: now,
    );
  }

  Subject subject(int id, String code, {String name = ''}) => Subject(
    id: id,
    code: code,
    name: name.isEmpty ? 'Môn $code' : name,
    createdAt: now,
    updatedAt: now,
  );

  /// `prereqId -> id`: học [prereqId] xong mới học được [id].
  Prerequisite edge(int prereqId, int id) =>
      Prerequisite(subjectId: id, prerequisiteId: prereqId);

  group('GPA trên file mẫu', () {
    test('ra đúng 8.10 / 100 tín chỉ / 30 môn', () {
      final profile = analytics.analyze(fixtureEntries, GraphData.empty);
      expect(profile.gpa, 8.10);
      expect(profile.totalCredits, 100);
      expect(profile.gpaSubjectCount, 30);
      expect(profile.gpaLabel, '8.10');
    });

    test('bỏ đúng 6 dòng có cờ * (môn điều kiện tốt nghiệp)', () {
      final counted = analytics.effectiveGpaEntries(fixtureEntries);
      final codes = counted.map((e) => e.subjectCode).toSet();
      for (final code in [
        'VOV114',
        'VOV124',
        'VOV134',
        'OTP101',
        'LAB211',
        'IOT102',
      ]) {
        expect(codes, isNot(contains(code)), reason: '$code có cờ *');
      }
    });

    test('bỏ dòng Passed không có điểm và dòng 0 tín chỉ', () {
      final counted = analytics.effectiveGpaEntries(fixtureEntries);
      final codes = counted.map((e) => e.subjectCode).toSet();
      // TRS601 và LAB211 qua môn nhưng không được chấm điểm.
      expect(codes, isNot(contains('TRS601')));
      expect(codes, isNot(contains('LAB211')));
      // Bảng tiếng Anh dự bị có điểm nhưng 0 tín chỉ.
      expect(codes, isNot(contains('TRS403')));
      expect(codes, isNot(contains('TRS501')));
      expect(counted.every((e) => e.credits > 0), isTrue);
    });

    test('đếm trạng thái theo mã môn', () {
      final profile = analytics.analyze(fixtureEntries, GraphData.empty);
      // 37 dòng Passed của bảng chính + 2 dòng của bảng tiếng Anh dự bị.
      expect(profile.passedCount, 39);
      expect(profile.studyingCount, 5);
      expect(profile.notStartedCount, 4);
    });
  });

  group('học lại', () {
    test('chỉ lần qua môn mới nhất được cộng vào GPA', () {
      final entries = [
        entry('CSD201', grade: 5.0, semester: 'Spring2024', semesterOrder: 20241),
        entry('CSD201', grade: 9.0, semester: 'Fall2024', semesterOrder: 20243),
      ];

      final counted = analytics.effectiveGpaEntries(entries);
      expect(counted, hasLength(1));
      expect(counted.single.grade, 9.0);

      final profile = analytics.analyze(entries, GraphData.empty);
      expect(profile.gpa, 9.0);
      expect(profile.totalCredits, 3);
      // Hai dòng cùng một mã môn vẫn chỉ là một môn đã qua.
      expect(profile.passedCount, 1);
    });
  });

  group('nhóm năng lực', () {
    test('dưới 3 môn thì không kết luận', () {
      final entries = [
        // Hai môn tiếng Nhật điểm cao — chưa đủ để nói "giỏi ngoại ngữ".
        entry('JPD113', grade: 9.5),
        entry('JPD123', grade: 9.5),
        // Ba môn lập trình cho nhóm này đủ điều kiện kết luận.
        entry('PRF192', grade: 7.0),
        entry('PRO192', grade: 7.0),
        entry('CSD201', grade: 7.0),
      ];

      final profile = analytics.analyze(entries, GraphData.empty);
      final jp = profile.byDomain.firstWhere(
        (d) => d.name == 'Kỹ năng & ngoại ngữ',
      );
      final code = profile.byDomain.firstWhere((d) => d.name == 'Lập trình');

      expect(jp.subjectCount, 2);
      expect(jp.isSignificant, isFalse);
      expect(jp.isStrong, isFalse, reason: 'chưa đủ dữ liệu thì không kết luận');

      expect(code.subjectCount, 3);
      expect(code.isSignificant, isTrue);
      // Chỉ nhóm đủ dữ liệu mới được đưa ra kết luận mạnh/yếu.
      expect(profile.significantDomains.map((d) => d.name), ['Lập trình']);
    });

    test('delta so với GPA tổng đổi dấu đúng chiều', () {
      final entries = [
        entry('PRF192', grade: 6.0),
        entry('PRO192', grade: 6.0),
        entry('CSD201', grade: 6.0),
        entry('MAE101', grade: 9.0),
        entry('MAD101', grade: 9.0),
        entry('MAS291', grade: 9.0),
      ];
      final profile = analytics.analyze(entries, GraphData.empty);
      expect(profile.gpa, 7.5);

      final coding = profile.byDomain.firstWhere((d) => d.name == 'Lập trình');
      final math = profile.byDomain.firstWhere(
        (d) => d.name == 'Toán & nền tảng',
      );
      expect(coding.delta, -1.5);
      expect(coding.isWeak, isTrue);
      expect(math.delta, 1.5);
      expect(math.isStrong, isTrue);
      expect(math.deltaLabel, '+1.5');
    });
  });

  group('cảnh báo rủi ro', () {
    /// Đồ thị hai môn: A là tiên quyết của B.
    GraphData twoNodeGraph() => GraphData(
      subjects: [subject(1, 'AAA101'), subject(2, 'BBB201')],
      edges: [edge(1, 2)],
    );

    test('nền yếu (6.0) mở ra môn chưa học thì phải cảnh báo', () {
      final entries = [
        entry('AAA101', grade: 6.0),
        entry('BBB201', status: SubjectStatus.notStarted, semester: ''),
      ];
      final profile = analytics.analyze(entries, twoNodeGraph());

      expect(profile.risks, hasLength(1));
      final risk = profile.risks.single;
      expect(risk.kind, RiskKind.weakFoundation);
      expect(risk.subjectCode, 'BBB201');
      expect(risk.prerequisiteCode, 'AAA101');
      expect(risk.prerequisiteGrade, 6.0);
      // Câu cảnh báo có sẵn [[MÃ MÔN]] để giao diện bóc thành liên kết.
      expect(risk.message, contains('[[BBB201]]'));
      expect(risk.message, contains('[[AAA101]]'));
    });

    test('nền vững (9.0) thì không cảnh báo gì', () {
      final entries = [
        entry('AAA101', grade: 9.0),
        entry('BBB201', status: SubjectStatus.notStarted, semester: ''),
      ];
      final profile = analytics.analyze(entries, twoNodeGraph());
      expect(profile.risks, isEmpty);
    });

    test('môn tiên quyết chưa qua thì báo chặn lộ trình', () {
      final entries = [
        entry('AAA101', status: SubjectStatus.notStarted, semester: ''),
        entry('BBB201', status: SubjectStatus.notStarted, semester: ''),
      ];
      final profile = analytics.analyze(entries, twoNodeGraph());
      expect(profile.risks, hasLength(1));
      expect(profile.risks.single.kind, RiskKind.blockedPath);
    });

    test('môn đã qua rồi thì nền yếu không còn là rủi ro phía trước', () {
      final entries = [
        entry('AAA101', grade: 6.0),
        entry('BBB201', grade: 8.0),
      ];
      final profile = analytics.analyze(entries, twoNodeGraph());
      expect(profile.risks, isEmpty);
    });

    test('nền yếu mở ra nhiều môn thì xếp trên nền yếu mở ra ít môn', () {
      final graph = GraphData(
        subjects: [
          subject(1, 'HUB101'), // nền yếu, mở ra 2 môn
          subject(2, 'LEAF101'), // nền yếu, mở ra 1 môn
          subject(3, 'AFTER301'),
          subject(4, 'AFTER302'),
          subject(5, 'AFTER303'),
        ],
        edges: [edge(1, 3), edge(1, 4), edge(2, 5)],
      );
      final entries = [
        entry('HUB101', grade: 6.5),
        entry('LEAF101', grade: 6.5),
        entry('AFTER301', status: SubjectStatus.notStarted, semester: ''),
        entry('AFTER302', status: SubjectStatus.notStarted, semester: ''),
        entry('AFTER303', status: SubjectStatus.notStarted, semester: ''),
      ];

      final profile = analytics.analyze(entries, graph);
      expect(profile.risks, hasLength(3));
      expect(profile.risks.first.prerequisiteCode, 'HUB101');
      expect(profile.risks.last.prerequisiteCode, 'LEAF101');
    });
  });

  group('xu hướng', () {
    test('dưới 4 kỳ dữ liệu thì trả unknown', () {
      final entries = [
        entry('AAA101', grade: 7.0, semester: 'Fall2023', semesterOrder: 20233),
        entry('BBB101', grade: 8.0, semester: 'Spring2024', semesterOrder: 20241),
        entry('CCC101', grade: 9.0, semester: 'Summer2024', semesterOrder: 20242),
      ];
      final profile = analytics.analyze(entries, GraphData.empty);
      expect(profile.bySemester, hasLength(3));
      expect(profile.trend, TrendDirection.unknown);
    });

    test('ba kỳ gần nhất cao hơn hẳn thì là đi lên', () {
      final entries = [
        entry('AAA101', grade: 6.0, semester: 'Fall2023', semesterOrder: 20233),
        entry('BBB101', grade: 8.0, semester: 'Spring2024', semesterOrder: 20241),
        entry('CCC101', grade: 8.0, semester: 'Summer2024', semesterOrder: 20242),
        entry('DDD101', grade: 8.0, semester: 'Fall2024', semesterOrder: 20243),
      ];
      final profile = analytics.analyze(entries, GraphData.empty);
      expect(profile.bySemester.map((s) => s.label).toList(), [
        'Fall2023',
        'Spring2024',
        'Summer2024',
        'Fall2024',
      ]);
      expect(profile.trend, TrendDirection.improving);
    });

    test('ba kỳ gần nhất thấp hơn hẳn thì là đi xuống', () {
      final entries = [
        entry('AAA101', grade: 9.0, semester: 'Fall2023', semesterOrder: 20233),
        entry('BBB101', grade: 6.0, semester: 'Spring2024', semesterOrder: 20241),
        entry('CCC101', grade: 6.0, semester: 'Summer2024', semesterOrder: 20242),
        entry('DDD101', grade: 6.0, semester: 'Fall2024', semesterOrder: 20243),
      ];
      expect(
        analytics.analyze(entries, GraphData.empty).trend,
        TrendDirection.declining,
      );
    });
  });

  group('trường hợp biên', () {
    test('danh sách rỗng trả GPA 0, không chia cho 0, không ném lỗi', () {
      final profile = analytics.analyze(const [], GraphData.empty);
      expect(profile.gpa, 0);
      expect(profile.totalCredits, 0);
      expect(profile.gpaSubjectCount, 0);
      expect(profile.risks, isEmpty);
      expect(profile.trend, TrendDirection.unknown);
      expect(profile.isEmpty, isTrue);
    });

    test('toàn môn chưa học vẫn ra GPA 0 chứ không NaN', () {
      final entries = [
        entry('AAA101', status: SubjectStatus.notStarted, semester: ''),
        entry('BBB101', status: SubjectStatus.studying, semester: ''),
      ];
      final profile = analytics.analyze(entries, GraphData.empty);
      expect(profile.gpa, 0);
      expect(profile.gpa.isNaN, isFalse);
      expect(profile.totalCredits, 0);
    });

    test('mã môn lạ rơi vào nhóm "Khác" chứ không mất', () {
      expect(analytics.domainOf('ZZZ999'), 'Khác');
      expect(analytics.domainOf('SSL101C'), 'Kỹ năng & ngoại ngữ');
      expect(analytics.domainOf('WDU203C'), 'Lập trình');
    });
  });

  test('renderForPrompt dẫn số liệu thật, không đưa sẵn kết luận', () {
    final profile = analytics.analyze(fixtureEntries, GraphData.empty);
    final text = profile.renderForPrompt();
    expect(text, contains('GPA tích luỹ 8.10 trên 100 tín chỉ'));
    // Kỳ đầu tiên có môn tính GPA là Summer2024: Fall2023 chỉ có Vovinam và
    // OTP101 — đều mang cờ (*) nên không vào GPA, cũng không lên biểu đồ.
    expect(text, contains('Summer2024'));
    expect(text, contains('Các môn điểm thấp nhất'));
  });
}
