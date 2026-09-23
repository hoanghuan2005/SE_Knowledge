import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';
import '../models/graph_rag_context.dart';
import '../utils/app_constants.dart';
import 'graph_rag_service.dart';
import 'settings_service.dart';

/// Gom các dòng thô của một SSE stream thành payload theo từng sự kiện.
///
/// Tách thành hàm thuần (không đụng `http`/`AiService`) để test được bằng
/// `Stream<String>` giả lập, không cần giả lập kết nối mạng thật.
///
/// OpenAI luôn nén JSON của một sự kiện vào đúng một dòng `data: {...}`,
/// nhưng Gemini đôi khi trải JSON của CÙNG một sự kiện ra nhiều dòng — chỉ
/// dòng đầu có tiền tố `data:`, các dòng sau là phần còn lại của khối JSON
/// đó, không lặp lại tiền tố. Bản cũ coi mỗi dòng phải tự đủ nghĩa
/// (`if (!line.startsWith('data:')) continue;`), nên phần JSON trải dòng bị
/// cắt cụt và rơi rụng âm thầm — nhẹ thì mất vài chữ giữa câu trả lời, nặng
/// thì toàn bộ nội dung rơi hết, báo "nhà cung cấp AI trả về nội dung rỗng"
/// dù AI đã trả lời thật.
///
/// Coi mỗi dòng không rỗng là thuộc sự kiện đang mở, dòng trống là ranh giới
/// kết thúc sự kiện — nhờ vậy JSON trải dòng vẫn được ghép đủ trước khi
/// decode.
Stream<String> sseEventPayloads(Stream<String> lines) async* {
  final eventLines = <String>[];

  await for (final line in lines) {
    if (line.isEmpty) {
      if (eventLines.isNotEmpty) {
        yield eventLines.join('\n').trim();
        eventLines.clear();
      }
      continue;
    }
    if (line.startsWith('data:')) {
      eventLines.add(line.substring(5).trimLeft());
    } else if (eventLines.isNotEmpty) {
      // Dòng tiếp theo của cùng một khối JSON trải dòng.
      eventLines.add(line);
    }
  }
  if (eventLines.isNotEmpty) {
    yield eventLines.join('\n').trim();
  }
}

/// Mã lỗi HTTP đáng gọi lại: quá nhịp gọi và các lỗi phía máy chủ — chính
/// nhà cung cấp gọi chúng là tạm thời ("Spikes in demand are usually
/// temporary").
///
/// Cố tình KHÔNG gồm 400/401/403/404: sai key, sai tên model hay request
/// hỏng thì gọi lại bao nhiêu lần cũng hỏng, chỉ tổ bắt người dùng chờ thêm
/// rồi vẫn nhận đúng lỗi đó.
bool isTransientAiStatus(int status) =>
    status == 429 || (status >= 500 && status <= 599);

/// Lấy phần chữ **hiển thị được** từ một chunk SSE của Gemini.
///
/// Model đời mới trả kèm những `parts` gắn cờ `thought: true` — đó là phần
/// nháp suy nghĩ nội bộ, không phải câu trả lời. Bản cũ ghép thẳng mọi part
/// nên câu trả lời lẫn cả tiếng Anh kiểu "Let's cite MAE101 (7.9", đồng thời
/// phần nháp ăn hết hạn mức token khiến câu trả lời thật bị cắt ngang.
///
/// Hàm thuần, tách khỏi `AiService` để test được mà không cần gọi mạng.
String geminiVisibleText(Map<String, Object?> chunk) {
  final candidates = chunk['candidates'] as List?;
  if (candidates == null || candidates.isEmpty) return '';

  final parts = ((candidates.first as Map)['content'] as Map?)?['parts'];
  if (parts is! List) return '';

  final sb = StringBuffer();
  for (final part in parts) {
    if (part is! Map) continue;
    if (part['thought'] == true) continue;
    final value = part['text'];
    if (value is String) sb.write(value);
  }
  return sb.toString();
}

