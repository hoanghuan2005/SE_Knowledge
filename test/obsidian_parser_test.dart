import 'package:flutter_test/flutter_test.dart';
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
}
