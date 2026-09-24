import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/views/widgets/linked_answer_text.dart';

/// Kiểm thử phần đổi `[[MÃ MÔN]]` thành liên kết Markdown.
///
/// Câu trả lời của AI là Markdown (`**đậm**`, `### tiêu đề`, gạch đầu dòng),
/// nên chỗ này phải chèn link mà không làm vỡ phần Markdown còn lại.
void main() {
  const known = {'CSD201', 'PRF192', 'SE_COM*2'};

  String convert(String text) => wikiLinksToMarkdown(text, known);

  test('đổi mã môn có thật thành liên kết', () {
    expect(
      convert('Học [[CSD201]] trước'),
      'Học [CSD201](se-subject:CSD201) trước',
    );
  });

  test('mã không có trong CSDL thì để chữ thường, không tạo link chết', () {
    expect(convert('Học [[AIL999]] đi'), 'Học AIL999 đi');
  });

  test('bỏ alias và neo trong ngoặc', () {
    expect(
      convert('[[CSD201|Cấu trúc dữ liệu]]'),
      '[CSD201](se-subject:CSD201)',
    );
    expect(convert('[[CSD201#Lịch trình]]'), '[CSD201](se-subject:CSD201)');
  });

  test('thoát ký tự Markdown trong mã môn', () {
    // Mã thật có dạng này: `*` và `_` là ký tự in nghiêng/đậm của Markdown,
    // để nguyên thì nhãn link vỡ.
    expect(
      convert('[[SE_COM*2]]'),
      r'[SE\_COM\*2](se-subject:SE_COM*2)',
    );
  });

  test('giữ nguyên phần Markdown xung quanh', () {
    expect(
      convert('* **Nền tảng:** [[PRF192]] (8.2)'),
      '* **Nền tảng:** [PRF192](se-subject:PRF192) (8.2)',
    );
  });

  test('đổi được nhiều mã trong cùng một câu', () {
    expect(
      convert('[[CSD201]] và [[PRF192]]'),
      '[CSD201](se-subject:CSD201) và [PRF192](se-subject:PRF192)',
    );
  });

  test('không có mã nào thì trả về y nguyên', () {
    const markdown = '### Lộ trình\n\n1. **Toán nền tảng**\n2. Lập trình';
    expect(convert(markdown), markdown);
  });
}
