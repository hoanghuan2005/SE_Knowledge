import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/services/md_intake_service.dart';

/// Gửi một request thật tới server đang chạy, giống hệt cách popup extension gọi.
Future<({int status, String body, HttpHeaders headers})> _call(
  String method,
  String path, {
  String? token,
  Object? json,
}) async {
  final client = HttpClient();
  try {
    final req = await client.open(
      method,
      '127.0.0.1',
      MdIntakeService.port,
      path,
    );
    if (token != null) req.headers.set('X-SE-Token', token);
    if (json != null) {
      // Extension khai text/plain để tránh preflight; server vẫn phải tự decode.
      req.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
      req.add(utf8.encode(jsonEncode(json)));
    }
    final res = await req.close();
    final body = await utf8.decoder.bind(res).join();
    return (status: res.statusCode, body: body, headers: res.headers);
  } finally {
    client.close(force: true);
  }
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // flutter_test cài sẵn một HttpOverrides trả 400 cho MỌI request đi ra, để
    // widget test không lỡ gọi mạng thật. Ở đây ta cần HttpClient thật vì đang
    // tự gọi vào server của chính mình ở loopback.
    HttpOverrides.global = null;

    tempDir = await Directory.systemTemp.createTemp('se_knowledge_intake');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    await MdIntakeService.instance.start();
  });

  tearDownAll(() async {
    await MdIntakeService.instance.stop();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('server lên được ở loopback', () {
    expect(MdIntakeService.instance.isRunning, isTrue);
    expect(MdIntakeService.instance.lastError, isNull);
    expect(MdIntakeService.instance.statusText, contains('127.0.0.1:8787'));
  });

  test('GET /ping để extension dò xem app có chạy không', () async {
    final res = await _call('GET', '/ping');
    expect(res.status, 200);
    expect(jsonDecode(res.body), {'app': 'se_knowledge'});
  });

  test('mọi response đều kèm CORS header', () async {
    final res = await _call('OPTIONS', '/note');
    expect(res.status, 204);
    expect(res.headers.value('access-control-allow-origin'), '*');
    expect(
      res.headers.value('access-control-allow-headers'),
      contains('X-SE-Token'),
    );
    // Thiếu header này thì popup báo lỗi CORS mà server không thấy request nào.
    expect(res.headers.value('access-control-allow-private-network'), 'true');
  });

  test('POST /note lưu file và phát ra IncomingNote', () async {
    final received = MdIntakeService.instance.onNote.first;

    final res = await _call(
      'POST',
      '/note',
      token: MdIntakeService.token,
      json: {
        'title': 'Curriculum Details: BIT_IS_K20D',
        'url': 'https://flm.fpt.edu.vn/gui/role/student/CurriculumDetails?curid=2951',
        'markdown': '# Curriculum\n\nSource: https://example.com\n',
      },
    );

    expect(res.status, 200);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(body['ok'], isTrue);

    final saved = File(body['savedAs'] as String);
    expect(await saved.exists(), isTrue);
    expect(await saved.readAsString(), contains('# Curriculum'));
    // Dấu `:` bị Windows cấm trong tên file nên phải được lọc đi.
    expect(saved.path, contains('Curriculum Details BIT_IS_K20D.md'));
    expect(saved.parent.path, endsWith('fap_inbox'));

    final note = await received;
    expect(note.sourceUrl, contains('curid=2951'));
    expect(note.savedPath, saved.path);
  });

  test('sai token thì bị chặn', () async {
    final res = await _call(
      'POST',
      '/note',
      token: 'SAI_TOKEN',
      json: {'title': 'x', 'url': 'x', 'markdown': 'x'},
    );
    expect(res.status, 403);
  });

  test('body không có markdown thì báo lỗi tử tế, không sập listener', () async {
    final bad = await _call(
      'POST',
      '/note',
      token: MdIntakeService.token,
      json: {'title': 'x', 'url': 'x', 'markdown': '   '},
    );
    expect(bad.status, 400);

    // Server vẫn phục vụ request tiếp theo bình thường.
    expect((await _call('GET', '/ping')).status, 200);
  });

  test('route lạ trả 404', () async {
    expect((await _call('GET', '/khong-co-that')).status, 404);
  });
}
