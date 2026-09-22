import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Buộc trình biên dịch dựng toàn bộ cây widget của app, kể cả những màn hình
// không bài test nào chạm tới — `flutter analyze` bắt lỗi kiểu, còn bài này
// bắt lỗi biên dịch/khởi tạo hằng ở mức kernel.
import 'package:se_knowledge/main.dart';
import 'package:se_knowledge/views/academic/academic_page.dart';
import 'package:se_knowledge/views/academic/transcript_import_dialog.dart';
import 'package:se_knowledge/views/app_shell.dart';
import 'package:se_knowledge/views/widgets/tree_context_menu.dart';
import 'package:se_knowledge/views/widgets/tree_pickers.dart';
import 'package:se_knowledge/views/vault/vault_import_flow.dart';

void main() {
  test('toàn bộ cây widget biên dịch được', () {
    expect(const AppShell(), isNotNull);
    expect(const SeKnowledgeApp(), isNotNull);
    expect(TreeContextMenu.showForCurriculum, isNotNull);
    expect(PickTermDialog.show, isNotNull);
    expect(VaultImportFlow.run, isNotNull);
    expect(const AcademicPage(), isNotNull);
    expect(TranscriptImportDialog.pickAndShow, isNotNull);
  });

  // Mở app khi chưa nhập bảng điểm là trạng thái mặc định của mọi máy mới, nên
  // tab Học lực phải dựng được mà không chạm tới CSDL: [AppState] lúc đó còn
  // rỗng, trang chỉ được phép hiện trạng thái rỗng kèm hướng dẫn.
  testWidgets('tab Học lực chưa có bảng điểm thì hiện trạng thái rỗng', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AcademicPage())),
    );
    expect(find.text('Chưa có bảng điểm nào'), findsOneWidget);
    expect(find.text('Nhập bảng điểm từ FAP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
