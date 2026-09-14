import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/models/subject.dart';
import 'package:se_knowledge/services/markdown_parser.dart';
import 'package:se_knowledge/services/obsidian_service.dart';

/// Kiểm thử phần bóc tách Markdown — logic thuần Dart, không cần DB hay UI.
void main() {
  group('parseWikiLinks', () {
    test('lấy được link đơn giản', () {
      expect(
        ObsidianService.parseWikiLinks('Cần [[MAD101]] trước.'),
        ['MAD101'],
      );
    });

    test('bỏ alias sau dấu gạch dọc', () {
      expect(
        ObsidianService.parseWikiLinks('[[CSD201|Cấu trúc dữ liệu]]'),
        ['CSD201'],
      );
    });

    test('bỏ phần heading sau dấu thăng', () {
      expect(
        ObsidianService.parseWikiLinks('[[DBI202#Chuẩn hoá]]'),
        ['DBI202'],
      );
    });

    test('loại bỏ link trùng nhau', () {
      expect(
        ObsidianService.parseWikiLinks('[[PRF192]] và [[PRF192]]'),
        ['PRF192'],
      );
    });

    test('không có link thì trả về danh sách rỗng', () {
      expect(ObsidianService.parseWikiLinks('Không có gì ở đây.'), isEmpty);
    });
  });

  group('splitFrontMatter', () {
    test('đọc được các cặp key: value', () {
      const md = '---\n'
          'code: CSD201\n'
          'name: "Data Structures"\n'
          'semester: 2\n'
          '---\n'
          '\n'
          '# Nội dung\n';

      final (front, body) = ObsidianService.splitFrontMatter(md);

      expect(front['code'], 'CSD201');
      expect(front['name'], 'Data Structures');
      expect(front['semester'], '2');
      expect(body.trim(), '# Nội dung');
    });

    test('file không có front matter thì giữ nguyên nội dung', () {
      const md = '# Chỉ có tiêu đề';
      final (front, body) = ObsidianService.splitFrontMatter(md);
      expect(front, isEmpty);
      expect(body, md);
    });
  });

  group('linksUnderHeading', () {
    test('chỉ lấy link nằm dưới đúng heading', () {
      const body = '# PRJ301\n'
          '\n'
          '## Môn tiên quyết\n'
          '- [[CSD201]]\n'
          '- [[DBI202]]\n'
          '\n'
          '## Mở ra các môn\n'
          '- [[PRM393]]\n';

      final links = ObsidianService.linksUnderHeading(body, [
        '## Môn tiên quyết',
      ]);

      expect(links, containsAll(['CSD201', 'DBI202']));
      expect(links, isNot(contains('PRM393')));
    });
  });

  group('parseNote', () {
    test('suy ra mã môn từ tên file khi front matter thiếu', () {
      final note = ObsidianService.instance.parseNote(
        r'C:\Vault\SWR302.md',
        '# Software Requirement\n\nMô tả môn.\n',
      );

      expect(note.code, 'SWR302');
      expect(note.description, 'Mô tả môn.');
    });

    test('ưu tiên front matter hơn tên file', () {
      final note = ObsidianService.instance.parseNote(
        r'C:\Vault\ghi-chu-cu.md',
        '---\ncode: MAD101\nname: "Discrete Mathematics"\ncredits: 3\n---\n\nToán rời rạc.\n',
      );

      expect(note.code, 'MAD101');
      expect(note.name, 'Discrete Mathematics');
      expect(note.credits, 3);
    });
  });

  // ==================================================================
  // HASHTAG
  // ==================================================================
  group('parseTags', () {
    List<String> tagsOf(String body) =>
        MarkdownParser.parseTags(body).map((t) => t.name).toList();

    test('lấy được tag đơn giản', () {
      expect(tagsOf('Môn này #quan-trong và #core'), ['quan-trong', 'core']);
    });

    test('lấy được tag lồng nhau', () {
      final tags = MarkdownParser.parseTags('#ky/2 #mon/bat-buoc');
      expect(tags.map((t) => t.name), ['ky/2', 'mon/bat-buoc']);
      expect(tags.first.parts, ['ky', '2']);
      expect(tags.first.root, 'ky');
    });

    test('tag có dấu tiếng Việt', () {
      expect(tagsOf('Ghi chú #tiên-quyết ở đây'), ['tiên-quyết']);
    });

    test('heading Markdown không phải tag', () {
      expect(tagsOf('## Môn tiên quyết\n# Tiêu đề\n### Ghi chú'), isEmpty);
    });

    test('phần heading trong wiki link không phải tag', () {
      expect(tagsOf('Xem [[DBI202#Chuẩn hoá]] nhé'), isEmpty);
    });

    test('dấu thăng trong URL không phải tag', () {
      expect(tagsOf('Tài liệu https://fap.fpt.edu.vn/sub#syllabus'), isEmpty);
    });

    test('nội dung trong khối code không tính là tag', () {
      const body = 'Trước đó #that\n'
          '```css\n'
          'body { color: #fff; }\n'
          '```\n'
          'Sau đó #cung-that';
      expect(tagsOf(body), ['that', 'cung-that']);
    });

    test('code inline không tính là tag', () {
      expect(tagsOf('Dùng `#include <stdio.h>` trong C'), isEmpty);
    });

    test('dấu thăng dính sau chữ không phải tag', () {
      expect(tagsOf('mau#fff va abc#tag'), isEmpty);
    });

    test('số thứ tự không phải tag', () {
      expect(tagsOf('Bài #1 và #2'), isEmpty);
    });

    test('vị trí trả về khớp với chuỗi gốc', () {
      const body = 'Ghi chú #core ở đây';
      final tag = MarkdownParser.parseTags(body).single;
      expect(body.substring(tag.start, tag.end), '#core');
    });
  });

  // ==================================================================
  // WIKI LINK CÓ CẤU TRÚC
  // ==================================================================
  group('parseLinks', () {
    test('tách được đích, heading và bí danh', () {
      final link = MarkdownParser.parseLinks(
        'Xem [[CSD201#Cây nhị phân|Cấu trúc dữ liệu]] trước.',
      ).single;

      expect(link.target, 'CSD201');
      expect(link.heading, 'Cây nhị phân');
      expect(link.alias, 'Cấu trúc dữ liệu');
      expect(link.display, 'Cấu trúc dữ liệu');
      expect(link.code, 'CSD201');
    });

    test('không có bí danh thì hiển thị chính đích', () {
      final link = MarkdownParser.parseLinks('[[PRF192]]').single;
      expect(link.alias, isNull);
      expect(link.display, 'PRF192');
    });

    test('biết mình nằm dưới section nào', () {
      const body = '# PRJ301\n'
          '\n'
          '## Môn tiên quyết\n'
          '- [[CSD201]]\n'
          '\n'
          '## Mở ra các môn\n'
          '- [[PRM393]]\n';

      final links = MarkdownParser.parseLinks(body);
      final prereq = links.firstWhere((l) => l.target == 'CSD201');
      final unlock = links.firstWhere((l) => l.target == 'PRM393');

      expect(prereq.section, 'Môn tiên quyết');
      expect(prereq.isPrerequisite, isTrue);
      expect(unlock.section, 'Mở ra các môn');
      expect(unlock.isPrerequisite, isFalse);
    });

    test('link trong khối code bị bỏ qua', () {
      const body = '```\n[[KHONG_TINH]]\n```\n[[CO_TINH]]';
      expect(
        MarkdownParser.parseLinks(body).map((l) => l.target),
        ['CO_TINH'],
      );
    });

    test('vị trí trả về khớp với chuỗi gốc', () {
      const body = 'Cần [[MAD101|Toán rời rạc]] trước.';
      final link = MarkdownParser.parseLinks(body).single;
      expect(body.substring(link.start, link.end), '[[MAD101|Toán rời rạc]]');
      expect(link.raw, '[[MAD101|Toán rời rạc]]');
    });

    test('heading trong khối code không tính là section thật', () {
      const body = '## Ghi chú\n'
          '\n'
          '```md\n'
          '## Môn tiên quyết\n'
          '- [[KHONG_TINH]]\n'
          '```\n'
          '\n'
          '- [[PRF192]]\n';

      final links = MarkdownParser.parseLinks(body);

      // Link trong khối code vẫn bị loại như cũ.
      expect(links.map((l) => l.target), ['PRF192']);

      // Và link phía sau vẫn thuộc "Ghi chú", không bị heading giả kéo sang
      // "Môn tiên quyết" — nếu lệch thì lúc nhập Vault sẽ sinh cạnh tiên
      // quyết không có thật.
      expect(links.single.section, 'Ghi chú');
      expect(links.single.isPrerequisite, isFalse);
    });
  });

  // ==================================================================
  // FRONT MATTER NÂNG CAO
  // ==================================================================
  group('front matter dạng danh sách', () {
    test('đọc được danh sách viết trên một dòng', () {
      final note = MarkdownParser.parse(
        '---\ncode: CSD201\ntags: [subject, semester-2]\n---\n\nNội dung.\n',
      );
      expect(note.tagNames, ['subject', 'semester-2']);
      expect(note.tags.every((t) => t.fromFrontMatter), isTrue);
    });

    test('đọc được danh sách YAML nhiều dòng', () {
      const md = '---\n'
          'code: CSD201\n'
          'tags:\n'
          '  - subject\n'
          '  - semester-2\n'
          '---\n'
          '\n'
          'Nội dung.\n';

      final note = MarkdownParser.parse(md);
      expect(note.frontMatter['code'], 'CSD201');
      expect(note.tagNames, ['subject', 'semester-2']);
    });

    test('gộp tag front matter với tag viết trong body', () {
      final note = MarkdownParser.parse(
        '---\ntags: [subject]\n---\n\nGhi chú #kho.\n',
      );
      expect(note.tagNames, containsAll(['subject', 'kho']));
    });
  });

  // ==================================================================
  // EXPORT KHÔNG ĐƯỢC LÀM MẤT NỘI DUNG NGƯỜI DÙNG
  // ==================================================================
  group('mergeMarkdown', () {
    final service = ObsidianService.instance;

    Subject subjectOf(String code, String name) =>
        Subject.create(code: code, name: name, semester: 2, credits: 3);

    const existing = '---\n'
        'code: CSD201\n'
        'name: "Data Structures"\n'
        'semester: 2\n'
        'credits: 3\n'
        'tags: [subject, tu-dat]\n'
        'author: Khoa\n'
        '---\n'
        '\n'
        '# CSD201 — Data Structures\n'
        '\n'
        '## Môn tiên quyết\n'
        '- [[CU_KY]]\n'
        '\n'
        '## Tài liệu\n'
        '- Sách Cormen chương 3\n'
        '\n'
        '## Ghi chú\n'
        'Phần tôi tự viết.\n';

    test('giữ nguyên các mục người dùng tự thêm', () {
      final merged = service.mergeMarkdown(
        subject: subjectOf('CSD201', 'Data Structures'),
        existingContent: existing,
        prerequisites: [subjectOf('PRF192', 'Programming Fundamentals')],
      );

      expect(merged, contains('## Tài liệu'));
      expect(merged, contains('Sách Cormen chương 3'));
      expect(merged, contains('## Ghi chú'));
      expect(merged, contains('Phần tôi tự viết.'));
    });

    test('cập nhật đúng mục môn tiên quyết', () {
      final merged = service.mergeMarkdown(
        subject: subjectOf('CSD201', 'Data Structures'),
        existingContent: existing,
        prerequisites: [subjectOf('PRF192', 'Programming Fundamentals')],
      );

      expect(merged, contains('[[PRF192]]'));
      expect(merged, isNot(contains('[[CU_KY]]')));
    });

    test('giữ khoá front matter lạ và tag người dùng tự đặt', () {
      final merged = service.mergeMarkdown(
        subject: subjectOf('CSD201', 'Data Structures'),
        existingContent: existing,
      );

      expect(merged, contains('author: Khoa'));
      expect(merged, contains('tu-dat'));
      expect(merged, contains('semester-2'));
    });

    test('thêm mục còn thiếu vào file người dùng tự tạo', () {
      final merged = service.mergeMarkdown(
        subject: subjectOf('SWR302', 'Software Requirement'),
        existingContent: '# Ghi chú riêng\n\nChưa có mục nào cả.\n',
        prerequisites: [subjectOf('CSD201', 'Data Structures')],
      );

      expect(merged, contains('## Môn tiên quyết'));
      expect(merged, contains('## Mở ra các môn'));
      expect(merged, contains('Chưa có mục nào cả.'));
    });

    test('chạy lại nhiều lần vẫn cho cùng một kết quả', () {
      final subject = subjectOf('CSD201', 'Data Structures');
      final prereqs = [subjectOf('PRF192', 'Programming Fundamentals')];

      final once = service.mergeMarkdown(
        subject: subject,
        existingContent: existing,
        prerequisites: prereqs,
      );
      final twice = service.mergeMarkdown(
        subject: subject,
        existingContent: once,
        prerequisites: prereqs,
      );

      expect(twice, once);
    });
  });

  // ==================================================================
  // CHỈ MỤC CHO GIAO DIỆN
  // ==================================================================
  group('chỉ mục backlink và tag', () {
    final service = ObsidianService.instance;

    final notes = [
      service.parseNote(
        r'C:\Vault\PRJ301.md',
        '---\ncode: PRJ301\ntags: [java]\n---\n\n'
            '## Môn tiên quyết\n- [[CSD201]]\n',
      ),
      service.parseNote(
        r'C:\Vault\PRM393.md',
        '---\ncode: PRM393\ntags: [java]\n---\n\n'
            '## Môn tiên quyết\n- [[CSD201]]\n',
      ),
    ];

    test('biết môn nào đang trỏ tới môn nào', () {
      expect(service.buildBacklinkIndex(notes)['CSD201'], [
        'PRJ301',
        'PRM393',
      ]);
    });

    test('gom được các môn theo thẻ', () {
      expect(service.buildTagIndex(notes)['java'], ['PRJ301', 'PRM393']);
    });
  });
}
