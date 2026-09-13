import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/models/subject.dart';
import 'package:se_knowledge/services/obsidian_service.dart';
import 'package:se_knowledge/views/widgets/vault_import_plan_dialog.dart';

/// Kiểm thử hộp thoại xem trước trước khi nạp Vault vào SQLite.
///
/// Hộp thoại chỉ đọc một [VaultSyncPlan] dựng sẵn nên không cần đụng tới đĩa
/// lẫn cơ sở dữ liệu: ráp plan trong bộ nhớ rồi pump thẳng widget.
void main() {
  final now = DateTime(2026, 1, 1);

  ObsidianNote note(String code) => ObsidianNote(
    filePath: 'C:/Vault/$code.md',
    fileName: '$code.md',
    frontMatter: {'code': code, 'name': 'Môn $code'},
    body: '',
    links: const [],
    tags: const [],
  );

  Subject subject(String code) => Subject(
    code: code,
    name: 'Môn $code',
    createdAt: now,
    updatedAt: now,
  );

  VaultSyncPlan plan({
    List<ObsidianNote> toCreate = const [],
    List<ObsidianNote> toUpdate = const [],
    List<ObsidianNote> unchanged = const [],
    List<EdgeChange> edgesToAdd = const [],
    List<EdgeChange> edgesToRemove = const [],
    List<String> brokenLinks = const [],
    List<Subject> missingInVault = const [],
  }) => VaultSyncPlan(
    vaultPath: r'C:\Vault',
    notes: [...toCreate, ...toUpdate, ...unchanged],
    toCreate: toCreate,
    toUpdate: toUpdate,
    unchanged: unchanged,
    edgesToAdd: edgesToAdd,
    edgesToRemove: edgesToRemove,
    brokenLinks: brokenLinks,
    missingInVault: missingInVault,
  );

  /// Mở hộp thoại và trả về hàm đọc kết quả — giá trị chỉ có sau khi hộp thoại
  /// đóng, tức là sau lần `pump` kế tiếp của bài test.
  Future<bool? Function()> open(WidgetTester tester, VaultSyncPlan p) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (_) => VaultImportPlanDialog(plan: p),
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
        plan(toCreate: [note('PRF192'), note('MAD101')], toUpdate: [note('CSD201')]),
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
      expect(
        find.textContaining('đã bị xoá khỏi file .md'),
        findsOneWidget,
      );
    });

    testWidgets('không có gì bị gỡ thì dùng biểu tượng nhập bình thường', (
      tester,
    ) async {
      await open(tester, plan(toCreate: [note('PRF192')]));

      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    });

    testWidgets('môn không còn file .md được nêu rõ là app không tự xoá', (
      tester,
    ) async {
      await open(tester, plan(missingInVault: [subject('SWR302')]));

      expect(find.textContaining('không bao giờ tự xoá'), findsOneWidget);
      expect(find.text('SWR302'), findsOneWidget);
    });

    testWidgets('liên kết gãy được báo là sẽ bỏ qua', (tester) async {
      await open(tester, plan(brokenLinks: const ['PRJ301 -> [[KHONGCO]]']));

      expect(find.text('Liên kết gãy (1)'), findsOneWidget);
      expect(find.textContaining('sẽ bỏ qua'), findsOneWidget);
    });
  });

  group('kết quả trả về', () {
    testWidgets('bấm Nạp vào CSDL trả về true', (tester) async {
      final result = await open(tester, plan(toCreate: [note('PRF192')]));

      await tester.tap(find.text('Nạp vào CSDL'));
      await tester.pumpAndSettle();

      expect(result(), isTrue);
    });

    testWidgets('bấm Huỷ trả về false, không ghi gì', (tester) async {
      final result = await open(tester, plan(toCreate: [note('PRF192')]));

      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();

      expect(result(), isFalse);
    });
  });
}
