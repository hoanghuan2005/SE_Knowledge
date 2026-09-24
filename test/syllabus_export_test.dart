import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/models/subject.dart';
import 'package:se_knowledge/services/fap_markdown_parser.dart';
import 'package:se_knowledge/services/obsidian_service.dart';

/// Trang Syllabus dạng bảng GFM: ô nhiều dòng `<br>` phải được đọc trọn theo
/// ô, và mục "Đề cương môn học" của file xuất ra Vault phải mang đủ dữ liệu.
void main() {
  const md = r'''
# VNR202_14468

Source: https://flm.fpt.edu.vn/gui/role/student/SyllabusDetails?sylID=14468

# Syllabus Details

| Syllabus ID: | 14468 |
| --- | --- |
| Syllabus Name: | **History of the Communist Party of Viet Nam - Lịch sử Đảng Cộng sản Việt Nam** |
| Subject Code: | **VNR202** |
| NoCredit: | 2 |
| Degree Level: | Bachelor |
| Time Allocation: | Thời gian học (103h)<br>Study hour (103h) |
| Pre-Requisite: | MLN111, MLN122 |
| Description: | Giới thiệu môn học<br>\- Về nội dung: tri thức |
| StudentTasks: | \- Nắm vững mục tiêu<br>Sinh viên phải tham gia 80% |
| Tools: | Internet, pdf reader |
| Scoring Scale: | 10 |
| DecisionNo MM/dd/yyyy: | 1028/QĐ-ĐHFPT dated 08/21/2026 |
| IsApproved: | **True** |
| Note: | 1) Progress test + Assignment: 70%<br>\- Participation: 10%<br>2) Final Exam: 30% |
| Is Scored: | **True** |
| MinAvgMarkToPass: | 5 |
| IsActive: | True |
| ApprovedDate: | 8/21/2026 |

2 material(s)

| No. | Material Description | Author | Publisher | Published Date | Edition | ISBN | Is Main Material | Is Hard Copy | Is Online | Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Báo cáo tổng kết<br>The final report | Đảng Cộng sản Việt Nam<br>Communist Party | NXB CTQG | 2015 | 1 |  | False | False | True |  |
| 2 | Giáo trình Lịch sử Đảng | Bộ GD&ĐT | NXB CTQG | 2021 | 1 |  | True | True | False | https://moet.gov.vn/x |

2 LO(s)

| No. | CLO Name | CLO Details |
| --- | --- | --- |
| 1 | CLO1 | Hiểu được đối tượng |
| 2 | CLO2 | Phân tích sự ra đời |

Download All Student Material

| Session | Topic | Learning-Teaching Type | LO | ITU | Student Materials | S-Download | Student's Tasks | URLs |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Chương nhập môn<br>I. Đối tượng nghiên cứu<br>II. Chức năng, nhiệm vụ | Offline | LO1 | IT | Đọc trước trang 7-24 | [link1-1](https://drive.google.com/x) | Giáo trình 2021 |  |
| 2 | Chương 1<br>III. Phương pháp | Offline | CLO2, CLO1 | ITU | Đọc trang 24-34 |  | Giáo trình 2021 |  |
''';

  final syl = FapMarkdownParser.parse(md).syllabus!;

  test('ô nhiều dòng của bảng lịch trình không tràn sang cột khác', () {
    expect(syl.sessions, hasLength(2));
    final s1 = syl.sessions.first;
    expect(s1.topic, 'Chương nhập môn\nI. Đối tượng nghiên cứu\nII. Chức năng, nhiệm vụ');
    expect(s1.teachingType, 'Offline');
    expect(s1.cloCodes, ['CLO1']);
    expect(s1.itu, 'IT');
    expect(s1.studentMaterials, 'Đọc trước trang 7-24');
    expect(s1.downloadUrl, contains('drive.google.com'));
    expect(s1.studentTasks, 'Giáo trình 2021');
    expect(syl.sessions[1].cloCodes, ['CLO1', 'CLO2']);
  });

  test('bảng tài liệu đọc đủ cột, kể cả mô tả và tác giả nhiều dòng', () {
    expect(syl.materials, hasLength(2));
    final m1 = syl.materials.first;
    expect(m1.description, 'Báo cáo tổng kết\nThe final report');
    expect(m1.author, 'Đảng Cộng sản Việt Nam\nCommunist Party');
    expect(m1.publisher, 'NXB CTQG');
    expect(m1.publishedDate, '2015');
    expect(m1.isOnline, isTrue);
    expect(syl.materials[1].isMain, isTrue);
    expect(syl.materials[1].note, 'https://moet.gov.vn/x');
    expect(syl.clos.map((c) => c.code), ['CLO1', 'CLO2']);
  });

  test('ô Note (cơ cấu điểm) được giữ lại', () {
    expect(syl.note, contains('Progress test + Assignment: 70%'));
    expect(syl.note, contains('- Participation: 10%'));
    expect(syl.note, contains('Final Exam: 30%'));
  });

  test('file xuất ra Vault có đủ mục đề cương', () {
    final subject = Subject.create(code: 'VNR202', name: 'History of CPV');
    final out = ObsidianService.instance.buildMarkdown(
      subject: subject,
      syllabus: syl,
    );

    expect(out, contains('## Đề cương môn học'));
    expect(out, contains('| Phân bổ thời gian | Thời gian học (103h)<br>Study hour (103h) |'));
    expect(out, contains('### Mô tả môn học'));
    expect(out, contains('### Cách tính điểm'));
    expect(out, contains('### Tài liệu (2)'));
    expect(out, contains('### Chuẩn đầu ra (2 CLO)'));
    expect(out, contains('| 1 | Chương nhập môn<br>I. Đối tượng nghiên cứu<br>II. Chức năng, nhiệm vụ |'));
    // Mục đề cương nằm trước "Ghi chú" để phần tự viết vẫn ở cuối file.
    expect(out.indexOf('## Đề cương môn học'), lessThan(out.indexOf('## Ghi chú')));

    // Không được giống trang FAP thô, không thì bộ quét fap_inbox nạp nhầm.
    expect(FapMarkdownParser.parse(out).syllabus, isNull);
  });

  test('xuất lại thay mục đề cương cũ, giữ nguyên mục người dùng tự viết', () {
    final subject = Subject.create(code: 'VNR202', name: 'History of CPV');
    const existing = '''---
code: VNR202
---

# VNR202 — History of CPV

## Môn tiên quyết
- _Không có (môn nền tảng)_

## Đề cương môn học

### Thông tin chung
bản cũ

### Tài liệu (1)
bản cũ

## Ghi chú
Ghi chú riêng của tôi
''';
    final out = ObsidianService.instance.mergeMarkdown(
      subject: subject,
      existingContent: existing,
      syllabus: syl,
    );
    expect(out, isNot(contains('bản cũ')));
    expect('## Đề cương môn học'.allMatches(out), hasLength(1));
    expect(out, contains('### Tài liệu (2)'));
    expect(out, contains('Ghi chú riêng của tôi'));

    // File cũ chưa có mục đề cương: chèn vào trước "Ghi chú".
    final inserted = ObsidianService.instance.mergeMarkdown(
      subject: subject,
      existingContent: existing.replaceAll(
        RegExp(r'## Đề cương môn học[\s\S]*?(?=## Ghi chú)'),
        '',
      ),
      syllabus: syl,
    );
    expect(
      inserted.indexOf('## Đề cương môn học'),
      lessThan(inserted.indexOf('## Ghi chú')),
    );
  });
}
