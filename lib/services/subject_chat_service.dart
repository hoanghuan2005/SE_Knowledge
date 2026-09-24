import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
/// Chat được **ghi xuống đĩa** qua `SharedPreferences`, mở lại app vẫn còn.
/// App là "second brain" local-first, nên hỏi AI về một môn rồi tuần sau quay
/// lại thấy trắng trơn là mâu thuẫn với chính tiền đề đó.
///
/// Nhưng có trần, vì `SharedPreferences` nạp TOÀN BỘ vào RAM lúc khởi động:
/// không chặn thì sau vài tuần dùng, 64 môn × chat dài thành một chuỗi JSON
/// vài trăm KB phải decode mỗi lần mở app. Xem [trimForStorage].
///
/// Câu hỏi gợi ý và đoạn chữ đang stream thì KHÔNG lưu: gợi ý phải đổi theo
/// đề cương nên cần vân tay dữ liệu mới lưu đúng được (giống cache bên tab
/// Học lực), còn đoạn stream dở vốn đã thành tin nhắn hoàn chỉnh.

/// Số tin nhắn giữ lại cho mỗi môn.
///
/// `AiService.maxHistoryMessages` = 8, tức chỉ 8 tin cuối được gửi cho AI.
/// Giữ nhiều hơn chỉ có giá trị đọc lại, nên 12 (6 lượt hỏi đáp) là đủ.
const int maxStoredMessagesPerSubject = 12;

/// Số môn giữ lại, tính theo môn có hoạt động gần nhất.
const int maxStoredSubjects = 12;

/// Cắt bớt lịch sử chat cho vừa trần trước khi ghi xuống đĩa.
///
/// Giữ **tin mới nhất** trong mỗi môn, và giữ **môn có hoạt động gần nhất**
/// — đo bằng thời điểm của tin cuối cùng, chứ không phải thứ tự trong Map.
/// Môn rỗng bị bỏ hẳn để không chiếm suất của môn có chat thật.
///
/// Hàm thuần, tách khỏi service để test được mà không cần SharedPreferences.
Map<int, List<ChatMessage>> trimForStorage(
  Map<int, List<ChatMessage>> messages,
) {
  final withContent = <int, List<ChatMessage>>{};
  for (final entry in messages.entries) {
    if (entry.value.isEmpty) continue;
    withContent[entry.key] = entry.value.length <= maxStoredMessagesPerSubject
        ? List<ChatMessage>.from(entry.value)
        : entry.value
            .sublist(entry.value.length - maxStoredMessagesPerSubject)
            .toList();
  }

  if (withContent.length <= maxStoredSubjects) return withContent;

  final byRecency = withContent.keys.toList()
    ..sort((a, b) {
      final at = withContent[a]!.last.at;
      final bt = withContent[b]!.last.at;
      final byTime = bt.compareTo(at);
      // Hai môn cùng mốc thời gian (test, hoặc hai tin trong cùng mili giây)
      // thì xếp theo id để kết quả không phụ thuộc thứ tự duyệt Map.
      return byTime != 0 ? byTime : a.compareTo(b);
    });

  return {
    for (final id in byRecency.take(maxStoredSubjects)) id: withContent[id]!,
  };
}

/// Bóc chuỗi JSON đã lưu thành lịch sử chat theo môn.
///
/// Dữ liệu hỏng thì trả về rỗng chứ không ném lỗi: mất lịch sử chat khó chịu
/// hơn nhiều nếu nó làm app không mở lên được. Bỏ qua từng khoá hỏng thay vì
/// vứt cả tệp, để một môn lỗi không kéo theo các môn còn lại.
///
/// Hàm thuần, tách khỏi service để test được mà không cần SharedPreferences.
Map<int, List<ChatMessage>> parseStoredHistory(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  final Map<String, dynamic> decoded;
  try {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>) return {};
    decoded = value;
  } catch (_) {
    return {};
  }

  final result = <int, List<ChatMessage>>{};
  for (final entry in decoded.entries) {
    final id = int.tryParse(entry.key);
    if (id == null) continue;
    try {
      final list = entry.value as List;
      final messages = [
        for (final m in list) ChatMessage.fromJson(m as Map<String, dynamic>),
      ];
      if (messages.isNotEmpty) result[id] = messages;
    } catch (_) {
      continue;
    }
  }
  return result;
}

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

  static const String _storageKey = 'subject_chat_history_v1';

  /// Chặn nạp lại đè lên tin nhắn vừa gửi trong phiên này.
  bool _restored = false;

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
    _save();
  }

  /// Nạp lịch sử chat đã lưu. Gọi một lần lúc khởi động app.
  ///
  /// Đọc đĩa hỏng thì bỏ qua và đi tiếp — xem [parseStoredHistory].
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final raw =
          (await SharedPreferences.getInstance()).getString(_storageKey);
      _messages.addAll(parseStoredHistory(raw));
      notifyListeners();
    } catch (_) {
      // Không đọc được SharedPreferences thì mở app với lịch sử rỗng.
    }
  }

  /// Ghi xuống đĩa sau khi cắt cho vừa trần.
  ///
  /// Không `await` ở chỗ gọi: người dùng không cần đợi đĩa mới thấy tin nhắn
  /// hiện ra, và lỗi ghi cũng không nên chặn cuộc hội thoại.
  Future<void> _save() async {
    try {
      final trimmed = trimForStorage(_messages);
      final prefs = await SharedPreferences.getInstance();
      if (trimmed.isEmpty) {
        await prefs.remove(_storageKey);
        return;
      }
      await prefs.setString(
        _storageKey,
        jsonEncode({
          for (final e in trimmed.entries)
            '${e.key}': [for (final m in e.value) m.toJson()],
        }),
      );
    } catch (_) {
      // Ghi hỏng thì thôi, phiên hiện tại vẫn chạy bình thường trong RAM.
    }
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
      // Ghi ở `finally` để cả câu trả lời lẫn tin báo lỗi đều được lưu —
      // mở lại app mà thấy câu hỏi treo lơ lửng không có hồi đáp thì khó
      // hiểu hơn là thấy đúng thông báo lỗi đã hiện lúc đó.
      _save();
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
