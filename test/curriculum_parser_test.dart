import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/models/curriculum.dart';
import 'package:se_knowledge/services/curriculum_mock_data.dart';
import 'package:se_knowledge/services/curriculum_parser_service.dart';

void main() {
  group('Curriculum Data Models Serialization', () {
    test('Course toJson and fromJson round-trip', () {
      const course = Course(
        code: 'PRO192',
        name: 'Object-Oriented Programming',
        credits: 3,
        prerequisites: ['PRF192'],
        term: 2,
      );

      final json = course.toJson();
      final parsed = Course.fromJson(json);

      expect(parsed.code, 'PRO192');
      expect(parsed.name, 'Object-Oriented Programming');
      expect(parsed.credits, 3);
      expect(parsed.prerequisites, ['PRF192']);
      expect(parsed.term, 2);
    });

    test('Curriculum json string serialization', () {
      final curriculum = CurriculumMockData.defaultCurriculum;
      final jsonString = curriculum.toJsonString();
      final parsed = Curriculum.fromJsonString(jsonString);

      expect(parsed.major, contains('Software Engineering'));
      expect(parsed.semesters.length, 3);
      expect(parsed.totalCourses, 12);
    });
  });

  group('Prerequisite and Text Cleaning Helpers', () {
    test('cleanCurriculumText removes tabs, newlines, extra spaces', () {
      expect(
        cleanCurriculumText('  PRF192 \n\t  Programming   Fundamentals  '),
        'PRF192 Programming Fundamentals',
      );
    });

    test('parsePrerequisites handles multiple formats', () {
      expect(
        parsePrerequisites('PRF192, PRO192'),
        ['PRF192', 'PRO192'],
      );
      expect(
        parsePrerequisites('PRF192; CSI104'),
        ['PRF192', 'CSI104'],
      );
      expect(
        parsePrerequisites('PRO192 and MAD101'),
        ['PRO192', 'MAD101'],
      );
      expect(
        parsePrerequisites('None'),
        isEmpty,
      );
      expect(
        parsePrerequisites('-'),
        isEmpty,
      );
    });
  });

  group('HTML Parsing Logic via parseCurriculumWorker', () {
    test('Parses HTML table with semester header rows correctly', () {
      const sampleHtml = '''
<!DOCTYPE html>
<html>
<head><title>FLM Curriculum</title></head>
<body>
  <h1 class="curriculum-title">Chuyên ngành Kỹ thuật phần mềm (SE)</h1>
  <table class="table">
    <thead>
      <tr>
        <th>No.</th>
        <th>Course Code</th>
        <th>Course Name</th>
        <th>Credits</th>
        <th>Prerequisites</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td colspan="5"><strong>Semester 1</strong></td>
      </tr>
      <tr>
        <td>1</td>
        <td>PRF192</td>
        <td>Programming Fundamentals</td>
        <td>3</td>
        <td>None</td>
      </tr>
      <tr>
        <td>2</td>
        <td>CEA201</td>
        <td>Computer Organization and Architecture</td>
        <td>3</td>
        <td>-</td>
      </tr>
      <tr>
        <td colspan="5"><strong>Semester 2</strong></td>
      </tr>
      <tr>
        <td>3</td>
        <td>PRO192</td>
        <td>Object-Oriented Programming</td>
        <td>3</td>
        <td>PRF192</td>
      </tr>
      <tr>
        <td>4</td>
        <td>MAD101</td>
        <td>Discrete Mathematics</td>
        <td>3</td>
        <td>-</td>
      </tr>
    </tbody>
  </table>
</body>
</html>
''';

      final curriculum = parseCurriculumWorker(sampleHtml);

      expect(curriculum.major, contains('Kỹ thuật phần mềm'));
      expect(curriculum.semesters.length, 2);

      // Kỳ 1
      final sem1 = curriculum.semesters.firstWhere((s) => s.termNumber == 1);
      expect(sem1.courses.length, 2);
      expect(sem1.courses[0].code, 'PRF192');
      expect(sem1.courses[0].credits, 3);
      expect(sem1.courses[0].prerequisites, isEmpty);
      expect(sem1.courses[1].code, 'CEA201');

      // Kỳ 2
      final sem2 = curriculum.semesters.firstWhere((s) => s.termNumber == 2);
      expect(sem2.courses.length, 2);
      expect(sem2.courses[0].code, 'PRO192');
      expect(sem2.courses[0].prerequisites, ['PRF192']);
      expect(sem2.courses[1].code, 'MAD101');
    });

    test('Parses FLM exact table format [Code, Name, Term, Credits, Prereq]', () {
      const flmHtml = '''
<!DOCTYPE html>
<html>
<body>
  <table>
    <tr>
      <td>SWD392</td>
      <td>Software Architecture and Design_Kiến trúc và thiết kế phần mềm</td>
      <td>7</td>
      <td>3</td>
      <td>SWE201c or SWE202c, PRO192</td>
    </tr>
    <tr>
      <td>EXE201</td>
      <td>Experiential Entrepreneurship 2_Trải nghiệm khởi nghiệp 2</td>
      <td>8</td>
      <td>3</td>
      <td>EXE101</td>
    </tr>
    <tr>
      <td>PRM393</td>
      <td>Mobile Programming_Lập trình di động</td>
      <td>8</td>
      <td>3</td>
      <td>PRO192</td>
    </tr>
    <tr>
      <td>HCM202</td>
      <td>Ho Chi Minh Ideology_Tư tưởng Hồ Chí Minh</td>
      <td>9</td>
      <td>2</td>
      <td>MLN111, MLN122</td>
    </tr>
    <tr>
      <td>SE_GRA_ELE</td>
      <td>Graduation Elective - Software Engineering_Học phần lựa chọn Đồ án tốt nghiệp</td>
      <td>9</td>
      <td>10</td>
      <td></td>
    </tr>
  </table>
</body>
</html>
''';

      final curriculum = parseCurriculumWorker(flmHtml);

      expect(curriculum.semesters.length, 3); // Kỳ 7, 8, 9

      // Kỳ 7
      final sem7 = curriculum.semesters.firstWhere((s) => s.termNumber == 7);
      expect(sem7.courses.length, 1);
      expect(sem7.courses[0].code, 'SWD392');
      expect(sem7.courses[0].credits, 3);
      expect(sem7.courses[0].prerequisites, ['SWE201C', 'SWE202C', 'PRO192']);

      // Kỳ 8
      final sem8 = curriculum.semesters.firstWhere((s) => s.termNumber == 8);
      expect(sem8.courses.length, 2);
      expect(sem8.totalCredits, 6);
      final prm393 = sem8.courses.firstWhere((c) => c.code == 'PRM393');
      expect(prm393.credits, 3);
      expect(prm393.prerequisites, ['PRO192']);
      final exe201 = sem8.courses.firstWhere((c) => c.code == 'EXE201');
      expect(exe201.credits, 3);
      expect(exe201.prerequisites, ['EXE101']);

      // Kỳ 9
      final sem9 = curriculum.semesters.firstWhere((s) => s.termNumber == 9);
      expect(sem9.courses.length, 2);
      expect(sem9.totalCredits, 12);
      final hcm202 = sem9.courses.firstWhere((c) => c.code == 'HCM202');
      expect(hcm202.credits, 2);
      expect(hcm202.prerequisites, ['MLN111', 'MLN122']);
      final graEle = sem9.courses.firstWhere((c) => c.code == 'SE_GRA_ELE');
      expect(graEle.credits, 10);
      expect(graEle.prerequisites, isEmpty);
    });

    test('Ignores PLO table completely and only parses subject table', () {
      const htmlWithPlo = '''
<!DOCTYPE html>
<html>
<body>
  <h1>Bachelor of Software Engineering</h1>
  <!-- Bảng PLO giống hệt trang FLM thực tế -->
  <div>13 PLO(s) found</div>
  <table class="table table-bordered">
    <thead>
      <tr>
        <th>#</th>
        <th>PLO Name</th>
        <th>PLO Description</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>1</td>
        <td>PLO1</td>
        <td>Understand basic knowledge of social sciences, political law...</td>
      </tr>
      <tr>
        <td>2</td>
        <td>PLO2</td>
        <td>Apply solid scientific foundation knowledge in software engineering...</td>
      </tr>
      <tr>
        <td>13</td>
        <td>PLO13</td>
        <td>Be able to plan, coordinate, and manage resources...</td>
      </tr>
    </tbody>
  </table>

  <!-- Bảng Môn Học (Subject Table) -->
  <table class="table">
    <thead>
      <tr>
        <th>Subject Code</th>
        <th>Subject Name</th>
        <th>Term</th>
        <th>Credits</th>
        <th>Prerequisites</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>PRM393</td>
        <td>Mobile Programming</td>
        <td>8</td>
        <td>3</td>
        <td>PRO192</td>
      </tr>
      <tr>
        <td>EXE201</td>
        <td>Experiential Entrepreneurship 2</td>
        <td>8</td>
        <td>3</td>
        <td>EXE101</td>
      </tr>
    </tbody>
  </table>
</body>
</html>
''';

      final curriculum = parseCurriculumWorker(htmlWithPlo);

      // Không chứa bất kỳ PLO nào
      for (final sem in curriculum.semesters) {
        for (final course in sem.courses) {
          expect(course.code.startsWith('PLO'), isFalse);
          expect(course.code, isNot('1'));
          expect(course.code, isNot('2'));
          expect(course.code, isNot('13'));
        }
      }

      // Chỉ có kỳ 8 với 2 môn học thực sự
      expect(curriculum.semesters.length, 1);
      final sem8 = curriculum.semesters.firstWhere((s) => s.termNumber == 8);
      expect(sem8.courses.length, 2);
      expect(sem8.courses.map((c) => c.code), containsAll(['PRM393', 'EXE201']));
    });

    test('Returns empty curriculum gracefully when no tables found', () {
      const invalidHtml = '<html><body><div>No data available</div></body></html>';
      final result = parseCurriculumWorker(invalidHtml);
      expect(result.semesters, isEmpty);
    });
  });
}

