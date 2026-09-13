import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import '../models/graph_rag_context.dart';
import '../utils/app_constants.dart';
import 'graph_rag_service.dart';
import 'settings_service.dart';

/// Gọi thẳng REST API của Gemini hoặc OpenAI bằng package `http`.
///
/// Không có backend trung gian: app desktop là client duy nhất, request đi
/// trực tiếp từ máy người dùng tới nhà cung cấp AI. Nội dung được đọc theo
/// kiểu streaming (SSE) nên chữ hiện dần thay vì đứng im chờ trọn câu trả lời.
class AiService {
  AiService._();
  static final AiService instance = AiService._();

  final SettingsService _settings = SettingsService.instance;
  final GraphRagService _graphRag = GraphRagService.instance;

  /// Hết hạn khi không nhận thêm được mẩu nội dung nào trong khoảng này.
  /// Với stream thì đây là khoảng chờ giữa hai chunk, không phải tổng thời
  /// gian, nên câu trả lời dài vẫn chạy thoải mái.
  static const Duration timeout = Duration(seconds: 45);

  /// Số tin nhắn cũ gửi kèm. Gửi trọn lịch sử thì càng chat lâu prompt càng
  /// phình ra, đi ngược lại chính mục tiêu tiết kiệm token của Graph RAG.
  static const int maxHistoryMessages = 8;

  Future<bool> get isConfigured async {
    final key = await _settings.getApiKey();
    return key != null && key.trim().isNotEmpty;
  }

  /// Gửi một lượt hội thoại. [history] là các tin nhắn trước đó (cũ -> mới).
  ///
  /// Khi [includeKnowledgeContext] bật, câu hỏi được đối chiếu với đồ thị
  /// tiên quyết trong SQLite (Graph RAG) để chỉ gửi kèm subgraph liên quan
  /// trực tiếp, thay vì toàn bộ CSDL.
  ///
  /// [onContext] gọi ngay khi trích xong ngữ cảnh (trước lúc chờ mạng), còn
  /// [onDelta] gọi mỗi lần nhận thêm một mẩu chữ, để UI hiện dần.
  Future<AiAnswer> ask({
    required String question,
    List<ChatMessage> history = const [],
    bool includeKnowledgeContext = true,
    void Function(GraphRagSummary summary)? onContext,
    void Function(String delta)? onDelta,
  }) async {
    final provider = await _settings.getAiProvider();
    final apiKey = (await _settings.getApiKey(provider))?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw AiException(
        'Chưa có API key. Vào màn hình Cài đặt để nhập key trước khi chat.',
      );
    }

    final model = await _settings.getModel(provider);

    final ragContext = includeKnowledgeContext
        ? await _graphRag.buildContext(question)
        : null;
    if (ragContext != null) onContext?.call(ragContext.summary);

    final systemPrompt = _systemPrompt(ragContext?.promptText ?? '');
    final recent = _recentHistory(history);

