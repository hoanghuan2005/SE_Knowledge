import 'dart:io';

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

  group('FapMarkdownParser — Syllabus Details', () {
    late FapSyllabusImport syl;

    setUpAll(() {
      final result = FapMarkdownParser.parse(_syllabusMd);
      expect(result.kind, FapPageKind.syllabus);
      expect(result.isSupported, isTrue);
      expect(result.syllabus, isNotNull);
      syl = result.syllabus!;
    });

    test('đọc được thông tin metadata chính của Syllabus', () {
      expect(syl.fapSyllabusId, 10368);
      expect(syl.subjectCode, 'CSD201');
      expect(syl.nameEn, 'Data Structures and Algorithm');
      expect(syl.nameNative, 'Cấu trúc dữ liệu và giải thuật');
      expect(syl.degreeLevel, 'Bachelor');
      expect(syl.scoringScale, 10);
      expect(syl.minAvgMarkToPass, 5.0);
      expect(syl.isApproved, isTrue);
      expect(syl.isScored, isTrue);
      expect(syl.isActive, isTrue);
      expect(syl.rawPrerequisiteText, 'PRO192');
      expect(syl.decisionNo, contains('1028/QĐ-ĐHFPT'));
      expect(syl.decisionDate, '08/21/2026');
    });

    test('bóc đủ 2 tài liệu giáo trình và các thuộc tính boolean', () {
      expect(syl.materials, hasLength(2));
      final m1 = syl.materials[0];
      expect(m1.seqNo, 1);
      expect(m1.description, 'Data Structures and Algorithms in Java');
      expect(m1.author, 'Michael Goodrich');
      expect(m1.publisher, 'Wiley');
      expect(m1.publishedDate, '2014');
      expect(m1.edition, '6th');
      expect(m1.isbn, '978-1-118-77133-4');
      expect(m1.isMain, isTrue);
      expect(m1.isHardCopy, isFalse);
      expect(m1.isOnline, isTrue);
      expect(m1.note, 'Online book');

      final m2 = syl.materials[1];
      expect(m2.seqNo, 2);
      expect(m2.description, 'FU slides (ppt)');
      expect(m2.isMain, isFalse);
      expect(m2.isHardCopy, isFalse);
      expect(m2.isOnline, isFalse);
    });

    test('bóc đủ 2 chuẩn đầu ra CLO', () {
      expect(syl.clos, hasLength(2));
      expect(syl.clos[0].code, 'CLO1');
      expect(syl.clos[0].detail, contains('singly linked list'));
      expect(syl.clos[1].code, 'CLO2');
      expect(syl.clos[1].detail, contains('stack and queue'));
    });

    test('bóc đủ các buổi học và ánh xạ CLO', () {
      expect(syl.sessions, hasLength(2));
      final s1 = syl.sessions[0];
      expect(s1.sessionNo, 1);
      expect(s1.topic, 'Course Introduction');
      expect(s1.teachingType, 'Offline');
      expect(s1.cloCodes, ['CLO1']);
      expect(s1.itu, 'IT');
      expect(s1.downloadUrl, contains('/download/863/S/1_CSD201.zip'));
    });

    test('bóc đủ các thành phần đánh giá điểm', () {
      expect(syl.assessments, hasLength(2));
      final a1 = syl.assessments[0];
      expect(a1.seqNo, 1);
      expect(a1.category, 'Progress test (PT)');
      expect(a1.type, 'quiz');
      expect(a1.part, 2);
      expect(a1.weightPercent, 20.0);
      expect(a1.completionCriteria, '>0');
      expect(a1.cloCodes, ['CLO1']);

      final a2 = syl.assessments[1];
      expect(a2.seqNo, 2);
      expect(a2.category, 'Final exam');
      expect(a2.weightPercent, 30.0);
      expect(a2.cloCodes, containsAll(['CLO1', 'CLO2']));
    });

    test('bóc tách chính xác file thật HCM202 và CSD201 từ fap_inbox', () {
      final hcmPath = r'C:\Users\SUPPER LOQ\AppData\Roaming\com.example\SE Knowledge\fap_inbox\HCM202_14467.md';
      final hcmFile = File(hcmPath);
      if (hcmFile.existsSync()) {
        final res = FapMarkdownParser.parse(hcmFile.readAsStringSync());
        expect(res.kind, FapPageKind.syllabus);
        expect(res.isSupported, isTrue);
        expect(res.syllabus?.subjectCode, 'HCM202');
        expect(res.syllabus?.fapSyllabusId, 14467);
        expect(res.syllabus?.materials.length, 8);
        expect(res.syllabus?.clos.length, 10);
        expect(res.syllabus?.sessions.length, 40);
        expect(res.syllabus?.assessments.length, 4);
      }

      final csdPath = r'C:\Users\SUPPER LOQ\AppData\Roaming\com.example\SE Knowledge\fap_inbox\CSD201_10368.md';
      final csdFile = File(csdPath);
      if (csdFile.existsSync()) {
        final res = FapMarkdownParser.parse(csdFile.readAsStringSync());
        expect(res.kind, FapPageKind.syllabus);
        expect(res.isSupported, isTrue);
        expect(res.syllabus?.subjectCode, 'CSD201');
        expect(res.syllabus?.fapSyllabusId, 10368);
        expect(res.syllabus?.materials.length, 4);
        expect(res.syllabus?.clos.length, 8);
        expect(res.syllabus?.sessions.length, 60);
        expect(res.syllabus?.assessments.length, 4);
      }
    });

    test('bóc tách chính xác prerequisite codes', () {
      expect(FapMarkdownParser.extractPrerequisiteCodes('PRO192'), ['PRO192']);
      expect(
        FapMarkdownParser.extractPrerequisiteCodes('MLN111, MLN122'),
        ['MLN111', 'MLN122'],
      );
      expect(
        FapMarkdownParser.extractPrerequisiteCodes('MAE101 or MAC101'),
        ['MAE101', 'MAC101'],
      );
      expect(
        FapMarkdownParser.extractPrerequisiteCodes('PRO192 (not applied to the BIT_AI; BIT_IC programs)'),
        ['PRO192'],
      );
      expect(
        FapMarkdownParser.extractPrerequisiteCodes('SWE202c, ENW493c'),
        ['SWE202C', 'ENW493C'],
      );
      expect(FapMarkdownParser.extractPrerequisiteCodes('None'), isEmpty);
      expect(FapMarkdownParser.extractPrerequisiteCodes('Không'), isEmpty);
      expect(FapMarkdownParser.extractPrerequisiteCodes(''), isEmpty);
      expect(FapMarkdownParser.extractPrerequisiteCodes('Description:'), isEmpty);
    });
  });

  group('FapMarkdownParser — phân loại trang', () {
    test('trang Syllabus được nhận dạng và hỗ trợ', () {
      final result = FapMarkdownParser.parse(
        '# Syllabus Details\n\n'
        'Source: https://flm.fpt.edu.vn/gui/role/student/SyllabusDetails?sylID=14177\n\n'
        'Subject Code:\n\n**SWD392**\n',
      );
      expect(result.kind, FapPageKind.syllabus);
      expect(result.isSupported, isTrue);
      expect(result.syllabus?.subjectCode, 'SWD392');
      expect(result.message, contains('SWD392'));
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

  // Bản extension dùng turndown + plugin GFM giữ nguyên bảng dạng `| ô | ô |`.
  // Trước khi hỗ trợ dạng này, mọi nhãn đều nằm sau dấu `|` nên không khớp
  // `startsWith` và cả trang bóc ra rỗng — kể cả ô Pre-Requisite.
  group('FapMarkdownParser — Markdown dạng bảng GFM', () {
    test('trang Syllabus dạng bảng bóc được mã môn và môn tiên quyết', () {
      final syl = FapMarkdownParser.parse(_syllabusTableMd).syllabus!;

      expect(syl.subjectCode, 'PRO192C');
      expect(syl.fapSyllabusId, 12288);
      expect(syl.rawPrerequisiteText.trim(), 'PRF192');
      expect(
        FapMarkdownParser.extractPrerequisiteCodes(syl.rawPrerequisiteText),
        ['PRF192'],
      );
    });

    test('bỏ dấu ** FLM in đậm quanh tên môn', () {
      final syl = FapMarkdownParser.parse(_syllabusTableMd).syllabus!;

      expect(syl.nameEn, 'Object Oriented Programming with Java');
      expect(syl.nameNative, 'Lập trình hướng đối tượng với Java');
    });

    test('các bảng con của trang Syllabus vẫn bóc được', () {
      final syl = FapMarkdownParser.parse(_syllabusTableMd).syllabus!;

      expect(syl.clos.map((c) => c.code), ['CLO1', 'CLO2']);
      expect(syl.sessions, hasLength(2));
      expect(syl.sessions.first.cloCodes, ['CLO1', 'CLO2']);
      expect(syl.isApproved, isTrue);
      expect(syl.scoringScale, 10);
    });

    test('"None" trong ô Pre-Requisite không thành mã môn', () {
      final syl = FapMarkdownParser.parse(
        _syllabusTableMd.replaceFirst(
          '| Pre-Requisite: | PRF192 |',
          '| Pre-Requisite: | None |',
        ),
      ).syllabus!;

      expect(syl.rawPrerequisiteText, isEmpty);
    });

    test('trang Curriculum dạng bảng bóc đủ hàng môn kèm cột tiên quyết', () {
      final cur = FapMarkdownParser.parse(_curriculumTableMd).curriculum!;

      expect(cur.code, 'BIT_SE_K19B');
      expect(cur.subjects.map((s) => s.code), ['PRF192', 'PRO192c', 'LAB211']);
      expect(cur.subjects[0].rawPrerequisite, isEmpty);
      expect(cur.subjects[1].semester, 2);
      expect(cur.subjects[1].credits, 3);
      expect(cur.subjects[1].rawPrerequisite, 'PRF192');
      expect(cur.subjects[2].rawPrerequisite, 'PRO192');
    });

    test('ô nhiều dòng bằng `<br>` không làm lệch các hàng còn lại', () {
      final cur = FapMarkdownParser.parse(
        _curriculumTableMd.replaceFirst('| 2 | 3 | PRF192 |', '| 2 | 3 | PRF192<br>MAE101 |'),
      ).curriculum!;

      expect(cur.subjects.map((s) => s.code), ['PRF192', 'PRO192c', 'LAB211']);
      expect(cur.subjects[1].rawPrerequisite, 'PRF192 MAE101');
      expect(
        FapMarkdownParser.extractPrerequisiteCodes(cur.subjects[1].rawPrerequisite),
        containsAll(['PRF192', 'MAE101']),
      );
      // Hàng sau vẫn nguyên vẹn, không bị ô nhiều dòng của hàng trước nuốt.
      expect(cur.subjects[2].semester, 3);
      expect(cur.subjects[2].rawPrerequisite, 'PRO192');
    });

    test('looksLikeFapPage tách được trang FAP khỏi ghi chú thường', () {
      expect(FapMarkdownParser.looksLikeFapPage(_syllabusTableMd), isTrue);
      expect(FapMarkdownParser.looksLikeFapPage(_curriculumTableMd), isTrue);
      expect(
        FapMarkdownParser.looksLikeFapPage(
          '---\ncode: PRF192\n---\n\n# PRF192\n\n## Môn tiên quyết\n\n_Không có_\n',
        ),
        isFalse,
      );
    });
  });
}

const String _syllabusMd = '''
# Syllabus Details

Source: https://flm.fpt.edu.vn/gui/role/student/SyllabusDetails?sylID=10368

Syllabus ID:

10368

Syllabus Name:

Data Structures and Algorithm\\_Cấu trúc dữ liệu và giải thuật

Course Name English:

Data Structures and Algorithm

Subject Code:

**CSD201**

Learning-Teaching Method:

In-class lecture

NoCredit:

3

Degree Level:

Bachelor

Time Allocation:

45h contact hours

Pre-Requisite:

PRO192

Description:

Course description for CSD201.

StudentTasks:

Study materials and do assignments.

Tools:

NetBeans, JDK

Scoring Scale:

10

DecisionNo MM/dd/yyyy:

1028/QĐ-ĐHFPT dated 08/21/2026

IsApproved:

**True**

Note:

Progress test: 20%, Final exam: 30%

Is Scored:

**True**

MinAvgMarkToPass:

5

IsActive:

True

ApprovedDate:

8/21/2026

2 material(s)

No.

Material Description

Author

Publisher

Published Date

Edition

ISBN

Is Main Material

Is Hard Copy

Is Online

Note

1

Data Structures and Algorithms in Java

Michael Goodrich

Wiley

2014

6th

978-1-118-77133-4

True

False

True

Online book

2

FU slides (ppt)

False

False

False

2 LO(s)

No.

CLO Name

CLO Details

1

CLO1

Describe the list data structure and singly linked list.

2

CLO2

Define stack and queue.

[View mapping of CLOs to PLOs](/CLOMapping/View?syllabusID=10368)

Download All Student Material

Session

Topic

Learning-Teaching Type

LO

ITU

Student Materials

S-Download

Student's Tasks

URLs

1

Course Introduction

Offline

CLO1

IT

Slides and examples

[CSD201](/download/863/S/1_CSD201.zip)

Do writing exercises

2

1.3. Circularly Linked Lists

Offline

CLO1

IT

Slides and examples

Do exercises

2 assessment(s)

No.

Category

Type

Part

Weight

Completion Criteria

Duration

CLO

Question Type

No Question

Knowledge and Skill

Grading Guide

Note

1

Progress test (PT)

quiz

2

20.0%

\\>0

Option 1: 20'-40'

CLO1

Option 1: essay or multiple choice

15-30

PT 1 LO1

on paper

Review for students

2

Final exam

Final exam

1

30.0%

\\>0

60'

CLO1, CLO2

Multiple choice

60

All chapters

by exam board

Note
''';

/// Trang Syllabus Details như bản extension mới (turndown + plugin GFM) sinh ra:
/// bảng được giữ nguyên thay vì bị làm phẳng thành từng dòng.
const String _syllabusTableMd = r'''
# PRO192c_12288

Source: https://flm.fpt.edu.vn/gui/role/student/SyllabusDetails?sylID=12288

# Syllabus Details

| Syllabus ID: | 12288 |
| --- | --- |
| Syllabus Name: | **Object Oriented Programming with Java\_Lập trình hướng đối tượng với Java** |
| Course Name English: | **Object Oriented Programming with Java** |
| Subject Code: | **PRO192c** |
| Learning-Teaching Method: | Blended,Online |
| NoCredit: | 3 |
| Degree Level: | Bachelor |
| Time Allocation: | Study hour (150h) = 45 hours online |
| Pre-Requisite: | PRF192 |
| Description: | This course provides the knowledge and skills of OOP. |
| StudentTasks: | Students complete the online courses MOOC. |
| Tools: | JDK 8+<br>NetBean 13+ IDE |
| Scoring Scale: | 10 |
| DecisionNo MM/dd/yyyy: | 1363/QĐ-ĐHFPT dated 12/06/2024 |
| IsApproved: | **True** |
| Is Scored: | **True** |
| MinAvgMarkToPass: | 5 |
| IsActive: | True |
| ApprovedDate: | 12/6/2024 |

2 LO(s)

| No. | CLO Name | CLO Details |
| --- | --- | --- |
| 1 | CLO1 | Understand the concepts of object oriented programs |
| 2 | CLO2 | Practice basic Java language syntax and semantics |

Download All Student Material 10 sessions (45'/session)

| Session | Topic | Learning-Teaching Type | LO | ITU | Student Materials | S-Download | Student's Tasks | URLs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Course introduction<br>Java introduction | Offline, Online | LO1, LO2 | ITU | MOOC |  | Enroll to the spec on Coursera |  |
| 2 | Reference Types introduction | Online | LO2 | ITU | MOOC |  | Watch all videos |  |

0 Constructive question(s)
0 assessment(s)
''';

/// Trang Curriculum Details cùng đời extension đó.
const String _curriculumTableMd = r'''
# Curriculum Details

Source: https://flm.fpt.edu.vn/gui/role/student/CurriculumDetails?curid=1074

| CurriculumCode: | BIT_SE_K19B |
| --- | --- |
| Name: | Bachelor of IT - Software Engineering |

3 subjects, 9 credits

| Subject Code | Subject Name | Semester | NoCredit | Pre-Requisite |
| --- | --- | --- | --- | --- |
| PRF192 | [Programming Fundamentals\_Nhập môn lập trình](/gui/role/student/Syllabuses?subCode=PRF192&curriculumID=1074) | 1 | 3 |  |
| PRO192c | [Object Oriented Programming\_Lập trình hướng đối tượng](/gui/role/student/Syllabuses?subCode=PRO192c&curriculumID=1074) | 2 | 3 | PRF192 |
| LAB211 | [OOP with Java Lab\_Thực hành OOP](/gui/role/student/Syllabuses?subCode=LAB211&curriculumID=1074) | 3 | 3 | PRO192 |
''';
