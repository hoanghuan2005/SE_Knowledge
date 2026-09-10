import 'package:flutter/material.dart';

import 'services/db_service.dart';
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
  await AppState.instance.bootstrap();

  runApp(const SeKnowledgeApp());
}

class SeKnowledgeApp extends StatelessWidget {
  const SeKnowledgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AppShell(),
    );
  }
}
