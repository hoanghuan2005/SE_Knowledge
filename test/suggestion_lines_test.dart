import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/services/subject_chat_service.dart';

/// Kiểm thử phần làm sạch 4 câu hỏi gợi ý — logic thuần Dart, không cần mạng.
void main() {
  group('cleanSuggestionLines', () {
    test('gỡ ngoặc quanh mã môn', () {
      // Lỗi thật: chip gợi ý hiện nguyên "[[JPD113]]" vì prompt hệ thống bắt
      // AI bọc mã môn trong ngoặc, mà nhãn nút không bóc link.
      expect(
        cleanSuggestionLines('Cần chuẩn bị gì trước khi học [[JPD113]]?'),
        ['Cần chuẩn bị gì trước khi học JPD113?'],
      );
    });

    test('gỡ được nhiều mã trong cùng một câu', () {
      expect(
        cleanSuggestionLines('[[PRF192]] khác [[PRO192]] ở đâu?'),
        ['PRF192 khác PRO192 ở đâu?'],
      );
    });

    test('bỏ alias và neo trong ngoặc', () {
      expect(
        cleanSuggestionLines('Học [[CSD201|Cấu trúc dữ liệu]] để làm gì?'),
        ['Học CSD201 để làm gì?'],
      );
      expect(
        cleanSuggestionLines('Xem [[CSD201#Lịch trình]] ở đâu?'),
        ['Xem CSD201 ở đâu?'],
      );
    });

    test('bỏ gạch đầu dòng và số thứ tự AI tự thêm', () {
      final lines = cleanSuggestionLines(
        '1. Câu một\n- Câu hai\n* Câu ba\n• Câu bốn',
      );
      expect(lines, ['Câu một', 'Câu hai', 'Câu ba', 'Câu bốn']);
    });

    test('bỏ dòng trống và chỉ lấy tối đa 4 câu', () {
      final lines = cleanSuggestionLines('A\n\nB\n\nC\n\nD\n\nE\n\nF');
      expect(lines, ['A', 'B', 'C', 'D']);
    });

    test('câu không có mã môn thì giữ nguyên', () {
      expect(
        cleanSuggestionLines('Môn này thi cuối kỳ hình thức gì?'),
        ['Môn này thi cuối kỳ hình thức gì?'],
      );
    });
  });
}
