import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/models/subject.dart';
import 'package:se_knowledge/services/fap_markdown_parser.dart';
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

  group('viết tắt mã môn', () {
    // Đủ lớn để phép lọc theo tỉ lệ kích hoạt, và cố tình có môn mang chữ
    // "trung"/"bình" trong tên để tái hiện đúng kiểu nhiễu đã gặp.
    final catalogue = <Subject>[
      Subject.create(code: 'CSD201', name: 'Data Structures and Algorithms'),
      Subject.create(code: 'SWR302', name: 'Software Requirement'),
      Subject.create(code: 'SWP391', name: 'Software Development Project'),
      Subject.create(code: 'SWT301', name: 'Software Testing'),
      Subject.create(code: 'JPD316', name: 'Intermediate Japanese_Tiếng Nhật trung cấp'),
      Subject.create(code: 'JPD133', name: 'Elementary Japanese_Tiếng Nhật sơ cấp'),
      Subject.create(code: 'VOV114', name: 'Vovinam_Võ bình định'),
      Subject.create(code: 'OTP101', name: 'Orientation_Trung tâm định hướng'),
      Subject.create(code: 'PRF192', name: 'Programming Fundamentals'),
      Subject.create(code: 'PRO192', name: 'Object Oriented Programming'),
      Subject.create(code: 'DBI202', name: 'Database Systems'),
      Subject.create(code: 'MAE101', name: 'Mathematics for Engineering'),
      Subject.create(code: 'MAS291', name: 'Statistics and Probability'),
      Subject.create(code: 'PRJ301', name: 'Java Web Application Development'),
    ];

    List<String> codesFrom(String question) => GraphRagService.instance
        .findSeeds(question, catalogue)
        .map((s) => s.code)
        .toList();

    test('viết tắt mã môn được nhận ra và không bị môn khác chen chỗ', () {
      // Ca thật: câu này từng chỉ ra CSD201, còn SWR302 bị bốn môn tình cờ
      // mang chữ "trung"/"bình" trong tên đẩy khỏi top 5 hạt giống.
      final codes = codesFrom('điểm trung bình csd và swr của tôi là bao nhiêu');

      expect(codes, containsAll(['CSD201', 'SWR302']));
      expect(codes, isNot(contains('JPD316')));
      expect(codes, isNot(contains('VOV114')));
      expect(codes, isNot(contains('OTP101')));
    });

    test('khớp mã môn xếp trên khớp tên môn', () {
      // "swp" trỏ thẳng vào mã SWP391, còn "software" chỉ là chữ trong tên
      // của ba môn — mã phải thắng.
      expect(codesFrom('môn swp học gì').first, 'SWP391');
    });

    test('viết tắt vẫn đủ tin để đính đề cương', () {
      final matches =
          GraphRagService.instance.seedsWithConfidence('swr là môn gì', catalogue);
      expect(matches.first.subject.code, 'SWR302');
      expect(matches.first.confident, isTrue);
    });
  });

  group('viết tắt trỏ vào nhiều môn thì hỏi lại', () {
    SeedMatch seed(String code, {bool confident = false, bool viaCode = true}) =>
        (
          subject: Subject.create(code: code, name: code),
          confident: confident,
          viaCode: viaCode,
        );

    test('nhiều môn cùng khớp qua mã thì nêu hết để hỏi lại', () {
      // "jpd" trỏ vào cả 5 môn tiếng Nhật, không môn nào nổi trội.
      expect(
        ambiguousCodeMatches([
          seed('JPD113'),
          seed('JPD123'),
          seed('JPD133'),
        ]),
        ['JPD113', 'JPD123', 'JPD133'],
      );
    });

    test('có môn đủ tin thì trả lời luôn, không hỏi', () {
      expect(
        ambiguousCodeMatches([
          seed('CSD201', confident: true),
          seed('CSD301'),
        ]),
        isEmpty,
      );
    });

    test('chỉ một môn thì không có gì để hỏi', () {
      expect(ambiguousCodeMatches([seed('PRF192')]), isEmpty);
    });

    test('khớp theo tên/chủ đề thì không hỏi lại', () {
      // "software" khớp tên nhiều môn, nhưng đó là câu hỏi rộng thật lòng —
      // hỏi lại chỉ làm phiền người dùng.
      expect(
        ambiguousCodeMatches([
          seed('SWE201C', viaCode: false),
          seed('SWR302', viaCode: false),
          seed('SWT301', viaCode: false),
        ]),
        isEmpty,
      );
    });

    test('không có hạt giống nào thì cũng không hỏi', () {
      expect(ambiguousCodeMatches(const []), isEmpty);
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

  group('từ chung trong đề cương không được cộng điểm', () {
    // Trường `description` chứa nguyên văn đề cương, dài hàng trăm chữ. Mỗi
    // cú khớp lẻ cộng 1 điểm, nên một đề cương đủ dài gom được số điểm lẻ
    // vượt ngưỡng 2/3 rồi chen vào 5 suất hạt giống. Đây là cách `VOV114`
    // (môn võ) lọt vào câu hỏi về nhóm môn JPD trên dữ liệu thật.
    //
    // Bộ lọc độ phổ biến chỉ chạy khi danh mục đủ lớn (từ 12 môn), vì danh
    // mục nhỏ thì không đo được từ nào là phổ thông. Nên danh sách dưới đây
    // phải đủ dài, và mấy từ chung phải rải ở nhiều môn đúng như ngoài đời.
    const boilerplate =
        'Mục tiêu: Học phần trang bị cho sinh viên những nội dung và kiến '
        'thức cơ bản. Sinh viên học những nội dung gì, dùng tài liệu nào '
        'đều được nêu trong phần nội dung học phần.';

    final noisy = <Subject>[
      ...subjects,
      for (var i = 0; i < 8; i++)
        Subject.create(
          code: 'FIL10$i',
          name: 'Filler $i',
          description: boilerplate,
        ),
      Subject.create(
        code: 'VOV114',
        name: 'Vovinam 1',
        description: '$boilerplate Nội dung về môn võ Vovinam, hệ thống kỹ '
            'thuật căn bản, tinh thần võ đạo.',
      ),
    ];

    test('câu hỏi nhiều từ chung không kéo môn vô can vào', () {
      final codes = GraphRagService.instance
          .findSeeds('PRF học những nội dung gì', noisy)
          .map((s) => s.code);
      expect(codes, isNot(contains('VOV114')));
      expect(codes, contains('PRF192'));
    });

    test('cụm từ hiếm trong mô tả thì vẫn được tính như cũ', () {
      // Không siết nhầm: "cấu trúc dữ liệu" chỉ có ở một môn nên vẫn phải
      // chọn đúng CSD201 dù nó chỉ khớp ở phần mô tả.
      expect(
        GraphRagService.instance
            .findSeeds('môn nào dạy cấu trúc dữ liệu', noisy)
            .map((s) => s.code),
        contains('CSD201'),
      );
    });

    test('âm tiết lẻ khớp tên môn cũng không đủ, phải là cụm', () {
      // "tạo" trong "nhân tạo" từng khớp tên những môn chẳng liên quan.
      // Chương trình không có môn AI thật, nên câu trả lời đúng là không
      // tìm ra môn nào — để AI nói thẳng là chương trình thiếu.
      final codes = GraphRagService.instance
          .findSeeds('môn nào dạy trí tuệ nhân tạo', noisy)
          .map((s) => s.code);
      expect(codes, isNot(contains('VOV114')));
    });
  });

  group('renderSyllabusOutlineForPrompt', () {
    test('giữ đúng phần gợi được câu hỏi, bỏ phần dài', () {
      final outline = GraphRagService.instance
          .renderSyllabusOutlineForPrompt(_syllabus());

      // Đủ cụ thể để hỏi "Progress test chiếm bao nhiêu %" hay "60 buổi học
      // những gì" — đó là lý do vẫn nêu số lượng thay vì bỏ trắng.
      expect(outline, contains('Mô tả môn học: Cấu trúc dữ liệu'));
      expect(outline, contains('2 chuẩn đầu ra'));
      expect(outline, contains('Progress test 20.0%'));
      expect(outline, contains('3 buổi học'));

      // Nhưng không kéo theo nội dung dài của từng buổi, từng CLO.
      expect(outline, isNot(contains('Chi tiết CLO')));
      expect(outline, isNot(contains('Buổi 1:')));
    });

    test('có tên tài liệu, vì "học gì, tài liệu nào" là câu hỏi hay gặp', () {
      // Bản rút gọn giờ còn dùng cho câu hỏi chung của cả nhóm môn. Thiếu
      // mục này thì ngữ cảnh không có lấy một dòng tài liệu, và AI kết luận
      // "dữ liệu khung chương trình không cung cấp tên giáo trình" — sai,
      // vì dữ liệu có đủ, chỉ là chưa ai đưa vào prompt.
      final outline = GraphRagService.instance
          .renderSyllabusOutlineForPrompt(_syllabus());
      expect(outline, contains('Tài liệu học tập:'));
      expect(outline, contains('Giáo trình chính'));
    });

    test('nhãn đầu điểm dài bị cắt ngắn', () {
      // Dữ liệu FAP thật có môn nhét cả đoạn điều kiện thi vào trường
      // `category`. Để nguyên thì riêng dòng này nặng hơn cả phần mô tả.
      final outline = GraphRagService.instance.renderSyllabusOutlineForPrompt(
        _syllabus(assessmentCategory: 'Thi cuối kỳ ${'dài ' * 60}'),
      );
      expect(outline, contains('…'));
      expect(outline, contains('Thi cuối kỳ'));
      expect(outline.length, lessThan(500));
    });

    test('có link đề cương gốc để sinh viên mở bản đầy đủ', () {
      // Mọi đề cương trong CSDL đều có `source_url` trỏ tới trang FLM. Prompt
      // đã lược bớt rất nhiều, nên đây là chỗ xem lại bản gốc.
      const url = 'https://flm.fpt.edu.vn/gui/role/student/Syllabus?sylID=1';
      final rag = GraphRagService.instance;
      final syl = _syllabus(sourceUrl: url);
      expect(rag.renderSyllabusOutlineForPrompt(syl), contains(url));
      expect(rag.renderSyllabusForPrompt(syl), contains(url));
    });

    test('không có link thì không viết dòng trống', () {
      expect(
        GraphRagService.instance.renderSyllabusOutlineForPrompt(_syllabus()),
        isNot(contains('Đề cương gốc')),
      );
    });

    test('nhẹ hơn hẳn bản đầy đủ', () {
      final rag = GraphRagService.instance;
      final syl = _syllabus();
      expect(
        rag.renderSyllabusOutlineForPrompt(syl).length,
        lessThan(rag.renderSyllabusForPrompt(syl).length),
      );
    });

    test('mô tả dài bất thường vẫn bị chặn trên', () {
      final outline = GraphRagService.instance.renderSyllabusOutlineForPrompt(
        _syllabus(description: 'x' * 5000),
      );
      expect(outline.length, lessThan(1000));
      expect(outline, contains('…'));
    });
  });
}

FapSyllabusImport _syllabus({
  String description = 'Cấu trúc dữ liệu và giải thuật.',
  String assessmentCategory = 'Progress test',
  String sourceUrl = '',
}) {
  return FapSyllabusImport(
    fapSyllabusId: 1,
    subjectCode: 'CSD201',
    nameEn: 'Data Structures and Algorithms',
    nameNative: 'Cấu trúc dữ liệu và giải thuật',
    degreeLevel: 'Bachelor',
    learningTeachingMethod: 'In-class',
    timeAllocation: '45h',
    description: description,
    studentTasks: 'Làm bài tập',
    tools: 'JDK',
    scoringScale: 10,
    decisionNo: '',
    decisionDate: '',
    isApproved: true,
    isScored: true,
    minAvgMarkToPass: 5.0,
    isActive: true,
    approvedDate: '',
    rawPrerequisiteText: 'PRF192',
    sourceUrl: sourceUrl,
    materials: const [
      FapMaterialRow(seqNo: 1, description: 'Giáo trình chính', isMain: true),
    ],
    clos: const [
      FapCloRow(code: 'CLO1', detail: 'Chi tiết CLO 1'),
      FapCloRow(code: 'CLO2', detail: 'Chi tiết CLO 2'),
    ],
    sessions: const [
      FapSessionRow(sessionNo: 1, topic: 'Giới thiệu'),
      FapSessionRow(sessionNo: 2, topic: 'Mảng và danh sách'),
      FapSessionRow(sessionNo: 3, topic: 'Cây nhị phân'),
    ],
    assessments: [
      FapAssessmentRow(seqNo: 1, category: assessmentCategory, weightPercent: 20),
      const FapAssessmentRow(seqNo: 2, category: 'Final exam', weightPercent: 60),
    ],
  );
}
