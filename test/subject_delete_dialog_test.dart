import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/models/graph_data.dart';
import 'package:se_knowledge/models/prerequisite.dart';
import 'package:se_knowledge/models/subject.dart';
import 'package:se_knowledge/services/subject_delete_guard.dart';
import 'package:se_knowledge/views/widgets/subject_delete_dialog.dart';

/// Kiểm thử hộp thoại cảnh báo xoá môn học.
///
/// Hộp thoại chỉ đọc [DeleteImpact] nên không cần mở SQLite: dựng đồ thị
/// trong bộ nhớ, cho guard phân tích, rồi pump thẳng widget.
void main() {
  final now = DateTime(2026, 1, 1);
  final guard = SubjectDeleteGuard.instance;

  Subject subject(int id, String code, {String? notePath}) => Subject(
    id: id,
    code: code,
    name: 'Môn $code',
    notePath: notePath,
    createdAt: now,
    updatedAt: now,
  );

  /// `prerequisiteId -> subjectId`: học [prereqId] xong mới học được [id].
  Prerequisite edge(int prereqId, int id) =>
      Prerequisite(subjectId: id, prerequisiteId: prereqId);

  /// Mở hộp thoại trong một app tối thiểu.
  ///
  /// Trả về một hàm đọc lựa chọn đã chốt — phải đọc trễ như vậy vì giá trị chỉ
  /// có sau khi hộp thoại đóng, tức là sau lần `pump` kế tiếp của bài test.
  Future<SubjectDeleteChoice? Function()> open(
    WidgetTester tester,
    DeleteImpact impact,
  ) async {
    SubjectDeleteChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                choice = await showDialog<SubjectDeleteChoice>(
                  context: context,
                  builder: (_) => SubjectDeleteDialog(impact: impact),
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
    return () => choice;
  }

  /// `PRF192 -> CSD201 -> PRJ301`, xoá CSD201 nằm giữa.
  DeleteImpact middleOfChain({String? notePath}) {
    final graph = GraphData(
      subjects: [
        subject(1, 'PRF192'),
        subject(2, 'CSD201', notePath: notePath),
        subject(3, 'PRJ301'),
      ],
      edges: [edge(1, 2), edge(2, 3)],
    );
    return guard.analyzeGraph(graph, 2);
  }

  group('môn nằm giữa chuỗi tiên quyết', () {
    testWidgets('cảnh báo mức nguy hiểm và nêu tên môn bị ảnh hưởng', (
      tester,
    ) async {
      await open(tester, middleOfChain());

      expect(find.text('Xoá CSD201?'), findsOneWidget);
      expect(find.text('NGUY HIỂM'), findsOneWidget);
      // PRJ301 mất tiên quyết, PRF192 bị gỡ liên kết.
      expect(find.text('PRJ301'), findsWidgets);
      expect(find.text('PRF192'), findsWidgets);
    });

    testWidgets('chọn sẵn phương án nối tắt và liệt kê cạnh sẽ tạo', (
      tester,
    ) async {
      await open(tester, middleOfChain());

      expect(find.text('PRF192 → PRJ301'), findsOneWidget);
      expect(find.text('Nối tắt rồi xoá'), findsOneWidget);
    });

    testWidgets('bấm xoá khi đang để mặc định thì trả về phương án nối tắt', (
      tester,
    ) async {
      final choice = await open(tester, middleOfChain());

      await tester.tap(find.text('Nối tắt rồi xoá'));
      await tester.pumpAndSettle();

      expect(choice()?.strategy, DeleteStrategy.rewire);
      expect(choice()?.deleteNoteFile, isFalse);
    });

    testWidgets('đổi sang xoá thẳng thì nhãn nút và giá trị trả về đổi theo', (
      tester,
    ) async {
      final choice = await open(tester, middleOfChain());

      // Nội dung hộp thoại cuộn được nên nút có thể đang nằm ngoài vùng nhìn.
      await tester.ensureVisible(find.text('Xoá thẳng'));
      await tester.tap(find.text('Xoá thẳng'));
      await tester.pumpAndSettle();
      expect(find.text('Nối tắt rồi xoá'), findsNothing);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Xoá'));
      await tester.pumpAndSettle();

      expect(choice()?.strategy, DeleteStrategy.cascade);
    });
  });

  group('môn đứng một mình', () {
    testWidgets('không hỏi chuyện nối tắt', (tester) async {
      final graph = GraphData(
        subjects: [subject(1, 'PRF192')],
        edges: const [],
      );
      await open(tester, guard.analyzeGraph(graph, 1));

      expect(find.text('AN TOÀN'), findsOneWidget);
      expect(find.text('Nối tắt'), findsNothing);
      expect(find.text('Xử lý các liên kết bắc cầu'), findsNothing);
    });
  });

  group('môn đã có file trong Vault', () {
    testWidgets('hiện ô chọn xoá file kèm cảnh báo bị tạo lại', (tester) async {
      await open(tester, middleOfChain(notePath: r'C:\Vault\CSD201.md'));

      expect(find.text('Xoá luôn file .md trong Vault'), findsOneWidget);
      expect(find.text(r'C:\Vault\CSD201.md'), findsOneWidget);
      expect(find.textContaining('sẽ tạo lại đúng môn vừa xoá'), findsOneWidget);
    });

    testWidgets('tick vào thì cảnh báo tắt và giá trị trả về đổi theo', (
      tester,
    ) async {
      final choice = await open(
        tester,
        middleOfChain(notePath: r'C:\Vault\CSD201.md'),
      );

      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(find.textContaining('sẽ tạo lại đúng môn vừa xoá'), findsNothing);

      await tester.tap(find.text('Nối tắt rồi xoá'));
      await tester.pumpAndSettle();

      expect(choice()?.deleteNoteFile, isTrue);
    });

    testWidgets('môn chưa export thì không hỏi về file', (tester) async {
      await open(tester, middleOfChain());

      expect(find.byType(Checkbox), findsNothing);
    });
  });

  group('huỷ bỏ', () {
    testWidgets('bấm Huỷ thì đóng hộp thoại, không trả lựa chọn nào', (
      tester,
    ) async {
      final choice = await open(tester, middleOfChain());

      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();

      expect(find.byType(SubjectDeleteDialog), findsNothing);
      expect(choice(), isNull);
    });
  });
}
