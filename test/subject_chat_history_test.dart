import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/models/chat_message.dart';
import 'package:se_knowledge/services/subject_chat_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kiểm thử việc lưu lịch sử chat theo môn xuống đĩa.
///
/// Trần tồn tại vì `SharedPreferences` nạp TOÀN BỘ vào RAM lúc khởi động:
/// không chặn thì sau vài tuần dùng, 64 môn × chat dài thành một chuỗi JSON
/// vài trăm KB phải decode mỗi lần mở app.
void main() {
  ChatMessage msg(String text, {int minutesAgo = 0}) => ChatMessage(
        role: ChatRole.user,
        content: text,
        at: DateTime(2026, 1, 1, 12).subtract(Duration(minutes: minutesAgo)),
      );

  group('trimForStorage', () {
    test('dưới trần thì giữ nguyên', () {
      final kept = trimForStorage({
        1: [msg('a'), msg('b')],
      });
      expect(kept[1]!.map((m) => m.content), ['a', 'b']);
    });

    test('quá trần thì giữ tin MỚI nhất', () {
      final many = [
        for (var i = 0; i < maxStoredMessagesPerSubject + 5; i++) msg('tin$i'),
      ];
      final kept = trimForStorage({1: many})[1]!;

      expect(kept.length, maxStoredMessagesPerSubject);
      expect(kept.last.content, 'tin${maxStoredMessagesPerSubject + 4}');
      expect(kept.first.content, 'tin5');
    });

    test('bỏ môn không có tin nào, khỏi chiếm suất', () {
      final kept = trimForStorage({1: [], 2: [msg('a')]});
      expect(kept.keys, [2]);
    });

    test('quá số môn thì giữ môn có hoạt động gần nhất', () {
      final input = <int, List<ChatMessage>>{
        for (var i = 0; i < maxStoredSubjects + 4; i++)
          // Môn id càng lớn càng cũ.
          i: [msg('tin của môn $i', minutesAgo: i)],
      };
      final kept = trimForStorage(input);

      expect(kept.length, maxStoredSubjects);
      expect(kept.keys.toSet(), {for (var i = 0; i < maxStoredSubjects; i++) i});
    });

    test('không sửa map gốc', () {
      final original = {
        1: [for (var i = 0; i < 30; i++) msg('tin$i')],
      };
      trimForStorage(original);
      expect(original[1]!.length, 30);
    });
  });

  _parsing();

  group('lưu và nạp lại', () {
    final service = SubjectChatService.instance;

    test('nạp lại được hội thoại đã lưu', () async {
      SharedPreferences.setMockInitialValues({
        'subject_chat_history_v1':
            '{"7":[{"role":"user","content":"JPD113 học gì"},'
            '{"role":"assistant","content":"Tiếng Nhật sơ cấp."}]}',
      });
      await service.restore();

      final messages = service.messagesOf(7);
      expect(messages.length, 2);
      expect(messages.first.content, 'JPD113 học gì');
      expect(messages.first.isUser, isTrue);
      expect(messages.last.isUser, isFalse);
    });

    test('dữ liệu hỏng thì bỏ qua, không làm chết app', () async {
      await expectLater(service.restore(), completes);
    });
  });
}

/// Bóc dữ liệu đã lưu — tách khỏi service nên test được thẳng mọi ca hỏng,
/// không vướng cờ "đã nạp một lần" của singleton.
void _parsing() {
  group('parseStoredHistory', () {
    test('chuỗi rỗng hoặc null thì ra map rỗng', () {
      expect(parseStoredHistory(null), isEmpty);
      expect(parseStoredHistory(''), isEmpty);
    });

    test('JSON hỏng thì ra map rỗng chứ không ném lỗi', () {
      expect(parseStoredHistory('đây không phải json'), isEmpty);
      expect(parseStoredHistory('[1,2,3]'), isEmpty);
      expect(parseStoredHistory('"chuỗi trơn"'), isEmpty);
    });

    test('một môn hỏng không kéo theo các môn còn lại', () {
      final kept = parseStoredHistory(
        '{"1":"đáng lẽ phải là mảng",'
        '"2":[{"role":"user","content":"còn nguyên"}]}',
      );
      expect(kept.keys, [2]);
      expect(kept[2]!.single.content, 'còn nguyên');
    });

    test('khoá không phải số thì bỏ qua', () {
      expect(
        parseStoredHistory('{"abc":[{"role":"user","content":"x"}]}'),
        isEmpty,
      );
    });

    test('môn có mảng rỗng thì không tạo khoá thừa', () {
      expect(parseStoredHistory('{"3":[]}'), isEmpty);
    });
  });
}
