import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/services/fap_markdown_parser.dart';

/// Hai lỗi đọc nhãn của trang FLM thật: thanh tiêu đề có dòng "Name:" của
/// người đang đăng nhập, và ô giá trị trống bị bỏ khiến nhãn sau bị đọc nhầm
/// thành giá trị.
void main() {
  test('tên khung lấy từ bảng chi tiết, không lấy email trên thanh tiêu đề', () {
    const md = '''
# BIT_SE_K18C_3243

Source: https://flm.fpt.edu.vn/gui/role/student/CurriculumDetails?curid=3243

Name: someone@example.com Email: someone@example.com User's role: Student

# Curriculum Details

CurriculumCode:

BIT\\_SE\\_K18C

Name:

Bachelor Program of Information Technology, Software Engineering Major

DecisionNo MM/dd/yyyy:

1189/QĐ-ĐHFPT dated 11/16/2022
''';
    final curriculum = FapMarkdownParser.parse(md).curriculum!;
    expect(curriculum.code, 'BIT_SE_K18C');
    expect(
      curriculum.name,
      'Bachelor Program of Information Technology, Software Engineering Major',
    );
  });

  test('ô giá trị trống không nuốt nhãn kế tiếp làm tên môn', () {
    const md = '''
# HCM202_14467

Source: https://flm.fpt.edu.vn/gui/role/student/SyllabusDetails?sylID=14467

# Syllabus Details

Syllabus Name:

**Ho Chi Minh Ideology - Tư tưởng Hồ Chí Minh**

Course Name English:

Subject Code:

**HCM202**
''';
    final syllabus = FapMarkdownParser.parse(md).syllabus!;
    expect(syllabus.subjectCode, 'HCM202');
    expect(syllabus.nameEn, isNot(contains('Subject Code')));
    expect(syllabus.nameEn, contains('Ho Chi Minh Ideology'));
  });
}
