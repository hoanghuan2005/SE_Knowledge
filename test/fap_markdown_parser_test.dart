import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/services/fap_markdown_parser.dart';

/// Trích nguyên văn từ file .md thật do extension sinh ra: turndown làm phẳng
/// bảng HTML thành từng dòng, **ô rỗng biến mất hẳn**, nên OTP101 có 5 dòng
/// (PreRequisite = "None") còn PEN chỉ có 4 dòng (ô PreRequisite rỗng).
const String _curriculumMd = '''
# Curriculum Details

Source: https://flm.fpt.edu.vn/gui/role/student/CurriculumDetails?curid=2951

CurriculumCode:

BIT\\_IS\\_K20D

Name:

Bachelor Program of Information Technology\\_Information System

DecisionNo MM/dd/yyyy:

577/QĐ-ĐHFPT dated 09/13/2024

Description

Total 4 subjects, 145 credits

PLO1

Apply knowledge of mathematics and computing.

PLO2

Analyse a complex computing problem.

Subject Code

Subject Name

Semester

NoCredit

PreRequisite

OTP101

[Orientation and General Training Program\\_Định hướng và Rèn luyện tập trung](/gui/role/student/Syllabuses?subCode=OTP101&curriculumID=2951)

0

0

None

PEN

[Preparation English\\_Tiếng Anh chuẩn bị](/gui/role/student/Syllabuses?subCode=PEN&curriculumID=2951)

0

0

PHE\\_COM\\*1

[Physical Education 1\\_Giáo dục thể chất 1](/gui/role/student/Syllabuses?subCode=PHE_COM%2A1&curriculumID=2951)

0

2

SWE201c

[Introduction to Software Engineering\\_Nhập môn kỹ thuật phần mềm](/gui/role/student/Syllabuses?subCode=SWE201c&curriculumID=2951)

4

3

PRO192 (not applied to the BIT\\_AI; BIT\\_IC programs)
''';

void main() {
  group('FapMarkdownParser — Curriculum Details', () {
    late FapCurriculumImport data;

    setUpAll(() {
      final result = FapMarkdownParser.parse(_curriculumMd);
      expect(result.kind, FapPageKind.curriculum);
      expect(result.isSupported, isTrue);
      data = result.curriculum!;
    });

    test('đọc được phần đầu trang', () {
      expect(data.fapCurriculumId, 2951);
      expect(data.code, 'BIT_IS_K20D');
      expect(data.name, 'Bachelor Program of Information Technology_Information System');
      expect(data.decisionNo, '577/QĐ-ĐHFPT dated 09/13/2024');
      expect(data.totalCredits, 145);
      expect(data.sourceUrl, contains('curid=2951'));
    });

    test('bóc đủ 4 môn dù số dòng mỗi hàng không cố định', () {
      expect(data.subjects.map((s) => s.code).toList(), [
        'OTP101',
        'PEN',
        'PHE_COM*1',
        'SWE201c',
      ]);
    });

    test('hàng CÓ tiên quyết (5 dòng) đọc đúng cả 5 ô', () {
      final otp = data.subjects.first;
      expect(otp.semester, 0);
      expect(otp.credits, 0);
      expect(otp.rawPrerequisite, 'None');
      expect(otp.nameEn, 'Orientation and General Training Program');
      expect(otp.nameVn, 'Định hướng và Rèn luyện tập trung');
    });

    test('hàng KHÔNG có tiên quyết (4 dòng) không nuốt sang hàng sau', () {
      final pen = data.subjects[1];
      expect(pen.code, 'PEN');
      expect(pen.semester, 0);
      expect(pen.credits, 0);
      expect(pen.rawPrerequisite, isEmpty);
      expect(pen.nameVn, 'Tiếng Anh chuẩn bị');
    });

    test('mã môn lấy từ URL nên sạch escape của turndown', () {
      // Dòng đứng trước anchor là `PHE\_COM\*1`; lấy từ subCode=PHE_COM%2A1.
      expect(data.subjects[2].code, 'PHE_COM*1');
      expect(data.subjects[2].credits, 2);
    });

    test('hàng cuối cùng vẫn lấy được ô tiên quyết', () {
      final swe = data.subjects.last;
      expect(swe.semester, 4);
      expect(swe.credits, 3);
      expect(
        swe.rawPrerequisite,
        'PRO192 (not applied to the BIT_AI; BIT_IC programs)',
      );
    });

    test('bóc được PLO', () {
      expect(data.plos.map((p) => p.code).toList(), ['PLO1', 'PLO2']);
      expect(data.plos.first.description, startsWith('Apply knowledge'));
    });
  });

  group('FapMarkdownParser — phân loại trang', () {
    test('trang Syllabus báo chưa hỗ trợ, không đoán bừa', () {
      final result = FapMarkdownParser.parse(
        '# FPT University Learning Material\n\n'
        'Source: https://flm.fpt.edu.vn/gui/role/student/SyllabusDetails?sylID=14177\n',
      );
      expect(result.kind, FapPageKind.syllabus);
      expect(result.isSupported, isFalse);
      expect(result.message, contains('chưa hỗ trợ'));
    });

    test('trang lạ báo không nhận ra', () {
      final result = FapMarkdownParser.parse(
        '# Google\n\nSource: https://google.com\n',
      );
      expect(result.kind, FapPageKind.unknown);
      expect(result.isSupported, isFalse);
    });

    test('file không có dòng Source cũng không nổ', () {
      final result = FapMarkdownParser.parse('chỉ là văn bản thường');
      expect(result.kind, FapPageKind.unknown);
      expect(result.isSupported, isFalse);
    });
  });
}
