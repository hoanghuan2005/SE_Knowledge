import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import 'ai_service.dart';

/// Quản lý chat + câu hỏi gợi ý theo TỪNG môn học — dùng cho khung chat nhỏ
/// hiện ở sidebar bên phải khi bấm chọn một node trên đồ thị.
///
/// Khác với tab "Trợ lý AI" (dùng Graph RAG trên toàn bộ đồ thị), ngữ cảnh
/// gửi cho AI ở đây LUÔN là nội dung của một môn cụ thể (file .md trong
/// Obsidian Vault nếu đã xuất ra, hoặc mô tả lưu trong CSDL nếu chưa) — nên
/// gọi `AiService.ask(..., extraContext: ...)` thay vì bật Graph RAG.
///
/// Lưu theo bộ nhớ (`Map<subjectId, ...>`), không ghi xuống đĩa: mất khi tắt
/// app, giống một "phiên hỏi nhanh" chứ không phải lịch sử chat lâu dài như
/// `ChatSessionService`.
class SubjectChatService extends ChangeNotifier {
  SubjectChatService._();
  static final SubjectChatService instance = SubjectChatService._();

  final Map<int, List<ChatMessage>> _messages = {};
  final Map<int, List<String>> _suggestions = {};
  final Set<int> _loadingSuggestions = {};
  final Set<int> _sending = {};

  /// Phần câu trả lời đang chảy về, giữ riêng theo môn.
  ///
  /// Để ở service chứ không ở state của panel: người dùng bấm sang môn khác
  /// giữa chừng rồi quay lại thì vẫn thấy đúng đoạn đang chạy dở.
  final Map<int, String> _streamingText = {};

  List<ChatMessage> messagesOf(int subjectId) =>
      List.unmodifiable(_messages[subjectId] ?? const []);

  /// Rỗng khi chưa nhận được chữ nào (còn đang chờ mạng) hoặc đã xong.
  String streamingTextOf(int subjectId) => _streamingText[subjectId] ?? '';

  List<String> suggestionsOf(int subjectId) =>
      List.unmodifiable(_suggestions[subjectId] ?? const []);

  bool hasSuggestions(int subjectId) => _suggestions.containsKey(subjectId);

  bool isLoadingSuggestions(int subjectId) =>
      _loadingSuggestions.contains(subjectId);

  bool isSending(int subjectId) => _sending.contains(subjectId);

  /// Xoá sạch chat + gợi ý của một môn (dùng khi muốn "làm mới" phiên hỏi).
  void clear(int subjectId) {
    _messages.remove(subjectId);
    _suggestions.remove(subjectId);
    _streamingText.remove(subjectId);
    notifyListeners();
  }

  /// Sinh 4 câu hỏi gợi ý từ nội dung môn học. Chỉ chạy MỘT LẦN cho mỗi môn:
  /// kết quả giữ trong bộ nhớ, lần sau mở lại cùng môn không gọi AI lại.
  Future<void> ensureSuggestions(int subjectId, String context) async {
    if (_suggestions.containsKey(subjectId) ||
        _loadingSuggestions.contains(subjectId)) {
      return;
    }
    _loadingSuggestions.add(subjectId);
    notifyListeners();
    try {
      final answer = await AiService.instance.ask(
        question:
            'Dựa trên nội dung môn học bên dưới, hãy đề xuất đúng 4 câu hỏi '
            'ngắn gọn (mỗi câu một dòng, không đánh số thứ tự, không thêm '
            'lời giải thích nào khác) mà một sinh viên mới đọc có thể muốn '
            'hỏi thêm về môn này.',
        includeKnowledgeContext: false,
        extraContext: context,
        // Việc này chỉ cần 4 dòng chữ, không cần bộ quy tắc gia sư đầy đủ.
        minimalPrompt: true,
        // Và cũng không cần ăn vào hạn mức của model đang dùng để trả lời.
        preferLightModel: true,
      );
      _suggestions[subjectId] = _splitLines(answer.text);
    } catch (_) {
      // Không có key / lỗi mạng: coi như không có gợi ý, người dùng vẫn hỏi
      // thẳng qua ô chat bên dưới được.
      _suggestions[subjectId] = const [];
    } finally {
      _loadingSuggestions.remove(subjectId);
      notifyListeners();
    }
  }

  /// Bỏ gợi ý cũ và sinh lại — dùng cho nút "Tạo gợi ý khác".
  Future<void> regenerateSuggestions(int subjectId, String context) async {
    _suggestions.remove(subjectId);
    await ensureSuggestions(subjectId, context);
  }

  Future<void> send({
    required int subjectId,
    required String context,
    required String question,
  }) async {
    final history = List<ChatMessage>.from(_messages[subjectId] ?? const []);
    _messages.putIfAbsent(subjectId, () => []).add(ChatMessage.user(question));
    _sending.add(subjectId);
    notifyListeners();

    try {
      final answer = await AiService.instance.ask(
        question: question,
        history: history,
        includeKnowledgeContext: false,
        extraContext: context,
        onDelta: (delta) {
          _streamingText[subjectId] = (_streamingText[subjectId] ?? '') + delta;
          notifyListeners();
        },
      );
      _messages[subjectId]!.add(ChatMessage.assistant(answer.text));
    } on AiException catch (e) {
      _messages[subjectId]!.add(
        ChatMessage.assistant(e.message, isError: true),
      );
    } catch (e) {
      _messages[subjectId]!.add(
        ChatMessage.assistant(e.toString(), isError: true),
      );
    } finally {
      // Đoạn đang chảy dở đã thành tin nhắn hoàn chỉnh (hoặc bị bỏ vì lỗi),
      // giữ lại nữa sẽ hiện trùng hai lần.
      _streamingText.remove(subjectId);
      _sending.remove(subjectId);
      notifyListeners();
    }
  }

  /// Bóc câu trả lời (mỗi dòng một câu hỏi) thành danh sách gợi ý sạch, bỏ
  /// gạch đầu dòng / số thứ tự AI có thể tự thêm dù đã dặn không cần.
  List<String> _splitLines(String text) => cleanSuggestionLines(text);
}

/// Bóc câu trả lời của AI thành danh sách câu hỏi gợi ý sạch.
///
/// Làm hai việc, đều vì AI không chịu nghe dặn hoàn toàn:
///
/// 1. Bỏ gạch đầu dòng / số thứ tự AI tự thêm dù prompt đã dặn không cần.
/// 2. Gỡ cặp ngoặc `[[...]]` quanh mã môn. Prompt hệ thống bắt AI bọc mã môn
///    như vậy để tầng hiển thị biến chúng thành link bấm được, nhưng gợi ý là
///    nhãn nút chữ thuần, không đi qua bộ bóc link đó — để nguyên thì người
///    dùng thấy `[[JPD113]]` lù lù trên nút. Gỡ tại đây thay vì dặn AI đừng
///    viết, vì cách này chắc chắn còn lời dặn thì không.
///
/// Hàm thuần, tách khỏi service để test được mà không cần gọi mạng.
List<String> cleanSuggestionLines(String text) {
  final wikiLink = RegExp(r'\[\[([^\[\]]+?)\]\]');

  return text
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'^[\s\-•*\d\.\)]+'), '').trim())
      .map((l) => l.replaceAllMapped(
            wikiLink,
            (m) => m.group(1)!.split(RegExp(r'[|#]')).first.trim(),
          ))
      .where((l) => l.isNotEmpty)
      .take(4)
      .toList();
}
