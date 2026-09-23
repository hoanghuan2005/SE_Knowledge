import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/models/knowledge.dart';
import 'package:se_knowledge/services/knowledge_extraction_service.dart';

/// Kiểm thử tầng trích tri thức: tách từ, so khớp từ điển, cụm từ tự trích
/// và phần tính tương quan giữa hai môn.
void main() {
  List<String> tokens(String text) => [
    for (final t in KnowledgeExtractionService.tokenize(
      KnowledgeExtractionService.normalize(text),
    ))
      t.text,
  ];

  KnowledgeSource source(
    String code, {
    int semester = 1,
    String name = '',
    String description = '',
    List<String> clos = const [],
    List<String> sessions = const [],
  }) {
    return KnowledgeSource(
      code: code,
      name: name.isEmpty ? code : name,
      semester: semester,
      description: description,
      clos: [
        for (var i = 0; i < clos.length; i++)
          KnowledgeText('CLO${i + 1}', clos[i]),
      ],
      sessions: [
        for (var i = 0; i < sessions.length; i++)
          KnowledgeText('Buổi ${i + 1}', sessions[i]),
      ],
    );
  }

  Set<String> conceptsOf(KnowledgeIndex index, String code) => {
    for (final c in index.subjects[code]!.concepts) c.conceptId,
  };

  group('tách từ', () {
    test('giữ nguyên cách viết đặc thù của ngành', () {
      expect(tokens('C++ và C# trên .NET, ASP.NET, Node.js'), [
        'c++',
        'va',
        'c#',
        'tren',
        '.net',
        'asp.net',
        'node.js',
      ]);
    });

    test('tách "/" giữa hai từ đủ dài nhưng giữ "i/o"', () {
      expect(tokens('Input/Output và I/O'), ['input', 'output', 'va', 'i/o']);
      expect(tokens('TCP/IP, UI/UX'), ['tcp', 'ip', 'ui', 'ux']);
    });

    test('gạch nối luôn tách, dấu tiếng Việt được bỏ', () {
      expect(tokens('Object-Oriented'), ['object', 'oriented']);
      expect(tokens('Triết học Mác-Lênin'), ['triet', 'hoc', 'mac', 'lenin']);
    });

    test('số mục dính vào chữ bị tách, số thập phân thì giữ', () {
      expect(tokens('3.Data storage 1.3'), ['3', 'data', 'storage', '1.3']);
    });

    test('dấu thanh dạng tổ hợp (NFD) không làm vỡ từ', () {
      // "Đảng" với dấu hỏi rời: a + U+0309.
      const nfd = 'Đảng';
      expect(tokens(nfd), ['dang']);
    });

    test('bỏ số nhiều nhất quán giữa từ điển và văn bản', () {
      expect(KnowledgeExtractionService.stem('queues'), 'queue');
      expect(KnowledgeExtractionService.stem('classes'), 'class');
      expect(KnowledgeExtractionService.stem('libraries'), 'library');
      expect(KnowledgeExtractionService.stem('analysis'), 'analysis');
      expect(KnowledgeExtractionService.stem('process'), 'process');
    });
  });

  group('so khớp từ điển', () {
    test('cụm dài thắng cụm ngắn', () {
      final index = KnowledgeExtractionService.build([
        source('CSD201', clos: ['Implement a binary search tree and a heap.']),
        source('PRM393', clos: ['Hot Reload/Restart & Widget Tree.']),
      ]);
      expect(conceptsOf(index, 'CSD201'), contains('tree'));
      expect(conceptsOf(index, 'CSD201'), isNot(contains('searching')));
      expect(conceptsOf(index, 'PRM393'), contains('dart-flutter'));
      expect(conceptsOf(index, 'PRM393'), isNot(contains('tree')));
    });

    test('"C programming" tính cho cả ngôn ngữ C lẫn lập trình', () {
      final index = KnowledgeExtractionService.build([
        source('OSG202', clos: ['C programming in Linux.']),
      ]);
      expect(
        conceptsOf(index, 'OSG202'),
        containsAll(['c-language', 'programming', 'linux-shell']),
      );
    });

    test('khớp được tiếng Việt có dấu', () {
      final index = KnowledgeExtractionService.build([
        source('CSD201', name: 'Cấu trúc dữ liệu và giải thuật'),
      ]);
      expect(
        conceptsOf(index, 'CSD201'),
        containsAll(['data-structure', 'algorithm']),
      );
    });

    test('nhắc thoáng qua đúng một buổi thì chưa tính', () {
      final index = KnowledgeExtractionService.build([
        source('PMG201C', sessions: ['Risk register review']),
      ]);
      expect(conceptsOf(index, 'PMG201C'), isNot(contains('risk')));
    });

    test('dẫn chứng trích đúng câu có khái niệm', () {
      final index = KnowledgeExtractionService.build([
        source('MAD101', clos: ['Find shortest paths in a weighted graph.']),
      ]);
      final graph = index.subjects['MAD101']!.conceptOf('graph')!;
      expect(graph.evidence.first.ref, 'CLO1');
      expect(graph.evidence.first.snippet, contains('weighted graph'));
    });
  });

  group('tương quan tri thức', () {
    final sources = [
      source(
        'MAD101',
        semester: 2,
        clos: [
          'Analyze the structure of a graph and find shortest paths in a weighted graph.',
          'Describe recursive algorithms and build binary search trees.',
          'Work in teams and present results.',
        ],
      ),
      source(
        'CSD201',
        semester: 3,
        clos: [
          'Implement graph traversal and shortest path algorithms.',
          'Explain binary tree, recursion and sorting.',
          'Work in teams and present results.',
        ],
      ),
      source(
        'SSG104',
        semester: 2,
        clos: ['Apply teamwork and presentation skills in groups.'],
      ),
    ];

    test(
      'hai môn dạy chung khái niệm thì có liên kết, môn trước đứng trước',
      () {
        final index = KnowledgeExtractionService.build(sources);
        final link = index.linkBetween('MAD101', 'CSD201');
        expect(link, isNotNull);
        expect(link!.from, 'MAD101');
        expect(
          link.sharedConceptIds,
          containsAll(['graph', 'tree', 'recursion']),
        );
        expect(link.hasDirectEdge, isFalse, reason: 'chưa có cạnh tiên quyết');
      },
    );

    test('cạnh tiên quyết có sẵn được nhận ra', () {
      final index = KnowledgeExtractionService.build(
        sources,
        directEdges: {KnowledgeExtractionService.pairKey('CSD201', 'MAD101')},
      );
      expect(index.linkBetween('MAD101', 'CSD201')!.hasDirectEdge, isTrue);
    });

    test('kỹ năng chung không nối các môn với nhau', () {
      final index = KnowledgeExtractionService.build(sources);
      expect(index.concepts['teamwork']!.generic, isTrue);
      expect(index.linkBetween('SSG104', 'MAD101'), isNull);
      expect(index.linkBetween('SSG104', 'CSD201'), isNull);
    });

    test('hai mã biến thể của cùng một môn không nối với nhau', () {
      expect(
        KnowledgeExtractionService.isCodeVariant('PRO192', 'PRO192C'),
        isTrue,
      );
      expect(
        KnowledgeExtractionService.isCodeVariant('PRF192', 'PRO192'),
        isFalse,
      );
      final index = KnowledgeExtractionService.build([
        source('PRO192', clos: ['Object-oriented programming in Java.']),
        source('PRO192C', clos: ['Object-oriented programming in Java.']),
      ]);
      expect(index.linkBetween('PRO192', 'PRO192C'), isNull);
    });

    test('độ "lập trình" đọc được từ syllabus', () {
      final index = KnowledgeExtractionService.build([
        source(
          'IOT102',
          clos: [
            'IoT Programming with Arduino UNO.',
            'Programming sensors and actuators in C programming language.',
          ],
        ),
        source('MLN111', clos: ['Triết học Mác - Lênin và chủ nghĩa duy vật.']),
      ]);
      expect(index.subjects['IOT102']!.programmingScore, greaterThan(0.5));
      expect(index.subjects['MLN111']!.programmingScore, 0);
    });
  });

  group('cụm từ tự trích', () {
    test('lấy cụm tiếng Anh ngoài từ điển, bỏ mẩu tiếng Việt', () {
      final index = KnowledgeExtractionService.build([
        source(
          'SWD392',
          clos: [
            'Use statecharts for state dependent objects.',
            'Draw state dependent objects for each use case.',
          ],
        ),
        source(
          'JPD123',
          clos: ['Giới thiệu với bạn bè xung quanh về gia đình.'],
        ),
      ]);
      final swd = index.subjects['SWD392']!.keywords.map((k) => k.phrase);
      expect(swd, contains('state dependent objects'));
      final jpd = index.subjects['JPD123']!.keywords.map((k) => k.phrase);
      expect(jpd, isNot(contains('xung quanh')));
    });

    test('cụm có mặt ở hai môn trở thành khái niệm tự trích', () {
      final index = KnowledgeExtractionService.build([
        source(
          'HCM202',
          clos: ['National liberation and national construction.'],
        ),
        source('VNR202', clos: ['The road of national liberation in Vietnam.']),
      ]);
      final extracted = index.concepts.values.where((c) => c.extracted);
      expect(
        extracted.map((c) => c.label.toLowerCase()),
        contains('national liberation'),
      );
    });
  });
}
