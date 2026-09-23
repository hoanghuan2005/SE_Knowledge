import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/services/ai_service.dart';

/// Kiểm thử phần gom sự kiện SSE — logic thuần Dart, không cần mạng thật.
///
/// Bug thật đã xảy ra: bản cũ coi mỗi dòng phải tự chứa trọn một JSON, nên
/// khi Gemini trải JSON của một sự kiện ra nhiều dòng (chỉ dòng đầu có tiền
/// tố "data:"), phần còn lại bị `continue` bỏ qua và JSON hỏng âm thầm — nhẹ
/// thì câu trả lời đứt quãng, nặng thì rỗng hoàn toàn dù AI đã trả lời thật.
void main() {
  Future<List<String>> collect(List<String> rawLines) =>
      sseEventPayloads(Stream.fromIterable(rawLines)).toList();

  group('sseEventPayloads', () {
    test('một sự kiện gói gọn trong một dòng (kiểu OpenAI)', () async {
      final payloads = await collect([
        'data: {"choices":[{"delta":{"content":"Xin"}}]}',
        '',
        'data: {"choices":[{"delta":{"content":" chào"}}]}',
        '',
      ]);
      expect(payloads, [
        '{"choices":[{"delta":{"content":"Xin"}}]}',
        '{"choices":[{"delta":{"content":" chào"}}]}',
      ]);
    });

    test('một sự kiện trải nhiều dòng (kiểu Gemini) vẫn ghép đủ', () async {
      // Đây đúng là ca gây bug thật: chỉ dòng đầu có "data:", các dòng sau
      // là phần tiếp của cùng khối JSON, không lặp lại tiền tố.
      final payloads = await collect([
        'data: {',
        '  "candidates": [{',
        '    "content": {"parts": [{"text": "Xin chào"}]}',
        '  }]',
        '}',
        '',
      ]);
      expect(payloads, hasLength(1));
      expect(payloads.first, contains('"text": "Xin chào"'));
    });

    test('nhiều sự kiện trải dòng liên tiếp không bị lẫn vào nhau', () async {
      final payloads = await collect([
        'data: {',
        '  "a": 1',
        '}',
        '',
        'data: {',
        '  "a": 2',
        '}',
        '',
      ]);
      expect(payloads, ['{\n  "a": 1\n}', '{\n  "a": 2\n}']);
    });

    test('sự kiện cuối không có dòng trống kết thúc vẫn được phát ra', () async {
      // Nhiều server không gửi thêm dòng trống sau sự kiện cuối trước khi
      // đóng kết nối.
      final payloads = await collect(['data: {"a": 1}']);
      expect(payloads, ['{"a": 1}']);
    });

    test('dòng rỗng liên tiếp không sinh payload rỗng', () async {
      final payloads = await collect(['', '', 'data: {"a": 1}', '', '']);
      expect(payloads, ['{"a": 1}']);
    });

    test('dòng không có tiền tố data trước khi có event nào mở thì bị bỏ qua', () {
      // Phòng trường hợp server gửi dòng comment/keep-alive (": ping") giữa
      // hai sự kiện — không được vô tình dính vào sự kiện kế tiếp.
      expect(
        collect(['orphan line without prefix', 'data: {"a": 1}', '']),
        completion(['{"a": 1}']),
      );
    });
  });

  group('geminiVisibleText', () {
    test('bỏ phần suy nghĩ nội bộ, chỉ giữ câu trả lời', () {
      // Đúng ca đã xảy ra: phần nháp tiếng Anh của model bị ghép vào câu trả
      // lời tiếng Việt.
      final chunk = <String, Object?>{
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': "Let's cite MAE101 (7.9)", 'thought': true},
                {'text': 'Để trở thành AI Engineer, bạn cần '},
              ],
            },
          },
        ],
      };
      expect(geminiVisibleText(chunk), 'Để trở thành AI Engineer, bạn cần ');
    });

    test('ghép nhiều part hiển thị được theo đúng thứ tự', () {
      final chunk = <String, Object?>{
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'Toán '},
                {'text': 'rời rạc'},
              ],
            },
          },
        ],
      };
      expect(geminiVisibleText(chunk), 'Toán rời rạc');
    });

    test('chunk chỉ có phần suy nghĩ thì không sinh chữ nào', () {
      final chunk = <String, Object?>{
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'thinking...', 'thought': true},
              ],
            },
          },
        ],
      };
      expect(geminiVisibleText(chunk), isEmpty);
    });

    test('chunk thiếu trường vẫn trả rỗng chứ không ném lỗi', () {
      expect(geminiVisibleText(const {}), isEmpty);
      expect(geminiVisibleText(const {'candidates': []}), isEmpty);
      expect(
        geminiVisibleText(const {
          'candidates': [
            {'content': {}},
          ],
        }),
        isEmpty,
      );
    });
  });

  group('isTransientAiStatus', () {
    test('quá tải và lỗi máy chủ thì đáng gọi lại', () {
      // 503 chính là lỗi đã gặp: "This model is currently experiencing high
      // demand. Spikes in demand are usually temporary."
      expect(isTransientAiStatus(503), isTrue);
      expect(isTransientAiStatus(429), isTrue);
      expect(isTransientAiStatus(500), isTrue);
      expect(isTransientAiStatus(502), isTrue);
      expect(isTransientAiStatus(504), isTrue);
    });

    test('lỗi do phía mình thì không gọi lại', () {
      // Gọi lại mấy lỗi này chỉ tốn quota và bắt người dùng chờ vô ích.
      expect(isTransientAiStatus(400), isFalse);
      expect(isTransientAiStatus(401), isFalse);
      expect(isTransientAiStatus(403), isFalse);
      expect(isTransientAiStatus(404), isFalse);
    });
  });

  group('isModelUnavailableStatus', () {
    test('sai tên model thì lùi về model chính', () {
      expect(isModelUnavailableStatus(404), isTrue);
      expect(isModelUnavailableStatus(400), isTrue);
    });

    test('lỗi tạm thời hay lỗi key thì không đổ cho tên model', () {
      // Lùi model trong mấy ca này là chẩn đoán sai: 503 chỉ là quá tải, 401
      // là sai key — đổi model không cứu được gì mà còn tắt model phụ oan.
      expect(isModelUnavailableStatus(503), isFalse);
      expect(isModelUnavailableStatus(429), isFalse);
      expect(isModelUnavailableStatus(401), isFalse);
      expect(isModelUnavailableStatus(500), isFalse);
      expect(isModelUnavailableStatus(null), isFalse);
    });
  });

  group('geminiFinishReason', () {
    test('đọc được lý do dừng', () {
      expect(
        geminiFinishReason(const {
          'candidates': [
            {'finishReason': 'MAX_TOKENS'},
          ],
        }),
        'MAX_TOKENS',
      );
    });

    test('chunk giữa chừng chưa có lý do dừng', () {
      expect(
        geminiFinishReason(const {
          'candidates': [
            {'content': {}},
          ],
        }),
        isNull,
      );
    });
  });
}
