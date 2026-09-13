import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../state/app_state.dart';

/// Một trang Markdown vừa được extension Chrome đẩy sang và đã ghi xuống đĩa.
class IncomingNote {
  /// `document.title` của tab lúc bấm nút.
  final String title;

  /// URL trang gốc trên FAP/FLM.
  final String sourceUrl;

  /// Toàn văn Markdown do turndown sinh ra.
  final String markdown;

  /// Đường dẫn tuyệt đối của file `.md` đã lưu.
  final String savedPath;

  final DateTime at;

  const IncomingNote({
    required this.title,
    required this.sourceUrl,
    required this.markdown,
    required this.savedPath,
    required this.at,
  });

  @override
  String toString() => 'IncomingNote($title -> $savedPath)';
}

/// Cổng nhận dữ liệu từ extension Chrome "Page to Markdown Note".
///
/// Chiều đi bắt buộc là **extension -> app**: Manifest V3 không cho một tiến
/// trình desktop gọi vào extension, nên app mở sẵn một HTTP server bé xíu và
/// extension POST markdown vào đó sau khi convert xong. Nhờ vậy toàn bộ bài
/// toán đăng nhập/giữ session FAP được đi vòng qua — trình duyệt đã đăng nhập
/// sẵn rồi.
///
/// Server chỉ bind vào [InternetAddress.loopbackIPv4] nên máy khác trong mạng
/// LAN không gọi tới được, và kết nối loopback cũng không kích hoạt hộp thoại
/// Windows Firewall.
class MdIntakeService {
  MdIntakeService._();
  static final MdIntakeService instance = MdIntakeService._();

  static const int port = 8787;
  static const String token = 'SE_KNOWLEDGE_LOCAL_INTAKE';

  /// Tên thư mục con trong Vault dành riêng cho dữ liệu nhập từ FAP, để không
  /// lẫn với các file `<MÃ MÔN>.md` do app tự xuất ra ở thư mục gốc.
  static const String vaultSubfolder = 'FAP';

  HttpServer? _server;

  /// Lý do server không chạy được (cổng bị chiếm...). Null nghĩa là bình thường.
  String? lastError;

  final StreamController<IncomingNote> _controller =
      StreamController<IncomingNote>.broadcast();

  /// Mỗi lần extension gửi thành công một trang thì phát ra một [IncomingNote].
  Stream<IncomingNote> get onNote => _controller.stream;

  bool get isRunning => _server != null;

  /// Mô tả trạng thái để hiển thị trong màn hình Cài đặt.
  String get statusText => isRunning
      ? 'Đang lắng nghe ở 127.0.0.1:$port'
      : (lastError ?? 'Chưa khởi động');

  /// Bật server. Không bao giờ ném lỗi ra ngoài: hỏng thì ghi [lastError] rồi
  /// trả về, để app vẫn khởi động bình thường.
  Future<void> start() async {
    if (_server != null) return;
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      _server = server;
      lastError = null;
      // Không await: listener chạy nền suốt vòng đời app.
      server.listen(_handle, onError: (Object e) => lastError = e.toString());
    } on SocketException catch (e) {
      // Cổng đã bị tiến trình khác chiếm (thường là một bản app đang mở sẵn).
      lastError =
          'Không mở được cổng $port: ${e.osError?.message ?? e.message}. '
          'Có thể một cửa sổ SE Knowledge khác đang chạy.';
      _server = null;
    } catch (e) {
      lastError = 'Không mở được cổng $port: $e';
      _server = null;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  /// CORS mở cho mọi origin: popup extension gửi tới với origin
  /// `chrome-extension://...` nên không thể liệt kê trước.
  /// `Allow-Private-Network` phòng khi Chrome siết Private Network Access —
  /// thiếu nó thì triệu chứng là popup báo lỗi CORS mà server không hề thấy
  /// request nào.
  void _cors(HttpResponse res) {
    res.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type, X-SE-Token')
      ..set('Access-Control-Allow-Private-Network', 'true');
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      _cors(res);

      if (req.method == 'OPTIONS') {
        res.statusCode = HttpStatus.noContent;
        await res.close();
        return;
      }

      if (req.method == 'GET' && req.uri.path == '/ping') {
        await _writeJson(res, HttpStatus.ok, {'app': 'se_knowledge'});
        return;
      }

      if (req.method == 'POST' && req.uri.path == '/note') {
        await _handleNote(req, res);
        return;
      }

      await _writeJson(res, HttpStatus.notFound, {
        'ok': false,
        'error': 'Không có route ${req.method} ${req.uri.path}',
      });
    } catch (e) {
      // Một request hỏng không được phép làm chết listener.
      try {
        await _writeJson(res, HttpStatus.internalServerError, {
          'ok': false,
          'error': e.toString(),
        });
      } catch (_) {
        // Kết nối đã đứt, không còn gì để trả lời.
      }
    }
  }

  Future<void> _handleNote(HttpRequest req, HttpResponse res) async {
    final sent = req.headers.value('x-se-token');
    if (sent != token) {
      await _writeJson(res, HttpStatus.forbidden, {
        'ok': false,
        'error': 'Sai token.',
      });
      return;
    }

    final body = await utf8.decoder.bind(req).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      await _writeJson(res, HttpStatus.badRequest, {
        'ok': false,
        'error': 'Body phải là một object JSON.',
      });
      return;
    }

    final title = (decoded['title'] as String?)?.trim() ?? '';
    final url = (decoded['url'] as String?)?.trim() ?? '';
    final markdown = (decoded['markdown'] as String?) ?? '';

    if (markdown.trim().isEmpty) {
      await _writeJson(res, HttpStatus.badRequest, {
        'ok': false,
        'error': 'Không có nội dung markdown.',
      });
      return;
    }

    final savedPath = await _saveMarkdown(title, markdown);

    _controller.add(
      IncomingNote(
        title: title.isEmpty ? p.basenameWithoutExtension(savedPath) : title,
        sourceUrl: url,
        markdown: markdown,
        savedPath: savedPath,
        at: DateTime.now(),
      ),
    );

    await _writeJson(res, HttpStatus.ok, {'ok': true, 'savedAs': savedPath});
  }

  /// Ghi file `.md` vào `<Vault>/FAP/` nếu đã chọn Vault, ngược lại vào thư mục
  /// `fap_inbox` trong application support. Trùng tên thì ghi đè — nhập lại
  /// cùng một trang FAP thì bản mới luôn đúng hơn bản cũ.
  Future<String> _saveMarkdown(String title, String markdown) async {
    final dir = await _targetDirectory();
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, '${safeFileName(title)}.md'));
    await file.writeAsString(markdown, flush: true);
    return file.path;
  }

  Future<Directory> _targetDirectory() async {
    final vault = AppState.instance.vaultPath;
    if (AppState.instance.hasVault && vault != null) {
      return Directory(p.join(vault, vaultSubfolder));
    }
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'fap_inbox'));
  }

  /// Lọc các ký tự Windows cấm trong tên file, gộp khoảng trắng, cắt 120 ký tự.
  static String safeFileName(String title) {
    final cleaned = title
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'page';
    return cleaned.length <= 120 ? cleaned : cleaned.substring(0, 120).trim();
  }

  Future<void> _writeJson(
    HttpResponse res,
    int status,
    Map<String, Object?> body,
  ) async {
    res.statusCode = status;
    res.headers.contentType =
        ContentType('application', 'json', charset: 'utf-8');
    res.write(jsonEncode(body));
    await res.close();
  }
}
