import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/models/transcript_entry.dart';
import 'package:se_knowledge/services/transcript_parser_service.dart';

/// Kiểm thử bộ bóc tách transcript trên **file thật** tải từ FAP.
///
/// Không mở CSDL, không cần Visual Studio: parser là Dart thuần nên chỉ cần
/// đọc file fixture rồi so kết quả.
void main() {
  final parser = TranscriptParserService.instance;
  late Uint8List bytes;
  late TranscriptParseResult result;

  setUpAll(() async {
    bytes = await File(
      'test/fixtures/transcript/StudentTranscript_SE193040.xls',
    ).readAsBytes();
    result = parser.parseBytes(
      bytes,
      fileName: 'StudentTranscript_SE193040.xls',
    );
  });

  group('giải mã file', () {
    test('nhận ra BOM UTF-16LE và đọc ra HTML đọc được', () {
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xFE);

      final html = parser.decodeBytes(bytes);
      expect(html, contains('Subject Code'));
      // Đọc đúng encoding thì tiếng Việt có dấu mới hiện ra nguyên vẹn.
      expect(html, contains('Môn điều kiện tốt nghiệp'));
    });

    test('mã sinh viên bóc được từ tên file', () {
      expect(result.studentCode, 'SE193040');
    });
  });

  group('đọc bảng', () {
    test('đủ 46 dòng bảng chính + 2 dòng bảng tiếng Anh dự bị', () {
      expect(result.entries, hasLength(48));

      // Bảng phụ không có cột Term nên hai dòng này là dấu nhận biết chắc chắn.
      final prep = result.entries.where((e) => e.term == null).toList();
      expect(prep.map((e) => e.subjectCode).toList(), ['TRS403', 'TRS501']);
    });

    test('đếm đúng trạng thái trong bảng chính', () {
      final main = result.entries.where((e) => e.term != null).toList();
      expect(main, hasLength(46));
      expect(
        main.where((e) => e.status == SubjectStatus.passed).length,
        37,
      );
      expect(
        main.where((e) => e.status == SubjectStatus.studying).length,
        5,
      );
      expect(
        main.where((e) => e.status == SubjectStatus.notStarted).length,
        4,
      );
    });

    test('dòng 10 ô (Studying) không làm lệch cột', () {
      final jpd326 = result.entries.firstWhere(
        (e) => e.subjectCode == 'JPD326',
      );
      // Thiếu ô cờ `*` ở cuối, nhưng 10 ô đầu vẫn phải về đúng chỗ.
      expect(jpd326.status, SubjectStatus.studying);
      expect(jpd326.term, 8);
      expect(jpd326.semesterLabel, isEmpty);
      expect(jpd326.subjectName, 'Japanese Intermediate 2-B2.1');
      expect(jpd326.rawPrerequisite, 'JPD316/JPD322');
      expect(jpd326.grade, isNull);
      expect(jpd326.credits, 0);
      expect(jpd326.isGraduationCondition, isFalse);
    });

    test('dòng chú thích (*) bị bỏ qua, không sinh entry rác', () {
      expect(
        result.entries.any((e) => e.subjectCode.contains('(*)')),
        isFalse,
      );
      expect(
        result.entries.any((e) => e.subjectName.contains('tích lũy')),
        isFalse,
      );
      // Ghi chú của FAP không phải dòng hỏng nên cũng không sinh cảnh báo.
      expect(result.warnings, isEmpty);
    });

    test('mã môn chữ thường được chuẩn hoá về chữ hoa', () {
      expect(
        result.entries.any((e) => e.subjectCode == 'SSL101C'),
        isTrue,
      );
      expect(
        result.entries.any((e) => e.subjectCode == 'WED201C'),
        isTrue,
      );
      // Không còn mã nào lẫn chữ thường.
      for (final e in result.entries) {
        expect(e.subjectCode, e.subjectCode.toUpperCase());
      }
    });

    test('Credit rỗng ra 0, Grade "10" ra 10.0', () {
      final mln122 = result.entries.firstWhere(
        (e) => e.subjectCode == 'MLN122',
      );
      expect(mln122.credits, 0);

      final wdu = result.entries.firstWhere(
        (e) => e.subjectCode == 'WDU203C',
      );
      expect(wdu.grade, 10.0);
      expect(wdu.displayGrade, '10');
    });

    test('cờ * nhận đúng 6 dòng môn điều kiện tốt nghiệp', () {
      final flagged = result.entries
          .where((e) => e.isGraduationCondition)
          .map((e) => e.subjectCode)
          .toList();
      expect(flagged, hasLength(6));
      expect(
        flagged,
        containsAll(['VOV114', 'VOV124', 'VOV134', 'OTP101', 'LAB211', 'IOT102']),
      );
    });

    test('môn Passed nhưng không có điểm vẫn giữ nguyên trạng thái', () {
      final noGrade = result.entries
          .where((e) => e.status == SubjectStatus.passed && !e.hasGrade)
          .map((e) => e.subjectCode)
          .toList();
      expect(noGrade, hasLength(2));
      expect(noGrade, containsAll(['TRS601', 'LAB211']));
      // Không có điểm thì không được cộng vào GPA.
      expect(
        result.entries
            .where((e) => noGrade.contains(e.subjectCode))
            .every((e) => !e.countsTowardGpa),
        isTrue,
      );
    });
  });

  group('parseSemester', () {
    test('Fall2023 ra năm 2023, mùa thu, khoá sắp xếp 20233', () {
      final parsed = parser.parseSemester('Fall2023')!;
      expect(parsed.year, 2023);
      expect(parsed.season, Season.fall);
      expect(parsed.order, 20233);
    });

    test('Spring < Summer < Fall trong cùng một năm', () {
      final spring = parser.parseSemester('Spring2024')!.order;
      final summer = parser.parseSemester('Summer2024')!.order;
      final fall = parser.parseSemester('Fall2024')!.order;
      expect(spring, lessThan(summer));
      expect(summer, lessThan(fall));
      // Và kỳ của năm sau luôn lớn hơn mọi kỳ của năm trước.
      expect(fall, lessThan(parser.parseSemester('Spring2025')!.order));
    });

    test('ô kỳ để trống trả null chứ không ném lỗi', () {
      expect(parser.parseSemester(''), isNull);
      expect(parser.parseSemester('   '), isNull);
    });
  });

  group('parseStatus', () {
    test('nhận đủ các chuỗi trạng thái của FAP', () {
      expect(parser.parseStatus('Passed'), SubjectStatus.passed);
      expect(parser.parseStatus('Studying'), SubjectStatus.studying);
      expect(parser.parseStatus('Not started'), SubjectStatus.notStarted);
      expect(parser.parseStatus('Not Passed'), SubjectStatus.notPassed);
      expect(parser.parseStatus('Trạng thái lạ'), SubjectStatus.unknown);
    });
  });

  test('chuỗi rỗng trả kết quả rỗng, không ném lỗi', () {
    final empty = parser.parse('');
    expect(empty.isEmpty, isTrue);
    expect(empty.warnings, isEmpty);
  });
}
