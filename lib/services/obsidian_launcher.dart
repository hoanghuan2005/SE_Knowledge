import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Gọi app Obsidian đã cài trên máy qua URI scheme `obsidian://`.
///
/// Điều kiện để chạy được: thư mục đó phải từng được mở như một Vault trong
/// Obsidian ít nhất một lần — Obsidian không tự thêm vault lạ qua URI.
class ObsidianLauncher {
  ObsidianLauncher._();

  /// Mở cả Vault. Obsidian KHÔNG nhận thư mục ở tham số `path` (tham số đó
  /// chỉ nhận file), nên phải đi đường `vault=<tên vault>` — mặc định tên
  /// vault trùng tên thư mục.
  static Future<bool> openVault(String vaultPath) {
    final name = p.basename(p.normalize(vaultPath));
    return _launch('obsidian://open?vault=${Uri.encodeComponent(name)}');
  }

  /// Mở đúng file .md của một môn. `file` là đường dẫn TƯƠNG ĐỐI so với gốc
  /// Vault, dùng dấu `/` và bỏ đuôi .md.
  ///
  /// Trả về false nếu note nằm ngoài Vault hiện tại (người dùng đã đổi thư
  /// mục Vault sau khi xuất file) — lúc đó đường dẫn tương đối sẽ bắt đầu
  /// bằng '..' và URI chắc chắn sai.
  static Future<bool> openNote({
    required String vaultPath,
    required String notePath,
  }) {
    var rel = p.relative(notePath, from: vaultPath).replaceAll(r'\', '/');
    if (rel.startsWith('..')) return Future.value(false);
    if (rel.toLowerCase().endsWith('.md')) {
      rel = rel.substring(0, rel.length - 3);
    }
    final name = p.basename(p.normalize(vaultPath));
    return _launch(
      'obsidian://open?vault=${Uri.encodeComponent(name)}'
      '&file=${Uri.encodeComponent(rel)}',
    );
  }

  static Future<bool> _launch(String uri) async {
    // Cố tình KHÔNG dùng canLaunchUrl: tài liệu url_launcher nói hàm này có
    // thể trả false ngay cả khi launchUrl chạy được.
    try {
      return await launchUrl(
        Uri.parse(uri),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  /// Dự phòng khi máy chưa cài Obsidian: mở thư mục bằng File Explorer.
  static Future<void> openInExplorer(String folderPath) async {
    // explorer.exe trả exit code 1 CẢ KHI THÀNH CÔNG — đừng check exitCode
    // rồi báo lỗi oan.
    await Process.run('explorer', [p.normalize(folderPath)]);
  }
}
