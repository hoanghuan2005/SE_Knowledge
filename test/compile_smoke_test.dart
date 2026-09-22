import 'package:flutter_test/flutter_test.dart';
// Buộc trình biên dịch dựng toàn bộ cây widget của app, kể cả những màn hình
// không bài test nào chạm tới — `flutter analyze` bắt lỗi kiểu, còn bài này
// bắt lỗi biên dịch/khởi tạo hằng ở mức kernel.
import 'package:se_knowledge/main.dart';
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
  });
}
