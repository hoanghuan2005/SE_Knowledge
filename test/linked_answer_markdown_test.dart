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

  _bareCodes();
  _urls();

  test('không có mã nào thì trả về y nguyên', () {
    const markdown = '### Lộ trình\n\n1. **Toán nền tảng**\n2. Lập trình';
    expect(convert(markdown), markdown);
  });
}

/// Phần dưới khoá lưới an toàn lấy từ nhánh `fix ask ai, fix ui`: model đôi
/// khi quên bọc `[[ ]]`, khi đó mã môn viết rời vẫn phải thành link.
void _bareCodes() {
  const known = {'CSD201', 'PRF192', 'SE_COM*2'};
  String convert(String text) => wikiLinksToMarkdown(text, known);

  test('mã môn viết rời cũng thành link', () {
    expect(
      convert('Em nên học PRF192 trước'),
      'Em nên học [PRF192](se-subject:PRF192) trước',
    );
  });

  test('mã viết rời không có trong CSDL thì để yên', () {
    expect(convert('Môn AIL999 không có'), 'Môn AIL999 không có');
  });

  test('không bọc lại mã đã nằm trong link', () {
    const done = '[CSD201](se-subject:CSD201)';
    expect(convert(done), done);
  });

  test('không đụng vào mã nằm trong code', () {
    expect(convert('gõ `PRF192` vào ô'), 'gõ `PRF192` vào ô');
    expect(
      convert('```\nPRF192\n```'),
      '```\nPRF192\n```',
    );
  });

  test('mã viết thường không bị nhận nhầm', () {
    expect(convert('môn prf192 là gì'), 'môn prf192 là gì');
  });
}

/// Link trong đề cương (Coursera, trang sách, trang FLM gốc) phải bấm được
/// ngay trong chat — đó là thứ sinh viên cần nhất ở câu hỏi "tài liệu nào".
void _urls() {
  const known = {'CSD201', 'PRF192'};
  String convert(String text) => wikiLinksToMarkdown(text, known);

  test('URL viết trần thành liên kết', () {
    expect(
      convert('Xem tại https://flm.fpt.edu.vn/gui/Syllabus?sylID=1 nhé'),
      'Xem tại [https://flm.fpt.edu.vn/gui/Syllabus?sylID=1]'
          '(https://flm.fpt.edu.vn/gui/Syllabus?sylID=1) nhé',
    );
  });

  test('dấu câu cuối câu không bị nuốt vào link', () {
    // "... xem tại https://a.vn/b." — để nguyên thì bấm ra trang 404.
    expect(
      convert('Tài liệu ở https://a.vn/b.'),
      'Tài liệu ở [https://a.vn/b](https://a.vn/b).',
    );
  });

  test('link Markdown có sẵn thì không bọc lại', () {
    const done = '[Coursera](https://www.coursera.org/learn/x)';
    expect(convert(done), done);
  });

  test('URL trong khối code để yên', () {
    expect(convert('`https://a.vn/b`'), '`https://a.vn/b`');
  });

  test('mã môn và URL cùng câu đều thành link', () {
    expect(
      convert('[[CSD201]] xem https://a.vn/b'),
      '[CSD201](se-subject:CSD201) xem [https://a.vn/b](https://a.vn/b)',
    );
  });

  test('không đụng vào chữ giống link nhưng thiếu scheme', () {
    expect(convert('vào flm.fpt.edu.vn'), 'vào flm.fpt.edu.vn');
  });
}
