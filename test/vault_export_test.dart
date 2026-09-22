import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:se_knowledge/models/curriculum.dart';
import 'package:se_knowledge/models/subject.dart';
import 'package:se_knowledge/services/db_service.dart';
import 'package:se_knowledge/services/obsidian_service.dart';
import 'package:se_knowledge/views/widgets/vault_export_dialog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Kiểm thử phần "Ghi ra Vault" có chọn phạm vi.
///
/// Trước đây nút này đổ thẳng toàn bộ CSDL ra đĩa, không hỏi gì. Hai nhóm bài
/// dưới đây khoá lại hai nửa của tính năng mới: tầng dịch vụ tính đúng "tạo
/// mới / hoà vào file cũ" và các liên kết sẽ gãy, còn hộp thoại dịch đúng ô
/// tích của người dùng thành danh sách môn.
void main() {
  final now = DateTime(2026, 1, 1);

  Subject subject(int id, String code, {int semester = 1, String? notePath}) =>
      Subject(
        id: id,
        code: code,
        name: 'Môn $code',
        semester: semester,
        notePath: notePath,
        createdAt: now,
        updatedAt: now,
      );

  // ------------------------------------------------------------------
  // TẦNG DỊCH VỤ — đụng đĩa thật, nên cần thư mục tạm và CSDL tạm
  // ------------------------------------------------------------------

  group('ObsidianService — ghi ra Vault theo phạm vi', () {
    late Directory tempDir;
    late Directory vault;
    final db = DbService.instance;
    final vaultService = ObsidianService.instance;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      tempDir = await Directory.systemTemp.createTemp('se_knowledge_export');
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
      vault = await Directory(p.join(tempDir.path, 'vault'))
          .create(recursive: true);
      await for (final e in vault.list()) {
        await e.delete(recursive: true);
      }
    });

    /// PRF192 <- CSD201 <- DBI202, cộng một môn rời MAD101.
    Future<Map<String, int>> seedChain() async {
      final ids = <String, int>{};
      for (final code in ['PRF192', 'CSD201', 'DBI202', 'MAD101']) {
        ids[code] = await db.insertSubject(
          Subject.create(code: code, name: 'Môn $code'),
        );
      }
      await db.addEdge(
        subjectId: ids['CSD201']!,
        prerequisiteId: ids['PRF192']!,
      );
      await db.addEdge(
        subjectId: ids['DBI202']!,
        prerequisiteId: ids['CSD201']!,
      );
      return ids;
    }

    test('preview đánh dấu đúng file đã có sẵn trên đĩa', () async {
      final ids = await seedChain();
      await File(p.join(vault.path, 'PRF192.md')).writeAsString('# cũ\n');

      final preview = await vaultService.buildExportPreview(vault.path);

      expect(preview.subjects, hasLength(4));
      expect(preview.existingFileIds, {ids['PRF192']});
      expect(
        preview.targetPathOf[ids['CSD201']],
        p.join(vault.path, 'CSD201.md'),
      );
      expect(preview.prerequisiteIds[ids['CSD201']], [ids['PRF192']]);
      expect(preview.unlockIds[ids['CSD201']], [ids['DBI202']]);
    });

    test('withPrerequisites truy ngược hết nhiều bậc', () async {
      final ids = await seedChain();
      final preview = await vaultService.buildExportPreview(vault.path);

      expect(preview.withPrerequisites({ids['DBI202']!}), {
        ids['DBI202'],
        ids['CSD201'],
        ids['PRF192'],
      });
      // Môn rời thì không kéo theo ai.
      expect(preview.withPrerequisites({ids['MAD101']!}), {ids['MAD101']});
    });

    test('danglingLinks bỏ qua môn đã có sẵn file trong Vault', () async {
      final ids = await seedChain();
      await File(p.join(vault.path, 'PRF192.md')).writeAsString('# cũ\n');
      final preview = await vaultService.buildExportPreview(vault.path);

      // Ghi mỗi CSD201: nó trỏ lên PRF192 (đã có file -> không gãy) và xuống
      // DBI202 (chưa có file, không được chọn -> gãy).
      final dangling = preview.danglingLinks({ids['CSD201']!});
      expect(dangling, ['CSD201 -> [[DBI202]]']);

      // Chọn cả hai đầu thì không còn liên kết nào gãy.
      expect(preview.danglingLinks({ids['CSD201']!, ids['DBI202']!}), isEmpty);
    });

    test('exportSelection tách bạch file tạo mới với file hoà vào', () async {
      final ids = await seedChain();
      await File(
        p.join(vault.path, 'PRF192.md'),
      ).writeAsString('# PRF192\n\n## Ghi chú của tôi\n\nĐừng xoá dòng này.\n');

      final graph = await db.loadGraph();
      final chosen = graph.subjects
          .where((s) => s.code == 'PRF192' || s.code == 'CSD201')
          .toList();

      final report = await vaultService.exportSelection(
        vault.path,
        subjects: chosen,
      );

      expect(report.total, 2);
      expect(report.created, 1);
      expect(report.overwritten, 1);
      expect(report.indexWritten, isFalse);

      // Chỉ hai môn được chọn có file; hai môn kia không bị đụng tới.
      expect(File(p.join(vault.path, 'CSD201.md')).existsSync(), isTrue);
      expect(File(p.join(vault.path, 'DBI202.md')).existsSync(), isFalse);
      expect(File(p.join(vault.path, 'MAD101.md')).existsSync(), isFalse);

      // Phần người dùng tự viết trong file cũ vẫn còn.
      final merged = await File(p.join(vault.path, 'PRF192.md')).readAsString();
      expect(merged, contains('Đừng xoá dòng này.'));

      expect(ids, isNotEmpty);
    });

    test('_INDEX.md chỉ được ghi khi người dùng bật', () async {
      await seedChain();
      final graph = await db.loadGraph();
      final index = File(p.join(vault.path, ObsidianService.indexFileName));

      await vaultService.exportSelection(
        vault.path,
        subjects: [graph.subjects.first],
      );
      expect(index.existsSync(), isFalse);

      final report = await vaultService.exportSelection(
        vault.path,
        subjects: graph.subjects,
        writeIndex: true,
      );
      expect(report.indexWritten, isTrue);
      expect(index.existsSync(), isTrue);
    });

    test('danh sách rỗng thì không ghi gì và báo cáo nói rõ', () async {
      await seedChain();
      final report = await vaultService.exportSelection(
        vault.path,
        subjects: const [],
      );

      expect(report.total, 0);
      expect(report.summary, 'Không có môn nào để ghi.');
      expect(vault.listSync(), isEmpty);
    });

    // Vault của người dùng thường còn chứa cả file nguồn họ tự bỏ vào (trang
    // FAP thô chẳng hạn). Ghi thẳng ra gốc thì file app sinh ra nằm lẫn với
    // chúng, nên phải trỏ được vào một thư mục riêng — và khi đổi thư mục,
    // file cũ phải ĐI THEO chứ không nằm lại thành bản trùng mã.
    group('ghi vào thư mục con', () {
      test('ghi đúng thư mục con, kể cả _INDEX.md', () async {
        await seedChain();
        final graph = await db.loadGraph();

        final report = await vaultService.exportSelection(
          vault.path,
          subjects: graph.subjects,
          writeIndex: true,
          subFolder: 'SE Knowledge',
        );

        expect(report.total, 4);
        final dir = p.join(vault.path, 'SE Knowledge');
        expect(File(p.join(dir, 'PRF192.md')).existsSync(), isTrue);
        expect(
          File(p.join(dir, ObsidianService.indexFileName)).existsSync(),
          isTrue,
        );
        // Gốc Vault không còn file môn nào.
        expect(File(p.join(vault.path, 'PRF192.md')).existsSync(), isFalse);
      });

      test('đổi thư mục thì dời file cũ chứ không đẻ bản trùng', () async {
        await seedChain();
        var graph = await db.loadGraph();

        // Lần 1: ghi ra gốc Vault, kèm ghi chú người dùng tự viết.
        await vaultService.exportSelection(vault.path, subjects: graph.subjects);
        final old = File(p.join(vault.path, 'PRF192.md'));
        await old.writeAsString(
          '${await old.readAsString()}\nGhi chú tay của tôi.\n',
        );

        // Lần 2: đổi sang thư mục con.
        graph = await db.loadGraph();
        final report = await vaultService.exportSelection(
          vault.path,
          subjects: graph.subjects,
          subFolder: 'SE Knowledge',
        );

        expect(report.moved, 4);
        expect(report.warnings, isEmpty);

        final moved = File(p.join(vault.path, 'SE Knowledge', 'PRF192.md'));
        expect(moved.existsSync(), isTrue);
        // Không còn bản trùng mã ở gốc.
        expect(old.existsSync(), isFalse);
        // Ghi chú tay đi theo file.
        expect(await moved.readAsString(), contains('Ghi chú tay của tôi.'));
        // note_path trong CSDL trỏ đúng chỗ mới.
        final after = await db.loadGraph();
        expect(
          after.subjects.firstWhere((s) => s.code == 'PRF192').notePath,
          moved.path,
        );
      });

      test('bỏ tích "dời file cũ" thì file cũ nằm lại nguyên vẹn', () async {
        await seedChain();
        var graph = await db.loadGraph();
        await vaultService.exportSelection(vault.path, subjects: graph.subjects);

        graph = await db.loadGraph();
        final report = await vaultService.exportSelection(
          vault.path,
          subjects: graph.subjects,
          subFolder: 'SE Knowledge',
          moveExisting: false,
        );

        expect(report.moved, 0);
        expect(File(p.join(vault.path, 'PRF192.md')).existsSync(), isTrue);
        expect(
          File(p.join(vault.path, 'SE Knowledge', 'PRF192.md')).existsSync(),
          isTrue,
        );
      });

      test('đích đã có file trùng tên thì không dời, chỉ cảnh báo', () async {
        await seedChain();
        var graph = await db.loadGraph();
        await vaultService.exportSelection(vault.path, subjects: graph.subjects);

        // Người dùng đã tự đặt sẵn một PRF192.md khác trong thư mục đích.
        final dir = await Directory(
          p.join(vault.path, 'SE Knowledge'),
        ).create(recursive: true);
        await File(p.join(dir.path, 'PRF192.md')).writeAsString('# của tôi\n');

        graph = await db.loadGraph();
        final report = await vaultService.exportSelection(
          vault.path,
          subjects: graph.subjects,
          subFolder: 'SE Knowledge',
        );

        expect(report.moved, 3);
        expect(report.warnings, hasLength(1));
        expect(report.warnings.single, contains('PRF192'));
        // Cả hai bản đều còn — app không tự ý giẫm lên file người dùng đặt sẵn.
        expect(File(p.join(vault.path, 'PRF192.md')).existsSync(), isTrue);
      });

      test('preview liệt kê trước các file sẽ bị dời', () async {
        final ids = await seedChain();
        final graph = await db.loadGraph();
        await vaultService.exportSelection(vault.path, subjects: graph.subjects);

        final atRoot = await vaultService.buildExportPreview(vault.path);
        expect(atRoot.subFolder, '');
        expect(atRoot.moves, isEmpty);

        final inFolder = await vaultService.buildExportPreview(
          vault.path,
          subFolder: 'SE Knowledge',
        );
        expect(inFolder.subFolder, 'SE Knowledge');
        expect(inFolder.moves, hasLength(4));
        // Chỉ hứa dời đúng phần được tích.
        expect(inFolder.movesFor({ids['PRF192']!}), hasLength(1));
        // Xem trước KHÔNG được đụng đĩa.
        expect(File(p.join(vault.path, 'PRF192.md')).existsSync(), isTrue);
        expect(Directory(p.join(vault.path, 'SE Knowledge')).existsSync(), isFalse);
      });

      test('ghi nhanh chỉ dùng thư mục cho môn chưa có file', () async {
        await seedChain();
        var graph = await db.loadGraph();

        // PRF192 đã có file ở gốc từ trước.
        await vaultService.exportSelection(
          vault.path,
          subjects: [graph.subjects.firstWhere((s) => s.code == 'PRF192')],
        );

        graph = await db.loadGraph();
        await vaultService.exportSubjects(
          vault.path,
          graph.subjects,
          subFolder: 'SE Knowledge',
        );

        // Môn cũ nằm yên tại chỗ — không dời, cũng không mọc bản trùng.
        expect(File(p.join(vault.path, 'PRF192.md')).existsSync(), isTrue);
        expect(
          File(p.join(vault.path, 'SE Knowledge', 'PRF192.md')).existsSync(),
          isFalse,
        );
        // Môn chưa có file thì vào thư mục con.
        expect(
          File(p.join(vault.path, 'SE Knowledge', 'MAD101.md')).existsSync(),
          isTrue,
        );
        expect(File(p.join(vault.path, 'MAD101.md')).existsSync(), isFalse);
      });

      test('thư mục chọn ngoài Vault bị từ chối', () async {
        expect(
          vaultService.subFolderFromAbsolute(
            vault.path,
            p.join(vault.path, 'SE Knowledge'),
          ),
          'SE Knowledge',
        );
        // Chọn đúng gốc Vault = ghi ra gốc, hợp lệ.
        expect(vaultService.subFolderFromAbsolute(vault.path, vault.path), '');
        // Thư mục anh em, không nằm trong Vault -> Obsidian không thấy.
        expect(
          vaultService.subFolderFromAbsolute(
            vault.path,
            p.join(tempDir.path, 'ngoài'),
          ),
          isNull,
        );
        expect(vaultService.subFolderFromAbsolute(vault.path, '  '), isNull);
      });

      test('ô nhập lôm côm không leo ra ngoài Vault', () async {
        await seedChain();
        final graph = await db.loadGraph();

        await vaultService.exportSelection(
          vault.path,
          subjects: [graph.subjects.firstWhere((s) => s.code == 'MAD101')],
          subFolder: '/../../thoát/  ',
        );

        // `..` bị loại, chỉ còn đoạn tên thật.
        expect(
          File(p.join(vault.path, 'thoát', 'MAD101.md')).existsSync(),
          isTrue,
        );
        expect(
          vaultService.normalizeSubFolder(vault.path, '/../../thoát/  '),
          'thoát',
        );
        expect(vaultService.normalizeSubFolder(vault.path, '  '), '');
      });
    });

    // FAP có thật những mã chứa `*` — các ô "combo" của khung: PHE_COM*1,
    // SE_COM*4_ELE... Ghép thẳng vào đường dẫn Windows thì cả lượt ghi chết
    // với PathNotFoundException ("The filename, directory name, or volume
    // label syntax is incorrect").
    group('mã môn có ký tự Windows cấm', () {
      test('gọt tên file nhưng giữ nguyên mã thật', () {
        expect(ObsidianService.sanitizeFileStem('PHE_COM*1'), 'PHE_COM-1');
        expect(
          ObsidianService.sanitizeFileStem('SE_COM*4_ELE'),
          'SE_COM-4_ELE',
        );
        expect(
          ObsidianService.sanitizeFileStem(r'A<B>C:D"E/F\G|H?I'),
          'A-B-C-D-E-F-G-H-I',
        );
        // Windows cắt cụt dấu chấm và khoảng trắng cuối tên.
        expect(ObsidianService.sanitizeFileStem('ABC123.  '), 'ABC123');
        // Tên thiết bị chiếm chỗ: CON.md không tạo được.
        expect(ObsidianService.sanitizeFileStem('con'), '_con');
        expect(ObsidianService.sanitizeFileStem('LPT1'), '_LPT1');
        // Mã bình thường không bị đụng tới.
        expect(ObsidianService.sanitizeFileStem('PRF192'), 'PRF192');
        expect(ObsidianService.sanitizeFileStem('PRN232'), 'PRN232');
      });

      test(
        'ghi ra được và front matter mang aliases để link vẫn trỏ đúng',
        () async {
          final comboId = await db.insertSubject(
            Subject.create(
              code: 'PHE_COM*1',
              name: 'Giáo dục thể chất combo 1',
            ),
          );
          final nextId = await db.insertSubject(
            Subject.create(
              code: 'PHE_COM*2',
              name: 'Giáo dục thể chất combo 2',
            ),
          );
          await db.addEdge(subjectId: nextId, prerequisiteId: comboId);

          final graph = await db.loadGraph();
          final report = await vaultService.exportSelection(
            vault.path,
            subjects: graph.subjects,
          );

          expect(report.warnings, isEmpty);
          expect(report.total, 2);

          final file = File(p.join(vault.path, 'PHE_COM-1.md'));
          expect(file.existsSync(), isTrue);

          final text = await file.readAsString();
          // Mã thật vẫn nguyên vẹn, chỉ tên file bị gọt.
          expect(text, contains('code: PHE_COM*1'));
          expect(text, contains('aliases: ["PHE_COM*1"]'));

          // Liên kết viết bằng mã thật, nên nạp ngược lại vẫn khớp đúng môn.
          final next = await File(p.join(vault.path, 'PHE_COM-2.md'))
              .readAsString();
          expect(next, contains('[[PHE_COM*1]]'));
        },
      );

      test('nạp ngược lại nhận đúng mã và dựng lại đúng cạnh', () async {
        final comboId = await db.insertSubject(
          Subject.create(code: 'PHE_COM*1', name: 'Combo 1'),
        );
        final nextId = await db.insertSubject(
          Subject.create(code: 'PHE_COM*2', name: 'Combo 2'),
        );
        await db.addEdge(subjectId: nextId, prerequisiteId: comboId);

        await vaultService.exportSelection(
          vault.path,
          subjects: (await db.loadGraph()).subjects,
        );

        final plan = await vaultService.planImport(vault.path);
        // Mã đọc từ front matter `code:`, không phải từ tên file đã gọt.
        expect(plan.notes.map((n) => n.code).toList()..sort(), [
          'PHE_COM*1',
          'PHE_COM*2',
        ]);
        expect(plan.brokenLinks, isEmpty);
        expect(plan.edgesToAdd, isEmpty, reason: 'cạnh đã có sẵn trong CSDL');
      });

      test('mã bình thường thì không mọc thêm khoá aliases', () async {
        await db.insertSubject(Subject.create(code: 'PRF192', name: 'Môn'));
        await vaultService.exportSelection(
          vault.path,
          subjects: (await db.loadGraph()).subjects,
        );

        final text = await File(p.join(vault.path, 'PRF192.md')).readAsString();
        expect(text, isNot(contains('aliases:')));
      });
    });
  });

  // ------------------------------------------------------------------
  // HỘP THOẠI — thuần bộ nhớ, không đụng đĩa lẫn CSDL
  // ------------------------------------------------------------------

  group('VaultExportDialog', () {
    final se1 = subject(1, 'PRF192');
    final se2 = subject(2, 'CSD201', semester: 2);
    final other = subject(3, 'MAD101');

    final groups = [
      CurriculumGroup(
        curriculumId: 10,
        code: 'BIT_SE_K17B',
        name: 'SE K17B',
        major: 'SE',
        semesters: {
          1: [se1],
          2: [se2],
        },
        totalSubjects: 2,
      ),
      CurriculumGroup(
        code: 'OTHER',
        name: 'Môn ngoài khung',
        major: '',
        semesters: {
          1: [other],
        },
        totalSubjects: 1,
      ),
    ];

    VaultExportPreview preview({
      Set<int> existing = const {},
      String subFolder = '',
      List<VaultExportMove> moves = const [],
    }) =>
        VaultExportPreview(
          vaultPath: r'C:\Vault',
          subFolder: subFolder,
          moves: moves,
          subjects: [se1, se2, other],
          targetPathOf: {
            1: r'C:\Vault\PRF192.md',
            2: r'C:\Vault\CSD201.md',
            3: r'C:\Vault\MAD101.md',
          },
          existingFileIds: existing,
          prerequisiteIds: const {
            2: [1],
          },
          unlockIds: const {
            1: [2],
          },
        );

    Future<VaultExportDecision? Function()> open(
      WidgetTester tester, {
      VaultExportPreview? withPreview,
      Future<VaultExportPreview> Function(String)? onFolderChanged,
      Future<String?> Function()? onPickFolder,
      String? Function(String)? toSubFolder,
    }) async {
      VaultExportDecision? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await VaultExportDialog.show(
                    context,
                    preview: withPreview ?? preview(),
                    groups: groups,
                    onFolderChanged: onFolderChanged,
                    onPickFolder: onPickFolder,
                    toSubFolder: toSubFolder,
                  );
                },
                child: const Text('mở'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('mở'));
      await tester.pumpAndSettle();
      return () => result;
    }

    /// Nội dung hộp thoại cao hơn cửa sổ test 800x600, nên phần tóm tắt ở dưới
    /// nằm ngoài vùng nhìn thấy: phải cuộn tới rồi mới bấm được.
    Future<void> tap(WidgetTester tester, Finder target) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    testWidgets('mặc định chọn toàn bộ và bật sẵn _INDEX.md', (tester) async {
      final read = await open(tester);

      expect(
        find.text('Sẽ ghi 3 file .md — tạo mới 3, hoà vào 0 file đã có.'),
        findsOneWidget,
      );

      await tap(tester, find.text('Ghi ra Vault').last);

      final decision = read()!;
      expect(decision.subjects.map((s) => s.code), [
        'PRF192',
        'CSD201',
        'MAD101',
      ]);
      expect(decision.writeIndex, isTrue);
    });

    testWidgets('đếm riêng file đã có sẵn trong Vault', (tester) async {
      await open(tester, withPreview: preview(existing: {1, 3}));

      expect(
        find.text('Sẽ ghi 3 file .md — tạo mới 1, hoà vào 2 file đã có.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'chọn một tệp môn học thì bỏ môn ngoài khung và tắt _INDEX.md',
      (tester) async {
        final read = await open(tester);

        await tap(tester, find.text('Một tệp môn học'));
        await tap(tester, find.text('Ghi ra Vault').last);

        final decision = read()!;
        expect(decision.subjects.map((s) => s.code), ['PRF192', 'CSD201']);
        // Mục lục liệt kê toàn bộ CSDL nên không được bật cho lượt ghi cục bộ.
        expect(decision.writeIndex, isFalse);
      },
    );

    testWidgets('bỏ tích một kỳ thì chỉ còn kỳ kia', (tester) async {
      final read = await open(tester);

      await tap(tester, find.text('Kỳ 2'));
      await tap(tester, find.text('Ghi ra Vault').last);

      expect(read()!.subjects.map((s) => s.code), ['PRF192', 'MAD101']);
    });

    testWidgets('bỏ tích một môn lẻ thì phạm vi tự về "Chọn tay"', (
      tester,
    ) async {
      final read = await open(tester);

      await tap(tester, find.text('PRF192'));

      expect(
        find.text('Sẽ ghi 2 file .md — tạo mới 2, hoà vào 0 file đã có.'),
        findsOneWidget,
      );

      await tap(tester, find.text('Ghi ra Vault').last);
      expect(read()!.subjects.map((s) => s.code), ['CSD201', 'MAD101']);
    });

    testWidgets('cảnh báo liên kết gãy khi môn đích không được chọn', (
      tester,
    ) async {
      await open(tester);

      // Toàn bộ đang được chọn -> chưa có gì gãy.
      expect(find.textContaining('liên kết [[...]] sẽ trỏ tới'), findsNothing);

      await tap(tester, find.text('PRF192'));

      expect(
        find.textContaining('1 liên kết [[...]] sẽ trỏ tới'),
        findsOneWidget,
      );
    });

    testWidgets('ghi kèm tiên quyết kéo lại đúng môn vừa bị bỏ', (
      tester,
    ) async {
      final read = await open(tester);

      await tap(tester, find.text('PRF192'));
      await tap(tester, find.text('Ghi kèm các môn tiên quyết'));

      expect(find.text('Ghi kèm các môn tiên quyết (+1 môn)'), findsOneWidget);
      expect(find.textContaining('liên kết [[...]] sẽ trỏ tới'), findsNothing);

      await tap(tester, find.text('Ghi ra Vault').last);
      expect(read()!.subjects.map((s) => s.code), [
        'PRF192',
        'CSD201',
        'MAD101',
      ]);
    });

    testWidgets('bỏ tích hết thì nút ghi bị khoá', (tester) async {
      await open(tester);

      await tap(tester, find.byKey(const ValueKey('export-group-BIT_SE_K17B')));
      await tap(tester, find.byKey(const ValueKey('export-group-OTHER')));

      expect(find.text('Chưa chọn môn nào.'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Ghi ra Vault'),
      );
      expect(button.onPressed, isNull);
    });

    // Người dùng chọn thư mục bằng hộp thoại của hệ điều hành chứ không gõ
    // đường dẫn: gõ tay thì sai chính tả một ký tự là ra một thư mục khác,
    // mà phải ghi xong mở Obsidian mới biết.
    group('chọn thư mục đích', () {
      testWidgets('chọn xong thì đổi đường dẫn đích và chốt vào quyết định', (
        tester,
      ) async {
        var askedFor = '';
        final read = await open(
          tester,
          onPickFolder: () async => r'C:\Vault\SE Knowledge',
          toSubFolder: (abs) => 'SE Knowledge',
          onFolderChanged: (folder) async {
            askedFor = folder;
            return preview(subFolder: folder);
          },
        );

        expect(find.text('Gốc Vault'), findsOneWidget);
        await tap(tester, find.widgetWithText(OutlinedButton, 'Chọn…'));

        expect(askedFor, 'SE Knowledge');
        expect(find.text('SE Knowledge'), findsOneWidget);
        expect(find.text(r'C:\Vault\SE Knowledge'), findsOneWidget);

        await tap(tester, find.text('Ghi ra Vault').last);
        expect(read()!.subFolder, 'SE Knowledge');
      });

      testWidgets('chọn ra ngoài Vault thì báo lý do và giữ nguyên đích', (
        tester,
      ) async {
        var refreshed = false;
        await open(
          tester,
          onPickFolder: () async => r'D:\Chỗ khác',
          toSubFolder: (abs) => null,
          onFolderChanged: (folder) async {
            refreshed = true;
            return preview(subFolder: folder);
          },
        );

        await tap(tester, find.widgetWithText(OutlinedButton, 'Chọn…'));

        expect(refreshed, isFalse);
        expect(find.text('Gốc Vault'), findsOneWidget);
        expect(
          find.textContaining('nằm ngoài Vault'),
          findsOneWidget,
        );
      });

      testWidgets('nút "Về gốc Vault" đưa đích trở lại gốc', (tester) async {
        var askedFor = 'chưa hỏi';
        await open(
          tester,
          withPreview: preview(subFolder: 'SE Knowledge'),
          onPickFolder: () async => null,
          toSubFolder: (abs) => '',
          onFolderChanged: (folder) async {
            askedFor = folder;
            return preview(subFolder: folder);
          },
        );

        await tap(tester, find.byTooltip('Về gốc Vault'));

        expect(askedFor, '');
        expect(find.text('Gốc Vault'), findsOneWidget);
      });

      testWidgets('không tiêm bộ chọn thì nút bị khoá', (tester) async {
        await open(tester);
        final button = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Chọn…'),
        );
        expect(button.onPressed, isNull);
      });
    });
  });
}
