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
/// trực tiếp từ máy người dùng tới nhà cung cấp AI.
class AiService {
  AiService._();
  static final AiService instance = AiService._();

  final SettingsService _settings = SettingsService.instance;
  final GraphRagService _graphRag = GraphRagService.instance;

  static const Duration timeout = Duration(seconds: 45);

  Future<bool> get isConfigured async {
    final key = await _settings.getApiKey();
    return key != null && key.trim().isNotEmpty;
  }

  /// Gửi một lượt hội thoại. [history] là các tin nhắn trước đó (cũ -> mới).
  ///
  /// Khi [includeKnowledgeContext] bật, câu hỏi được đối chiếu với đồ thị
  /// tiên quyết trong SQLite (Graph RAG) để chỉ gửi kèm subgraph liên quan
  /// trực tiếp, thay vì toàn bộ CSDL.
  Future<AiAnswer> ask({
    required String question,
    List<ChatMessage> history = const [],
    bool includeKnowledgeContext = true,
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
    final systemPrompt = _systemPrompt(ragContext?.promptText ?? '');

    try {
      final text = provider == AppConstants.providerOpenAi
          ? await _askOpenAi(
              apiKey: apiKey,
              model: model,
              systemPrompt: systemPrompt,
              history: history,
              question: question,
            )
          : await _askGemini(
              apiKey: apiKey,
              model: model,
              systemPrompt: systemPrompt,
              history: history,
              question: question,
            );
      return AiAnswer(text: text, ragSummary: ragContext?.summary);
    } on AiException {
      rethrow;
    } on http.ClientException catch (e) {
      throw AiException('Không kết nối được tới nhà cung cấp AI: ${e.message}');
    } catch (e) {
      throw AiException('Lỗi khi gọi AI: $e');
    }
  }

  String _systemPrompt(String context) {
    final sb = StringBuffer()
      ..writeln(
        'Bạn là trợ lý học tập trong ứng dụng SE Knowledge, một app desktop '
        'quản lý bản đồ tri thức môn học theo phong cách Obsidian.',
      )
      ..writeln(
        'Trả lời ngắn gọn, bằng tiếng Việt, tập trung vào lộ trình học và '
        'quan hệ tiên quyết giữa các môn.',
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

  Future<String> _askGemini({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<ChatMessage> history,
    required String question,
  }) async {
    final uri = Uri.parse(
      '${AppConstants.geminiBaseUrl}/models/$model:generateContent',
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

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: jsonEncode({
            'systemInstruction': {
              'parts': [
                {'text': systemPrompt},
              ],
            },
            'contents': contents,
            'generationConfig': {'temperature': 0.4, 'maxOutputTokens': 1024},
          }),
        )
        .timeout(timeout);

    final body = _decode(response);

    if (response.statusCode != 200) {
      throw AiException(_errorMessage(response.statusCode, body));
    }

    final candidates = body['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw AiException('Gemini không trả về nội dung nào.');
    }
    final parts =
        ((candidates.first as Map)['content'] as Map?)?['parts'] as List?;
    final text = parts
        ?.map((x) => (x as Map)['text'])
        .whereType<String>()
        .join('\n')
        .trim();

    if (text == null || text.isEmpty) {
      throw AiException('Gemini trả về nội dung rỗng.');
    }
    return text;
  }

  // ------------------------------------------------------------------
  // OPENAI (và mọi endpoint tương thích OpenAI)
  // ------------------------------------------------------------------

  Future<String> _askOpenAi({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<ChatMessage> history,
    required String question,
  }) async {
    final uri = Uri.parse('${AppConstants.openAiBaseUrl}/chat/completions');

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      for (final m in history)
        {'role': m.isUser ? 'user' : 'assistant', 'content': m.content},
      {'role': 'user', 'content': question},
    ];

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'temperature': 0.4,
          }),
        )
        .timeout(timeout);

    final body = _decode(response);

    if (response.statusCode != 200) {
      throw AiException(_errorMessage(response.statusCode, body));
    }

    final choices = body['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw AiException('OpenAI không trả về nội dung nào.');
    }
    final text =
        ((choices.first as Map)['message'] as Map?)?['content'] as String?;

    if (text == null || text.trim().isEmpty) {
      throw AiException('OpenAI trả về nội dung rỗng.');
    }
    return text.trim();
  }

  // ------------------------------------------------------------------

  Map<String, Object?> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
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
