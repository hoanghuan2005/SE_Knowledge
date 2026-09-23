import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:se_knowledge/models/subject.dart';
import 'package:se_knowledge/services/db_service.dart';
import 'package:se_knowledge/services/markdown_parser.dart';
import 'package:se_knowledge/services/obsidian_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Các lỗi của luồng "Nạp vào CSDL" (Vault -> SQLite) đã được sửa. Mỗi bài
/// test dựng đúng kịch bản làm hỏng dữ liệu trước đây.
void main() {
  late Directory tempDir;
  late Directory vault;
  final db = DbService.instance;
  final service = ObsidianService.instance;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    tempDir = await Directory.systemTemp.createTemp('se_knowledge_import_fix');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await db.resetAll();
    vault = await Directory(p.join(tempDir.path, 'vault')).create(recursive: true);
    await for (final e in vault.list()) {
      await e.delete(recursive: true);
    }
  });

  Future<void> write(String rel, String content) async {
    final f = File(p.join(vault.path, rel));
    await f.parent.create(recursive: true);
    await f.writeAsString(content);
  }

  Future<int> addSubject(
    String code, {
    String? name,
    int semester = 1,
    int credits = 3,
    String description = '',
  }) => db.insertSubject(
    Subject.create(
      code: code,
      name: name ?? 'Môn $code',
      semester: semester,
      credits: credits,
      description: description,
    ),
  );

  Future<Set<String>> edgesOf(String code) async {
    final s = await db.getSubjectByCode(code);
    return (await db.getPrerequisitesOf(s!.id!)).map((e) => e.code).toSet();
  }

  group('front matter', () {
    test('khối properties rỗng không làm hỏng lượt quét', () {
      final (front, body) = MarkdownParser.splitFrontMatter('---\n---\nNội dung');
      expect(front, isEmpty);
      expect(body, 'Nội dung');
    });

    test('dấu nháy kép đã escape được trả về nguyên dạng', () {
      final (front, _) = MarkdownParser.splitFrontMatter(
        '---\nname: "Lập trình \\"C\\""\n---\n',
      );
      expect(front['name'], 'Lập trình "C"');
    });

    test('một file template rỗng không chặn cả Vault', () async {
      await write('Templates/mau.md', '---\n---\n');
      await write('PRF192.md', '---\ncode: PRF192\nname: "A"\n---\n');
      final plan = await service.planImport(vault.path);
      expect(plan.toCreate.map((n) => n.code), contains('PRF192'));
    });
  });

  group('không đè dữ liệu bằng giá trị mặc định', () {
    test('ghi chú tay không có front matter giữ nguyên tên/kỳ/tín chỉ và cạnh', () async {
      await addSubject('CSD201', semester: 2);
      final id = await addSubject('PRJ301', name: 'Java Web', semester: 4, credits: 4);
      final csd = await db.getSubjectByCode('CSD201');
      await db.addEdge(subjectId: id, prerequisiteId: csd!.id!);

      await write('PRJ301.md', 'Ghi chép của tôi, không có heading nào.\n');
      await write('CSD201.md', '---\ncode: CSD201\nsemester: 2\n---\n');

      final plan = await service.planImport(vault.path);
      expect(plan.edgesToRemove, isEmpty);
      await service.applyPlan(plan);

      final prj = await db.getSubjectByCode('PRJ301');
      expect(prj!.name, 'Java Web');
      expect(prj.semester, 4);
      expect(prj.credits, 4);
      expect(await edgesOf('PRJ301'), {'CSD201'});
    });

    test('comment YAML cuối dòng vẫn đọc được số', () async {
      await write('A.md', '---\ncode: A\nsemester: 3 # kỳ 3\n---\n');
      await service.applyPlan(await service.planImport(vault.path));
      expect((await db.getSubjectByCode('A'))!.semester, 3);
    });

    test('hộp thoại được biết trường nào sẽ đổi', () async {
      await addSubject('A', semester: 2);
      await write('A.md', '---\ncode: A\nname: "Môn A"\nsemester: 5\n---\n');
      final plan = await service.planImport(vault.path);
      expect(plan.changeDetails['A'], contains('kỳ 2 → 5'));
    });
  });

  group('mô tả', () {
    test('mô tả nhiều dòng đi hết vòng xuất -> nạp vẫn nguyên', () async {
      final desc = 'Dòng một.\nDòng hai.';
      await addSubject('A', description: desc);
      final s = (await db.getSubjectByCode('A'))!;
      await write(
        'A.md',
        service.buildMarkdown(subject: s),
      );
      final plan = await service.planImport(vault.path);
      final a = plan.notes.single;
      expect(a.importDescription, desc);
      expect(plan.changeDetails['A'] ?? const [], isNot(contains('mô tả')));
    });

    test('môn không có mô tả không vớ nhầm dòng của mục Ghi chú', () async {
      await write(
        'A.md',
        '---\ncode: A\n---\n# A — Môn A\n\n## Môn tiên quyết\n\n## Ghi chú\nViệc cần làm\n',
      );
      final plan = await service.planImport(vault.path);
      expect(plan.notes.single.importDescription, '');
    });
  });

  group('môn tiên quyết', () {
    test('link dưới heading con và heading viết biến thể vẫn được nhận', () {
      const body =
          '## Môn tiên quyết:\n### Bắt buộc\n- [[PRF192]]\n'
          '## Ghi chú\n- [[KHONG]]\n'
          '## **Prerequisites** ##\n- [[MAD101]]\n';
      final r = MarkdownParser.prerequisiteLinksDeep(body);
      expect(r.hasSection, isTrue);
      expect(r.links.map((l) => l.target), ['PRF192', 'MAD101']);
    });

    test('link dạng đường dẫn / tên file đã gọt vẫn trỏ đúng môn', () async {
      await addSubject('PHE_COM*1');
      await write('FAP/PRF192.md', '---\ncode: PRF192\n---\n');
      await write(
        'B.md',
        '---\ncode: B\n---\n## Môn tiên quyết\n- [[FAP/PRF192]]\n- [[PHE_COM-1]]\n',
      );
      final plan = await service.planImport(vault.path);
      expect(plan.brokenLinks, isEmpty);
      expect(
        plan.edgesToAdd.map((e) => e.prerequisiteCode).toSet(),
        {'PRF192', 'PHE_COM*1'},
      );
    });

    test('hai file cùng mã: gộp tiên quyết, không gỡ nhầm cạnh', () async {
      final c = await addSubject('C');
      final a = await addSubject('A');
      await db.addEdge(subjectId: c, prerequisiteId: a);

      await write('A.md', '---\ncode: A\n---\n');
      await write('C.md', '---\ncode: C\n---\n## Môn tiên quyết\n- [[A]]\n');
      await write('sub/C.md', '---\ncode: C\n---\n## Môn tiên quyết\n');

      final plan = await service.planImport(vault.path);
      expect(plan.edgesToRemove, isEmpty);
      expect(plan.allNotes.where((n) => n.code == 'C'), hasLength(1));
      expect(plan.warnings.single, contains('2 file .md cùng mã'));
    });

    test('mục tiên quyết có mặt nhưng rỗng thì vẫn gỡ cạnh như trước', () async {
      final c = await addSubject('C');
      final a = await addSubject('A');
      await db.addEdge(subjectId: c, prerequisiteId: a);
      await write('C.md', '---\ncode: C\n---\n## Môn tiên quyết\n');
      final plan = await service.planImport(vault.path);
      expect(plan.edgesToRemove.map((e) => e.toString()), ['A -> C']);
    });
  });

  test('ghi chú có front matter `code` không bị coi là trang FAP', () async {
    await write(
      'A.md',
      '---\ncode: A\n---\n## Syllabus Details\nXem SyllabusDetails?sylID=1\n',
    );
    final plan = await service.planImport(vault.path);
    expect(plan.fapPages, isEmpty);
    expect(plan.toCreate.map((n) => n.code), ['A']);
  });

  test('kế hoạch cũ bị từ chối khi file sửa sau lúc quét', () async {
    await write('A.md', '---\ncode: A\n---\n');
    final plan = await service.planImport(vault.path);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await write('A.md', '---\ncode: A\nname: "Mới"\n---\n');
    await expectLater(
      service.applyPlan(plan),
      throwsA(isA<ObsidianException>()),
    );
    expect(await db.getSubjectByCode('A'), isNull);
  });
}