    try {
      final text = provider == AppConstants.providerOpenAi
          ? await _streamOpenAi(
              apiKey: apiKey,
              model: model,
              systemPrompt: systemPrompt,
              history: recent,
              question: question,
              onDelta: onDelta,
            )
          : await _streamGemini(
              apiKey: apiKey,
              model: model,
              systemPrompt: systemPrompt,
              history: recent,
              question: question,
              onDelta: onDelta,
            );
      return AiAnswer(text: text, ragSummary: ragContext?.summary);
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw AiException('Nhà cung cấp AI phản hồi quá chậm, thử lại sau.');
    } on http.ClientException catch (e) {
      throw AiException('Không kết nối được tới nhà cung cấp AI: ${e.message}');
    } catch (e) {
      throw AiException('Lỗi khi gọi AI: $e');
    }
  }

  /// Bỏ các tin báo lỗi cũ (chúng không phải câu trả lời thật) và chỉ giữ
  /// vài lượt gần nhất.
  List<ChatMessage> _recentHistory(List<ChatMessage> history) {
    final usable = history.where((m) => !m.isError).toList();
    if (usable.length <= maxHistoryMessages) return usable;
    return usable.sublist(usable.length - maxHistoryMessages);
  }

  /// Prompt gia sư: ép AI bám đúng dữ liệu đồ thị của người dùng và trả lời
  /// theo khuôn mà app hiển thị lại được.
  ///
  /// Quy tắc viết mã môn trong `[[...]]` là điều kiện để Citation Linker ở
  /// tầng UI biến chúng thành link bấm được — bỏ dòng đó thì AI trả về chữ
  /// thường và không còn link nào để bóc.
  String _systemPrompt(String context) {
    final sb = StringBuffer()
      ..writeln(
        'Bạn là gia sư học tập trong ứng dụng SE Knowledge, giúp sinh viên '
        'ngành Kỹ thuật phần mềm FPTU lập lộ trình học dựa trên đồ thị môn '
        'tiên quyết của chính họ.',
      )
      ..writeln()
      ..writeln('Quy tắc trả lời:')
      ..writeln('- Viết bằng tiếng Việt, ngắn gọn, đi thẳng vào việc.')
      ..writeln(
        '- Mỗi lần nhắc tới một môn học, viết mã môn trong hai ngoặc vuông, '
        'ví dụ [[CSD201]], để ứng dụng biến nó thành liên kết bấm được. '
        'Chỉ đặt mã môn vào trong ngoặc, tên môn viết ở ngoài.',
      )
      ..writeln(
        '- Khi gợi ý lộ trình, đánh số theo đúng thứ tự nên học và nêu lý do '
        'ngắn gọn dựa trên quan hệ tiên quyết.',
      )
      ..writeln(
        '- Chỉ dùng dữ liệu môn học được cung cấp bên dưới, không bịa thêm '
        'môn không có trong danh sách.',
      )
      ..writeln(
        '- Nếu dữ liệu không đủ để trả lời, nói thẳng là chưa có thông tin '
        'trong cơ sở dữ liệu thay vì suy đoán.',
      );
    if (context.isNotEmpty) {
      sb
        ..writeln()
        ..writeln('Dữ liệu hiện có trong cơ sở dữ liệu cục bộ của người dùng:')
        ..writeln(context);
    }
    return sb.toString();
  }

  // ------------------------------------------------------------------
  // GEMINI
  // ------------------------------------------------------------------

  Future<String> _streamGemini({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<ChatMessage> history,
    required String question,
    void Function(String delta)? onDelta,
  }) {
    final uri = Uri.parse(
      '${AppConstants.geminiBaseUrl}/models/$model:streamGenerateContent?alt=sse',
    );

    final contents = <Map<String, Object?>>[
      for (final m in history)
        {
          'role': m.isUser ? 'user' : 'model',
          'parts': [
            {'text': m.content},
          ],
        },
      {
        'role': 'user',
        'parts': [
          {'text': question},
        ],
      },
    ];

    return _consumeSse(
      uri: uri,
      headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
      body: jsonEncode({
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt},
          ],
        },
        'contents': contents,
        'generationConfig': {'temperature': 0.4, 'maxOutputTokens': 1024},
      }),
      onDelta: onDelta,
      extract: (chunk) {
        final candidates = chunk['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) return null;
        final parts =
            ((candidates.first as Map)['content'] as Map?)?['parts'] as List?;
        return parts
            ?.map((p) => (p as Map)['text'])
            .whereType<String>()
            .join();
      },
    );
  }

  // ------------------------------------------------------------------
  // OPENAI (và mọi endpoint tương thích OpenAI)
  // ------------------------------------------------------------------

  Future<String> _streamOpenAi({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<ChatMessage> history,
    required String question,
    void Function(String delta)? onDelta,
  }) {
    final uri = Uri.parse('${AppConstants.openAiBaseUrl}/chat/completions');

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      for (final m in history)
        {'role': m.isUser ? 'user' : 'assistant', 'content': m.content},
      {'role': 'user', 'content': question},
    ];

    return _consumeSse(
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': 0.4,
        'stream': true,
      }),
      onDelta: onDelta,
      extract: (chunk) {
        final choices = chunk['choices'] as List?;
        if (choices == null || choices.isEmpty) return null;
        return ((choices.first as Map)['delta'] as Map?)?['content'] as String?;
      },
    );
  }

  // ------------------------------------------------------------------

  /// Đọc một stream Server-Sent Events, ghép các mẩu chữ lại và bắn từng mẩu
  /// ra [onDelta]. [extract] là phần khác nhau giữa hai nhà cung cấp: lấy
  /// đoạn text nằm trong một chunk JSON.
  Future<String> _consumeSse({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    required String? Function(Map<String, Object?> chunk) extract,
    void Function(String delta)? onDelta,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..body = body;

      final response = await client.send(request).timeout(timeout);

      if (response.statusCode != 200) {
        final raw = await response.stream.bytesToString();
        throw AiException(_errorMessage(response.statusCode, _decode(raw)));
      }

      final buffer = StringBuffer();
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(timeout);

      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;

        final chunk = _decode(payload);
        if (chunk.isEmpty) continue;

        final delta = extract(chunk);
        if (delta == null || delta.isEmpty) continue;

        buffer.write(delta);
        onDelta?.call(delta);
      }

      final text = buffer.toString().trim();
      if (text.isEmpty) {
        throw AiException('Nhà cung cấp AI trả về nội dung rỗng.');
      }
      return text;
    } finally {
      client.close();
    }
  }

  Map<String, Object?> _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  String _errorMessage(int status, Map<String, Object?> body) {
    final error = body['error'];
    final detail = error is Map ? error['message'] : null;
    final base = switch (status) {
      400 => 'Request không hợp lệ',
      401 || 403 => 'API key sai hoặc không có quyền',
      404 => 'Không tìm thấy model (kiểm tra lại tên model trong Cài đặt)',
      429 => 'Vượt quá giới hạn gọi API, thử lại sau ít phút',
      >= 500 => 'Nhà cung cấp AI đang lỗi',
      _ => 'Gọi API thất bại',
    };
    return detail is String && detail.isNotEmpty
        ? '$base (HTTP $status): $detail'
        : '$base (HTTP $status).';
  }
}

class AiException implements Exception {
  final String message;
  AiException(this.message);
  @override
  String toString() => message;
}

/// Câu trả lời từ AI kèm tóm tắt ngữ cảnh Graph RAG đã gửi kèm (nếu có), để
/// UI hiển thị lại subgraph nào được dùng cho câu trả lời này.
class AiAnswer {
  final String text;
  final GraphRagSummary? ragSummary;
  const AiAnswer({required this.text, this.ragSummary});
}
