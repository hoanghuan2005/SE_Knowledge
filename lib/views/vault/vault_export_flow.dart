import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../services/obsidian_service.dart';
import '../../state/app_state.dart';
import '../../utils/ui_helpers.dart';
import '../widgets/vault_export_dialog.dart';

/// Luồng "Ghi ra Vault" dùng chung cho màn hình Vault và màn hình Cài đặt.
///
/// Đối xứng với [VaultImportFlow]: chụp trạng thái Vault, hỏi người dùng muốn
/// ghi những gì, rồi mới ghi. Không có bước nào chạm đĩa trước khi họ bấm
/// xác nhận.
class VaultExportFlow {
  VaultExportFlow._();

  /// Trả về báo cáo khi đã ghi, `null` khi người dùng huỷ hoặc gặp lỗi
  /// (lỗi đã được hiển thị bằng snackbar).
  static Future<VaultExportReport?> run(BuildContext context) async {
    final state = AppState.instance;
    if (!state.hasVault) {
      Ui.error(context, 'Chưa chọn thư mục Obsidian Vault.');
      return null;
    }

    try {
      // Mở lại đúng thư mục lần trước đã ghi: rơi về gốc Vault là đẻ ra một bộ
      // file trùng mã nằm song song với bộ cũ.
      final lastFolder = await state.lastExportSubFolder();
      final preview = await state.buildExportPreview(subFolder: lastFolder);
      if (!context.mounted) return null;

      if (preview.subjects.isEmpty) {
        Ui.info(context, 'Chưa có môn nào trong CSDL để ghi ra Vault.');
        return null;
      }

      final decision = await VaultExportDialog.show(
        context,
        preview: preview,
        groups: state.curriculumGroups,
        onFolderChanged: (folder) =>
            state.buildExportPreview(subFolder: folder),
        // Mở sẵn ở Vault để người dùng khỏi lần mò, và để thư mục họ chọn nhiều
        // khả năng đã nằm sẵn trong Vault.
        onPickFolder: () => getDirectoryPath(
          initialDirectory: state.vaultPath,
          confirmButtonText: 'Chọn thư mục',
        ),
        toSubFolder: state.subFolderFromAbsolute,
      );
      if (decision == null) return null;

      final report = await state.exportSelectionToVault(
        decision.subjects,
        writeIndex: decision.writeIndex,
        subFolder: decision.subFolder,
        moveExisting: decision.moveExisting,
      );
      if (context.mounted) Ui.success(context, report.summary);
      return report;
    } catch (e) {
      if (context.mounted) Ui.error(context, e);
      return null;
    }
  }
}
