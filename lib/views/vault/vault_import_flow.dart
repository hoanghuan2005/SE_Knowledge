import 'package:flutter/material.dart';

import '../../services/obsidian_service.dart';
import '../../state/app_state.dart';
import '../../utils/ui_helpers.dart';
import '../widgets/vault_import_plan_dialog.dart';

/// Luồng "Nạp vào CSDL" dùng chung cho màn hình Vault, màn hình Cài đặt và
/// menu chuột phải của một tệp môn học trên thanh bên.
///
/// Ba bước, không bước nào ghi xuống đĩa trước khi người dùng bấm xác nhận:
///  1. Liệt kê thư mục con của Vault để chọn phạm vi quét.
///  2. Dựng kế hoạch (`planImport`) và mở hộp thoại chọn phạm vi + tệp đích.
///  3. Ghi kế hoạch (`applyPlan`) kèm tệp đích đã chọn.
class VaultImportFlow {
  VaultImportFlow._();

  /// Chặn mở luồng thứ hai khi luồng trước chưa xong (bấm lặp ở menu chuột
  /// phải trong lúc đang quét) — hai hộp thoại có thể ghi cùng một kế hoạch.
  static bool _running = false;

  /// Trả về báo cáo khi đã nạp, `null` khi người dùng huỷ hoặc gặp lỗi
  /// (lỗi đã được hiển thị bằng snackbar).
  static Future<VaultSyncReport?> run(
    BuildContext context, {
    int? preselectedCurriculumId,
  }) async {
    final state = AppState.instance;
    if (!state.hasVault) {
      Ui.error(context, 'Chưa chọn thư mục Obsidian Vault.');
      return null;
    }

    if (_running) return null;
    _running = true;

    try {
      final folders = await state.listVaultFolders();
      final plan = await state.planImportFromVault();
      if (!context.mounted) return null;

      final decision = await VaultImportPlanDialog.show(
        context,
        initialPlan: plan,
        folders: folders,
        curriculums: state.curriculums,
        onReplan: (sub) => state.planImportFromVault(subFolder: sub),
        preselectedCurriculumId: preselectedCurriculumId,
      );
      if (decision == null) return null;

      final report = await state.applyVaultPlan(
        decision.plan,
        target: decision.target,
      );
      if (context.mounted) Ui.success(context, report.summary);
      return report;
    } catch (e) {
      // `applyVaultPlan` chỉ làm mới giao diện khi ghi xong trọn vẹn. Lỗi ở
      // lượt nạp trang FAP / xếp tệp có thể xảy ra SAU khi môn và cạnh đã ghi,
      // nên vẫn làm mới để cây và đồ thị khớp với CSDL.
      try {
        await state.refresh();
      } catch (_) {}
      if (context.mounted) Ui.error(context, e);
      return null;
    } finally {
      _running = false;
    }
  }
}
