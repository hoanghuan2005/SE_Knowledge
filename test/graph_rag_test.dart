import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/models/subject.dart';
import 'package:se_knowledge/services/graph_rag_service.dart';

/// Kiểm thử phần chọn môn "hạt giống" cho Graph RAG — logic thuần Dart,
/// không cần DB hay UI.
void main() {
  final subjects = <Subject>[
    Subject.create(
      code: 'PRF192',
      name: 'Programming Fundamentals',
      description: 'Nhập môn lập trình C.',
    ),
    Subject.create(
      code: 'MAD101',
      name: 'Discrete Mathematics',
      description: 'Toán rời rạc, logic, lý thuyết đồ thị.',
    ),
    Subject.create(
      code: 'CSD201',
      name: 'Data Structures and Algorithms',
      description: 'Cấu trúc dữ liệu và thuật toán.',
    ),
    Subject.create(
      code: 'DBI202',
      name: 'Database Systems',
      description: 'Mô hình quan hệ, SQL, chuẩn hoá.',
    ),
    Subject.create(
      code: 'AIL303',
      name: 'Artificial Intelligence',
      description: 'Trí tuệ nhân tạo, tác tử thông minh.',
    ),
    Subject.create(
      code: 'PRJ301',
      name: 'Java Web Application Development',
      description: 'Servlet, JSP, mô hình MVC.',
    ),
  ];

  List<String> seedCodes(String question) => GraphRagService.instance
      .findSeeds(question, subjects)
      .map((s) => s.code)
      .toList();

  group('findSeeds theo mã môn', () {
    test('bắt được mã môn viết thẳng trong câu hỏi', () {
      expect(seedCodes('PRJ301 cần học trước những gì?'), contains('PRJ301'));
    });

    test('bắt được nhiều mã môn trong cùng câu hỏi', () {
      final codes = seedCodes('So sánh CSD201 với DBI202 giúp em');
      expect(codes, containsAll(['CSD201', 'DBI202']));
    });

    test('không phân biệt hoa thường', () {
      expect(seedCodes('mã prj301 là môn gì'), contains('PRJ301'));
    });
  });

  group('findSeeds với câu hỏi toàn cục', () {
    // Hỏi về lộ trình mà thu hẹp quanh vài môn thì trả lời sai bản chất:
    // xếp thứ tự học phải nhìn cả đồ thị. Rỗng = buildContext dùng full graph.
    test('câu hỏi về lộ trình dùng toàn đồ thị', () {
      expect(seedCodes('Gợi ý lộ trình học cho em với'), isEmpty);
    });

    test('câu hỏi về kỳ tới dùng toàn đồ thị', () {
      expect(seedCodes('Kỳ tới em nên đăng ký môn gì'), isEmpty);
    });

    test('mã môn viết thẳng vẫn được ưu tiên hơn ý toàn cục', () {
      // "lộ trình để vào PRJ301" là hỏi có đích danh, không phải hỏi chung.
      expect(seedCodes('Lộ trình để vào được PRJ301 là gì'), ['PRJ301']);
    });
  });

  group('findSeeds theo từ khoá', () {
    test('câu hỏi theo chủ đề viết tắt vẫn ra đúng môn', () {
      // Ca quan trọng nhất: câu hỏi kiểu này không có mã môn nào, trước đây
      // rơi thẳng vào nhánh fallback và gửi cả đồ thị cho AI.
      expect(
        seedCodes('Em muốn theo hướng AI thì cần học trước những môn nào ạ?'),
        ['AIL303'],
      );
    });

    test('khớp theo mô tả tiếng Việt', () {
      expect(seedCodes('môn nào dạy cấu trúc dữ liệu'), contains('CSD201'));
    });

    test('gõ không dấu vẫn khớp', () {
      expect(seedCodes('mon toan roi rac hoc ky may'), contains('MAD101'));
    });

    test('khớp theo tên môn tiếng Anh', () {
      expect(seedCodes('database systems khó không'), contains('DBI202'));
    });

    test('câu hỏi chung chung không suy ra môn nào', () {
      // Không có manh mối thì trả về rỗng để buildContext chuyển sang
      // fallback, thay vì đoán bừa một môn ngẫu nhiên.
      expect(seedCodes('Cho em xin lời khuyên học tập với ạ'), isEmpty);
    });

    test('âm tiết lẻ trùng mô tả không đủ để chọn môn', () {
      // Bỏ dấu xong "lập lộ trình" và "lập trình" cùng ra "lap ... trinh",
      // nên PRF192 ("Nhập môn lập trình C") từng bị chọn nhầm.
      expect(seedCodes('Lập lộ trình 2 kỳ tới dựa trên các môn tôi đã có'),
          isEmpty);
    });

    test('không khớp bừa vào chuỗi con của từ khác', () {
      // "ai" là tiền tố của "Artificial" nhưng câu này không hỏi về AI.
      expect(seedCodes('Ai là người dạy môn này vậy ạ'), isEmpty);
    });
  });
}
