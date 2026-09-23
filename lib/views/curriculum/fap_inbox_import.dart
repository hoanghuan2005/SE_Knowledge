import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../utils/ui_helpers.dart';

/// Nút "Nhập từ fap_inbox" dùng chung cho màn hình Bản đồ và màn hình tổng
/// quan khung: hiện vòng chờ, quét, rồi báo lại số trang đã nạp.
class FapInboxImport {
  FapInboxImport._();

  static Future<void> run(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 16),
                Text(
                  'Đang quét và tự động nạp fap_inbox...',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final res = await AppState.instance.importFapInbox();
      if (!context.mounted) return;
      Navigator.pop(context);
      Ui.success(
        context,
        'Đã nạp ${res['totalFiles']} files '
        '(${res['curricula']} khung CTĐT, ${res['syllabi']} syllabus, '
        '${res['edges']} cạnh tiên quyết).',
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      Ui.error(context, e);
    }
  }
}