/// Lý do model dừng sinh chữ, nếu chunk này có kèm.
String? geminiFinishReason(Map<String, Object?> chunk) {
  final candidates = chunk['candidates'] as List?;
  if (candidates == null || candidates.isEmpty) return null;
  final reason = (candidates.first as Map)['finishReason'];
  return reason is String && reason.isNotEmpty ? reason : null;
}

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

  /// Trần độ dài câu trả lời.
  ///
  /// Trước để 1024 và bị cắt ngang giữa câu ở những câu hỏi dạng lộ trình.
  /// Model đời mới còn tiêu một phần hạn mức này cho phần suy nghĩ nội bộ,
  /// nên phần chữ thật sự hiện ra còn ít hơn nhiều so với con số cấu hình.
  /// Chỉ bị tính tiền theo số token thực sinh ra, nên để rộng không làm đắt
  /// thêm với câu trả lời ngắn.
  static const int maxOutputTokens = 4096;

  /// Số lần gọi lại khi nhà cung cấp báo lỗi tạm thời (quá tải, quá nhịp).
  static const int maxRetryAttempts = 2;

  /// Giãn cách giữa các lần thử lại. Ngắn đủ để người dùng không thấy treo,
  /// thưa dần để đợt quá tải kịp qua và không tự dồn thêm tải lên server.
  static const List<Duration> retryDelays = [
    Duration(milliseconds: 800),
    Duration(seconds: 2),
  ];


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
  /// [extraContext] là ngữ cảnh do phía gọi tự chuẩn bị (ví dụ khung chat
  /// gắn theo một môn học). Khi có nó, Graph RAG toàn đồ thị bị bỏ qua hoàn
  /// toàn để câu trả lời không lẫn dữ liệu của môn khác.
  ///
  /// [onContext] gọi ngay khi trích xong ngữ cảnh (trước lúc chờ mạng), còn
  /// [onDelta] gọi mỗi lần nhận thêm một mẩu chữ, để UI hiện dần.
  Future<AiAnswer> ask({
    required String question,
    List<ChatMessage> history = const [],
    bool includeKnowledgeContext = true,
    /// Ngữ cảnh cố định do màn hình gọi tự cung cấp (ví dụ nội dung file .md
    /// của một môn cụ thể). Khi có giá trị này, Graph RAG bị bỏ qua hoàn
    /// toàn — dùng cho chat theo từng môn học (xem `SubjectChatService`),
    /// khác với chat chung ở tab "Trợ lý AI" vốn dùng Graph RAG trên toàn
    /// đồ thị.
    String? extraContext,
    /// Bật khi [extraContext] có kèm điểm của sinh viên, để prompt hệ thống
    /// thêm bộ quy tắc nhận xét năng lực. Đường Graph RAG tự suy ra được nên
    /// không cần truyền.
    bool extraContextHasGrades = false,

    /// Dùng prompt hệ thống tối giản thay cho bộ quy tắc gia sư đầy đủ.
    ///
    /// Dành cho tác vụ phụ không phải trả lời người dùng — hiện chỉ có việc
    /// sinh 4 câu hỏi gợi ý. Bộ quy tắc gia sư nặng ~380 token và bàn toàn
    /// chuyện không liên quan tới việc đó (cách đánh số lộ trình, cách gắn
    /// nhãn phần tự học, cách bọc mã môn cho tầng hiển thị bóc link).
    bool minimalPrompt = false,
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

    GraphRagContext? ragContext;
    if (extraContext == null && includeKnowledgeContext) {
      ragContext = await _graphRag.buildContext(question);
      onContext?.call(ragContext.summary);
    }

    final context = extraContext ?? ragContext?.promptText ?? '';
    final systemPrompt = minimalPrompt
        ? _minimalSystemPrompt(context)
        : _systemPrompt(
            context,
            hasGrades: extraContext != null
                ? extraContextHasGrades
                : (ragContext?.summary.includesTranscript ?? false),
          );
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

  /// Prompt cho tác vụ phụ: chỉ giữ hai ràng buộc thật sự có tác dụng.
  ///
  /// Soi từng quy tắc trong [_systemPrompt] xem giúp được gì cho việc sinh 4
  /// câu hỏi gợi ý: cách đánh số lộ trình, cách gắn nhãn phần tự học, cách
  /// xử lý khi chương trình thiếu môn — đều vô can. Riêng quy tắc bọc mã môn
  /// trong `[[...]]` còn có hại, vì gợi ý là nhãn nút chữ thuần chứ không đi
  /// qua bộ bóc link, nên dấu ngoặc lòi ra nguyên xi.
  ///
  /// Còn lại đúng hai điều cần giữ: viết tiếng Việt ngắn gọn, và không bịa ra
  /// môn không có trong dữ liệu.
  String _minimalSystemPrompt(String context) {
    final sb = StringBuffer()
      ..writeln(
        'Bạn đọc dữ liệu môn học của một sinh viên và làm đúng yêu cầu được '
        'giao, không thêm lời dẫn hay giải thích ngoài yêu cầu đó.',
      )
      ..writeln('- Viết bằng tiếng Việt, ngắn gọn.')
      ..writeln(
        '- Chỉ dùng dữ liệu bên dưới, không nhắc tới môn học không có trong '
        'đó.',
      );
    if (context.isNotEmpty) {
      sb
        ..writeln()
        ..writeln('Dữ liệu môn học:')
        ..writeln(context);
    }
    return sb.toString();
  }

  /// Prompt gia sư: ép AI bám đúng dữ liệu đồ thị của người dùng và trả lời
  /// theo khuôn mà app hiển thị lại được.
  ///
  /// Quy tắc viết mã môn trong `[[...]]` là điều kiện để Citation Linker ở
  /// tầng UI biến chúng thành link bấm được — bỏ dòng đó thì AI trả về chữ
  /// thường và không còn link nào để bóc.
  String _systemPrompt(String context, {bool hasGrades = false}) {
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
        '- Dữ liệu bên dưới là nguồn DUY NHẤT cho mọi khẳng định về chương '
        'trình học: mã môn, tên môn, học kỳ, quan hệ tiên quyết, điểm số. '
        'Không bịa ra môn không có trong danh sách, không suy đoán tiên '
        'quyết hay điểm.',
      )
      ..writeln(
        '- Ngoài phạm vi đó, được phép khuyên thêm kỹ năng, công cụ hay chủ '
        'đề nên tự học khi câu hỏi cần (nhất là câu hỏi định hướng nghề '
        'nghiệp) — nhưng phải nói rõ đó là phần TỰ HỌC ngoài khung chương '
        'trình, không phải môn trong chương trình.',
      )
      ..writeln(
        '- Chỉ đặt trong hai ngoặc vuông những mã môn có thật trong danh sách '
        'được cung cấp. Phần tự học ngoài chương trình viết chữ thường, tuyệt '
        'đối không đặt trong ngoặc vuông.',
      )
      ..writeln(
        '- Khi chương trình không có môn nào dạy chủ đề được hỏi, nói thẳng '
        'điều đó trước, rồi mới gợi ý môn nền tảng gần nhất trong chương '
        'trình và hướng tự học bổ sung.',
      );

    // Bộ quy tắc riêng cho lúc ngữ cảnh có điểm. Không có điểm mà vẫn nhét
    // mấy dòng này vào thì AI đi tìm số liệu không tồn tại rồi bịa ra.
    if (hasGrades) {
      sb
        ..writeln()
        ..writeln('Quy tắc khi nhận xét về năng lực học tập:')
        ..writeln(
          '- Phải dẫn số liệu cụ thể: mã môn kèm điểm. Không nói chung chung '
          'kiểu "bạn khá tốt".',
        )
        ..writeln(
          '- Chỉ kết luận mạnh/yếu khi một nhóm có ít nhất 3 môn đã có điểm. '
          'Ít hơn thì nói rõ là chưa đủ dữ liệu để kết luận.',
        )
        ..writeln(
          '- Không suy diễn về năng lực từ môn chưa học hoặc môn không có '
          'điểm.',
        )
        ..writeln(
          '- Khi đề xuất cải thiện, gắn với môn sắp học trong đồ thị tiên '
          'quyết, nêu rõ vì sao môn nền yếu ảnh hưởng tới môn nào phía sau.',
        )
        ..writeln(
          '- Đề xuất phải hành động được và có thể kiểm chứng trong một kỳ '
          'học, không đưa lời khuyên chung chung kiểu "hãy chăm chỉ hơn".',
        )
        ..writeln(
          '- Giữ giọng xây dựng. Điểm thấp là dữ liệu để lập kế hoạch, không '
          'phải để phán xét người học.',
        );
    }
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
  }) async {
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

    String? finishReason;

    final text = await _consumeSse(
      uri: uri,
      headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
      body: jsonEncode({
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt},
          ],
        },
        'contents': contents,
        'generationConfig': {
          'temperature': 0.4,
          'maxOutputTokens': maxOutputTokens,
        },
      }),
      onDelta: onDelta,
      extract: (chunk) {
        finishReason = geminiFinishReason(chunk) ?? finishReason;
        return geminiVisibleText(chunk);
      },
    );

    return _appendFinishNotice(text, finishReason);
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
  }) async {
    final uri = Uri.parse('${AppConstants.openAiBaseUrl}/chat/completions');

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      for (final m in history)
        {'role': m.isUser ? 'user' : 'assistant', 'content': m.content},
      {'role': 'user', 'content': question},
    ];

    String? finishReason;

    final text = await _consumeSse(
      uri: uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': 0.4,
        'max_tokens': maxOutputTokens,
        'stream': true,
      }),
      onDelta: onDelta,
      extract: (chunk) {
        final choices = chunk['choices'] as List?;
        if (choices == null || choices.isEmpty) return null;
        final choice = choices.first as Map;

        final reason = choice['finish_reason'];
        if (reason is String && reason.isNotEmpty) finishReason = reason;

        return (choice['delta'] as Map?)?['content'] as String?;
      },
    );

    return _appendFinishNotice(text, finishReason);
  }

  /// Nói thẳng khi câu trả lời bị cắt giữa chừng.
  ///
  /// Không có dòng này thì người dùng chỉ thấy câu văn đứt ngang và tưởng app
  /// hỏng — đúng như đã xảy ra lúc câu trả lời dừng tại "Tuy nhiên".
  String _appendFinishNotice(String text, String? finishReason) {
    return switch (finishReason) {
      'MAX_TOKENS' || 'length' =>
        '$text\n\n_(Câu trả lời bị cắt vì chạm giới hạn độ dài. Hỏi lại gọn '
            'hơn hoặc chia nhỏ câu hỏi để nhận câu trả lời đầy đủ.)_',
      'SAFETY' || 'content_filter' =>
        '$text\n\n_(Nhà cung cấp AI đã chặn một phần nội dung.)_',
      'RECITATION' =>
        '$text\n\n_(Nhà cung cấp AI dừng vì nội dung trùng nguồn có bản quyền.)_',
      _ => text,
    };
  }

  // ------------------------------------------------------------------

  /// Gọi [_consumeSseOnce], tự thử lại khi nhà cung cấp báo lỗi tạm thời.
  ///
  /// Quá tải (503) hay chạm giới hạn nhịp gọi (429) là chuyện thường gặp và
  /// thường chỉ kéo dài vài giây. Bắt người dùng tự gõ lại câu hỏi trong lúc
  /// demo là không chấp nhận được, nên thử lại ngay tại đây.
  ///
  /// Chỉ thử lại khi lỗi xảy ra **trước** lúc phát chữ đầu tiên: chữ đã hiện
  /// lên màn hình rồi mà gọi lại thì câu trả lời sẽ bị lặp đoạn đầu.
  /// [_consumeSseOnce] chỉ ném [_TransientFailure] ở khâu kiểm tra mã trạng
  /// thái, tức luôn trước khi có chữ nào chảy ra.
  Future<String> _consumeSse({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    required String? Function(Map<String, Object?> chunk) extract,
    void Function(String delta)? onDelta,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _consumeSseOnce(
          uri: uri,
          headers: headers,
          body: body,
          extract: extract,
          onDelta: onDelta,
        );
      } on _TransientFailure catch (failure) {
        if (attempt >= maxRetryAttempts) throw AiException(failure.message);
        await Future<void>.delayed(retryDelays[attempt]);
      }
    }
  }

  Future<String> _consumeSseOnce({
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
        final message = _errorMessage(response.statusCode, _decode(raw));
        // Sai key, sai tên model, request hỏng... thì thử lại bao nhiêu lần
        // cũng vậy — chỉ tổ tốn thêm quota và bắt người dùng chờ.
        if (isTransientAiStatus(response.statusCode)) {
          throw _TransientFailure(message);
        }
        throw AiException(message);
      }

      final buffer = StringBuffer();
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(timeout);

      await for (final payload in sseEventPayloads(lines)) {
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

/// Lỗi nhà cung cấp tự nhận là tạm thời (quá tải, quá nhịp gọi).
///
/// Chỉ sống trong nội bộ [AiService]: hoặc được nuốt đi vì lần thử lại sau
/// thành công, hoặc hết lượt thử thì chuyển thành [AiException] cho UI.
class _TransientFailure implements Exception {
  final String message;
  _TransientFailure(this.message);
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
