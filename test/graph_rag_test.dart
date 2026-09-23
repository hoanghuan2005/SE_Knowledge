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

  group('lọc từ khoá không có sức phân biệt', () {
    // Danh mục thật của FPTU có rất nhiều môn mang chữ "Engineering" trong
    // tên. Phải đủ lớn thì phép lọc theo tỉ lệ mới kích hoạt.
    final catalogue = <Subject>[
      Subject.create(code: 'AIL303', name: 'Artificial Intelligence'),
      Subject.create(code: 'MAE101', name: 'Mathematics for Engineering'),
      Subject.create(code: 'SWE201C', name: 'Introduction to Software Engineering'),
      Subject.create(code: 'SWR302', name: 'Software Requirement Engineering'),
      Subject.create(code: 'SWT301', name: 'Software Testing Engineering'),
      Subject.create(code: 'GRC490', name: 'Graduation Project Engineering'),
      Subject.create(code: 'SE_GRA_ELE', name: 'SE Graduation Elective Engineering'),
      Subject.create(code: 'PRF192', name: 'Programming Fundamentals'),
      Subject.create(code: 'CSD201', name: 'Data Structures and Algorithms'),
      Subject.create(code: 'DBI202', name: 'Database Systems'),
      Subject.create(code: 'PRJ301', name: 'Java Web Application Development'),
      Subject.create(code: 'PRM392', name: 'Mobile Programming'),
      Subject.create(code: 'MAS291', name: 'Statistics and Probability'),
      Subject.create(code: 'JPD316', name: 'Japanese Elementary'),
    ];

    List<String> codesFrom(String question) => GraphRagService.instance
        .findSeeds(question, catalogue)
        .map((s) => s.code)
        .toList();

    test('từ chung chung không kéo theo cả loạt môn vô can', () {
      // Ca thật đã gặp: câu này từng trả về GRC490, SWE201C, SE_GRA_ELE...
      // vì "engineer" khớp tiền tố "Engineering" ở tên hàng loạt môn.
      final codes = codesFrom('tôi muốn làm AI Engineer nên học gì');

      expect(codes, contains('AIL303'));
      expect(codes, isNot(contains('GRC490')));
      expect(codes, isNot(contains('SE_GRA_ELE')));
      expect(codes, isNot(contains('SWE201C')));
    });

    test('từ khoá hiếm vẫn giữ nguyên sức chọn', () {
      expect(codesFrom('môn database học gì'), contains('DBI202'));
    });

    test('từ rộng đưa môn vào ngữ cảnh nhưng không được đính đề cương', () {
      // Đo trên CSDL thật (64 môn): "software" khớp tên 8 môn. Chọn 2 trong 8
      // để đính đề cương chỉ là đoán mò, nên các môn này vào ngữ cảnh ở dạng
      // gọn thôi.
      final matches = GraphRagService.instance
          .seedsWithConfidence('học về software thì sao', catalogue);

      expect(matches, isNotEmpty);
      expect(matches.every((m) => !m.confident), isTrue);
    });

    test('từ đặc hiệu thì được đính đề cương', () {
      final matches = GraphRagService.instance
          .seedsWithConfidence('môn japanese học gì', catalogue);

      expect(matches.first.subject.code, 'JPD316');
      expect(matches.first.confident, isTrue);
    });

    test('danh mục nhỏ thì không áp dụng lọc theo tỉ lệ', () {
      // Với 6 môn, 25% chỉ là 1-2 môn nên tỉ lệ không nói lên điều gì —
      // bộ test ở nhóm trên vẫn phải chạy đúng như cũ.
      expect(seedCodes('database systems khó không'), contains('DBI202'));
    });
  });

  group('mức tin cậy quyết định có đính đề cương hay không', () {
    test('gọi thẳng mã môn thì luôn đủ tin', () {
      final matches =
          GraphRagService.instance.seedsWithConfidence('CSD201 là gì', subjects);
      expect(matches.single.subject.code, 'CSD201');
      expect(matches.single.confident, isTrue);
    });

    test('khớp vào tên môn thì đủ tin', () {
      final matches = GraphRagService.instance.seedsWithConfidence(
        'database systems khó không',
        subjects,
      );
      expect(matches.first.subject.code, 'DBI202');
      expect(matches.first.confident, isTrue);
    });

    test('chỉ khớp ở phần mô tả thì chưa đủ tin để đính đề cương', () {
      // "cấu trúc dữ liệu" nằm trong phần mô tả của CSD201, không nằm trong
      // tên tiếng Anh "Data Structures and Algorithms".
      final matches = GraphRagService.instance.seedsWithConfidence(
        'môn nào dạy cấu trúc dữ liệu',
        subjects,
      );
      expect(matches.first.subject.code, 'CSD201');
      expect(matches.first.confident, isFalse);
    });
  });
}
