import 'dart:developer' as dev;
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/curriculum.dart';

/// Quản lý việc lưu trữ và đọc cache file curriculum_cache.json cục bộ
class CurriculumCacheManager {
  static const String _fileName = 'curriculum_cache.json';

  /// Lấy file cache cục bộ trong thư mục ứng dụng
  static Future<File> _getCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(dir.path, 'SE_Knowledge'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File(p.join(cacheDir.path, _fileName));
  }

  /// Kiểm tra file cache đã tồn tại chưa
  static Future<bool> hasCache() async {
    try {
      final file = await _getCacheFile();
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// Đọc dữ liệu từ file cache
  static Future<Curriculum?> readCache() async {
    try {
      final file = await _getCacheFile();
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;

      return Curriculum.fromJsonString(content);
    } catch (e, stack) {
      dev.log('Lỗi khi đọc file cache: $e', stackTrace: stack);
      return null;
    }
  }

  /// Lưu đối tượng Curriculum vào file cache
  static Future<bool> writeCache(Curriculum curriculum) async {
    try {
      final file = await _getCacheFile();
      await file.writeAsString(curriculum.toJsonString(), flush: true);
      dev.log('Đã lưu Curriculum vào cache: ${file.path}');
      return true;
    } catch (e, stack) {
      dev.log('Lỗi khi ghi file cache: $e', stackTrace: stack);
      return false;
    }
  }

  /// Lấy đường dẫn đầy đủ của file cache
  static Future<String> getCacheFilePath() async {
    final file = await _getCacheFile();
    return file.path;
  }

  /// Mở thư mục chứa file cache trong File Explorer (Windows)
  static Future<void> openCacheFolder() async {
    final file = await _getCacheFile();
    if (!await file.exists()) {
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
    }
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', file.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', file.path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [file.parent.path]);
    }
  }

  /// Xóa file cache nếu cần làm mới hoàn toàn
  static Future<void> clearCache() async {
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      dev.log('Lỗi xóa cache: $e');
    }
  }
}
