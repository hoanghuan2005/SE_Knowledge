import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/services/obsidian_service.dart';
import 'package:se_knowledge/views/widgets/vault_import_plan_dialog.dart';

/// Kiểm thử hộp thoại xem trước trước khi nạp Vault vào SQLite.
///
/// Hộp thoại chỉ đọc một [VaultSyncPlan] dựng sẵn nên không cần đụng tới đĩa
/// lẫn cơ sở dữ liệu: ráp plan trong bộ nhớ rồi pump thẳng widget.
void main() {
  ObsidianNote note(String code, {String? curriculum}) => ObsidianNote(
    filePath: 'C:/Vault/$code.md',
    fileName: '$code.md',
    frontMatter: {
      'code': code,
      'name': 'Môn $code',
      if (curriculum != null) 'curriculum': '[$curriculum]',
    },
    body: '',
    links: const [],
    tags: const [],
  );

  VaultSyncPlan plan({
    String subFolder = '',
    List<ObsidianNote> toCreate = const [],
    List<ObsidianNote> toUpdate = const [],
    List<ObsidianNote> unchanged = const [],
    List<EdgeChange> edgesToAdd = const [],
    List<EdgeChange> edgesToRemove = const [],
    List<String> brokenLinks = const [],
    List<String> detectedCurriculumCodes = const [],
  }) => VaultSyncPlan(
    vaultPath: r'C:\Vault',
    subFolder: subFolder,
    notes: [...toCreate, ...toUpdate, ...unchanged],
    toCreate: toCreate,
    toUpdate: toUpdate,
    unchanged: unchanged,
    edgesToAdd: edgesToAdd,
    edgesToRemove: edgesToRemove,
    brokenLinks: brokenLinks,
    detectedCurriculumCodes: detectedCurriculumCodes,
  );

  /// Mở hộp thoại và trả về hàm đọc kết quả — giá trị chỉ có sau khi hộp thoại
  /// đóng, tức là sau lần `pump` kế tiếp của bài test.
  Future<VaultImportDecision? Function()> open(
    WidgetTester tester,
    VaultSyncPlan p, {
    List<VaultFolderOption> folders = const [],
    List<Map<String, dynamic>> curriculums = const [],
    Future<VaultSyncPlan> Function(String)? onReplan,
  }) async {
    VaultImportDecision? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await VaultImportPlanDialog.show(
                  context,
                  initialPlan: p,
                  folders: folders,
                  curriculums: curriculums,
                  onReplan: onReplan ?? (_) async => p,
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

  group('liệt kê thay đổi', () {
    testWidgets('hiện môn thêm mới và môn cập nhật kèm số lượng', (
      tester,
    ) async {
      await open(
        tester,
        plan(
          toCreate: [note('PRF192'), note('MAD101')],
          toUpdate: [note('CSD201')],
        ),
      );

      expect(find.text('Môn thêm mới (2)'), findsOneWidget);
      expect(find.text('Môn cập nhật (1)'), findsOneWidget);
      expect(find.text('PRF192'), findsOneWidget);
      expect(find.text('CSD201'), findsOneWidget);
    });

    testWidgets('nhóm rỗng thì không chiếm chỗ', (tester) async {
      await open(tester, plan(toCreate: [note('PRF192')]));

      expect(find.text('Môn thêm mới (1)'), findsOneWidget);
      expect(find.textContaining('Môn cập nhật'), findsNothing);
      expect(find.textContaining('Liên kết thêm'), findsNothing);
      expect(find.textContaining('Liên kết bị gỡ'), findsNothing);
    });

    testWidgets('cạnh hiển thị đúng chiều môn trước → môn sau', (tester) async {
      await open(
        tester,
        plan(
          edgesToAdd: const [
            EdgeChange(subjectCode: 'CSD201', prerequisiteCode: 'PRF192'),
          ],
        ),
      );

      expect(find.text('PRF192 -> CSD201'), findsOneWidget);
    });
  });

  group('cảnh báo mất dữ liệu', () {
    testWidgets('có liên kết bị gỡ thì đổi sang biểu tượng cảnh báo', (
      tester,
    ) async {
      await open(
        tester,
        plan(
          edgesToRemove: const [
            EdgeChange(subjectCode: 'PRJ301', prerequisiteCode: 'CSD201'),
          ],
        ),
      );

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.text('Liên kết bị gỡ (1)'), findsOneWidget);
      expect(find.textContaining('đã bị xoá khỏi file .md'), findsOneWidget);
    });

    testWidgets('không có gì bị gỡ thì dùng biểu tượng nhập bình thường', (
      tester,
    ) async {
      await open(tester, plan(toCreate: [note('PRF192')]));

      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    });

    testWidgets('liên kết gãy được báo là sẽ bỏ qua', (tester) async {
      await open(tester, plan(brokenLinks: const ['PRJ301 -> [[KHONGCO]]']));

      expect(find.text('Liên kết gãy (1)'), findsOneWidget);
      expect(find.textContaining('sẽ bỏ qua'), findsOneWidget);
    });
  });

  group('chọn tệp môn học đích', () {
    testWidgets('mặc định tạo tệp mới, mã gợi ý lấy từ tên thư mục Vault', (
      tester,
    ) async {
      final result = await open(tester, plan(toCreate: [note('PRF192')]));

      await tester.tap(find.text('Nạp vào CSDL'));
      await tester.pumpAndSettle();

      final target = result()!.target;
      expect(target.isUnassigned, isFalse);
      expect(target.newCode, 'VAULT');
    });

    testWidgets('mã gợi ý ưu tiên front matter curriculum: của các file', (
      tester,
    ) async {
      final result = await open(
        tester,
        plan(
          toCreate: [note('PRF192', curriculum: 'BIT_SE_K19B')],
          detectedCurriculumCodes: const ['BIT_SE_K19B'],
        ),
      );

      await tester.tap(find.text('Nạp vào CSDL'));
      await tester.pumpAndSettle();

      expect(result()!.target.newCode, 'BIT_SE_K19B');
    });

    testWidgets('mã đã trùng một tệp có sẵn thì chọn luôn tệp đó', (
      tester,
    ) async {
      final result = await open(
        tester,
        plan(
          toCreate: [note('PRF192')],
          detectedCurriculumCodes: const ['BIT_SE_K19B'],
        ),
        curriculums: const [
          {
            'id': 7,
            'code': 'BIT_SE_K19B',
            'name': 'SE K19B',
            'course_count': 47,
          },
        ],
      );

      await tester.tap(find.text('Nạp vào CSDL'));
      await tester.pumpAndSettle();

      final target = result()!.target;
      expect(target.existingCurriculumId, 7);
      expect(target.newCode, isNull);
    });

    testWidgets('chọn "không xếp vào tệp nào" thì target là unassigned', (
      tester,
    ) async {
      final result = await open(tester, plan(toCreate: [note('PRF192')]));

      await tester.tap(find.textContaining('Không xếp vào tệp nào'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nạp vào CSDL'));
      await tester.pumpAndSettle();

      expect(result()!.target.isUnassigned, isTrue);
    });

    testWidgets('đổi phạm vi thì quét lại và cập nhật danh sách thay đổi', (
      tester,
    ) async {
      final replanned = plan(subFolder: 'FAP', toCreate: [note('CSD201')]);
      var replanCalls = 0;

      await open(
        tester,
        plan(toCreate: [note('PRF192'), note('MAD101')]),
        folders: const [
          VaultFolderOption(relativePath: '', mdCount: 2),
          VaultFolderOption(relativePath: 'FAP', mdCount: 1),
        ],
        onReplan: (sub) async {
          replanCalls++;
          expect(sub, 'FAP');
          return replanned;
        },
      );

      expect(find.text('Môn thêm mới (2)'), findsOneWidget);

      await tester.tap(find.textContaining('Toàn bộ Vault'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('FAP  ·  1 file .md').last);
      await tester.pumpAndSettle();

      expect(replanCalls, 1);
      expect(find.text('Môn thêm mới (1)'), findsOneWidget);
      expect(find.text('CSD201'), findsOneWidget);
    });

    testWidgets('quét lại hỏng thì trả phạm vi về cũ và nói rõ, không nạp nhầm', (
      tester,
    ) async {
      final result = await open(
        tester,
        plan(toCreate: [note('PRF192'), note('MAD101')]),
        folders: const [
          VaultFolderOption(relativePath: '', mdCount: 2),
          VaultFolderOption(relativePath: 'FAP', mdCount: 1),
        ],
        onReplan: (_) async => throw Exception('Không tìm thấy thư mục'),
      );

      await tester.tap(find.textContaining('Toàn bộ Vault'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('FAP  ·  1 file .md').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('giữ nguyên phạm vi cũ'), findsOneWidget);
      // Ô phạm vi phải quay về "Toàn bộ Vault" để khớp với kế hoạch đang hiện.
      expect(find.textContaining('Toàn bộ Vault'), findsWidgets);

      await tester.tap(find.text('Nạp vào CSDL'));
      await tester.pumpAndSettle();
      expect(result()!.plan.subFolder, '');
      expect(result()!.plan.toCreate, hasLength(2));
    });
  });

  group('kết quả trả về', () {
    testWidgets('bấm Nạp vào CSDL trả về kế hoạch kèm tệp đích', (
      tester,
    ) async {
      final result = await open(tester, plan(toCreate: [note('PRF192')]));

      await tester.tap(find.text('Nạp vào CSDL'));
      await tester.pumpAndSettle();

      expect(result(), isNotNull);
      expect(result()!.plan.toCreate.single.code, 'PRF192');
    });

    testWidgets('bấm Huỷ không trả về quyết định nào', (tester) async {
      final result = await open(tester, plan(toCreate: [note('PRF192')]));

      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();

      expect(result(), isNull);
    });
  });
}
