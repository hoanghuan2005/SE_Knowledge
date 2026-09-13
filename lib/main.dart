import 'package:flutter/material.dart';

import 'services/chat_session_service.dart';
import 'services/db_service.dart';
import 'services/md_intake_service.dart';
import 'services/settings_service.dart';
import 'state/app_state.dart';
import 'utils/app_constants.dart';
import 'utils/app_theme.dart';
import 'views/app_shell.dart';

/// Điểm vào duy nhất của ứng dụng.
///
/// SE Knowledge là một Standalone Desktop App: không có backend, không có
/// server database. Toàn bộ dữ liệu nằm trong một file SQLite trên máy người
/// dùng, ghi chú nằm trong Obsidian Vault dạng file `.md`. Chạy offline 100%.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Đăng ký SQLite FFI cho nền tảng desktop (Windows / macOS / Linux).
  DbService.registerFfi();

  await SettingsService.instance.init();
  await ChatSessionService.instance.init();
  await AppState.instance.bootstrap();

  // Cổng nhận markdown từ extension Chrome. Hỏng thì chỉ ghi `lastError`,
  // không được phép chặn khởi động app.
  await MdIntakeService.instance.start();

  runApp(const SeKnowledgeApp());
}

class SeKnowledgeApp extends StatelessWidget {
  const SeKnowledgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: AppState.instance.themeMode,
          home: const AppShell(),
        );
      },
    );
  }
}
