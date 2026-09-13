import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/models/graph_data.dart';
import 'package:se_knowledge/models/prerequisite.dart';
import 'package:se_knowledge/models/subject.dart';
import 'package:se_knowledge/services/subject_delete_guard.dart';

/// Kiểm thử logic ràng buộc trước khi xoá môn học.
///
/// Chỉ kiểm phần phân tích đồ thị nên không cần mở SQLite: dựng sẵn một
/// [GraphData] trong bộ nhớ rồi gọi thẳng `analyzeGraph`.
void main() {
  final now = DateTime(2026, 1, 1);

  Subject subject(int id, String code) => Subject(
    id: id,
    code: code,
    name: 'Môn $code',
    createdAt: now,
    updatedAt: now,
  );

  /// `prerequisiteId -> subjectId`: học [prereqId] xong mới học được [id].
  Prerequisite edge(int prereqId, int id) =>
      Prerequisite(subjectId: id, prerequisiteId: prereqId);

  final guard = SubjectDeleteGuard.instance;

  group('phân loại mức rủi ro', () {
    test('môn đứng một mình thì an toàn', () {
      final graph = GraphData(subjects: [subject(1, 'PRF192')], edges: const []);
      final impact = guard.analyzeGraph(graph, 1);

      expect(impact.risk, DeleteRisk.safe);
      expect(impact.edgesLost, 0);
      expect(impact.canRewire, isFalse);
    });

    test('môn lá chỉ ở mức cảnh báo', () {
      // PRF192 -> CSD201, xoá CSD201 thì không ai mất tiên quyết.
      final graph = GraphData(
        subjects: [subject(1, 'PRF192'), subject(2, 'CSD201')],
        edges: [edge(1, 2)],
      );
      final impact = guard.analyzeGraph(graph, 2);

      expect(impact.risk, DeleteRisk.warning);
      expect(impact.prerequisites.map((s) => s.code), ['PRF192']);
      expect(impact.dependents, isEmpty);
      expect(impact.edgesLost, 1);
    });

    test('môn có kẻ phụ thuộc là mức nguy hiểm', () {
      // CSD201 -> PRJ301
      final graph = GraphData(
        subjects: [subject(2, 'CSD201'), subject(3, 'PRJ301')],
        edges: [edge(2, 3)],
      );
      final impact = guard.analyzeGraph(graph, 2);

      expect(impact.risk, DeleteRisk.danger);
      expect(impact.dependents.map((s) => s.code), ['PRJ301']);
      expect(impact.headline, contains('CSD201'));
      expect(impact.details.first, contains('PRJ301'));
    });
  });

  group('nối tắt khi xoá môn ở giữa', () {
    // PRF192 -> CSD201 -> PRJ301
    final chain = GraphData(
      subjects: [subject(1, 'PRF192'), subject(2, 'CSD201'), subject(3, 'PRJ301')],
      edges: [edge(1, 2), edge(2, 3)],
    );

    test('đề xuất nối thẳng môn trước với môn sau', () {
      final impact = guard.analyzeGraph(chain, 2);

      expect(impact.canRewire, isTrue);
      expect(impact.rewireSuggestions.map((r) => r.toString()), [
        'PRF192 -> PRJ301',
      ]);
      expect(impact.edgesLost, 2);
    });

    test('cạnh nối tắt trỏ đúng chiều', () {
      final suggestion = guard.analyzeGraph(chain, 2).rewireSuggestions.single;
      final newEdge = suggestion.toEdge();

      // Môn PRJ301 (id 3) cần học PRF192 (id 1) trước.
      expect(newEdge.subjectId, 3);
      expect(newEdge.prerequisiteId, 1);
    });

    test('không đề xuất lại cạnh vốn đã tồn tại', () {
      // Đã có sẵn PRF192 -> PRJ301 song song với đường qua CSD201.
      final graph = GraphData(
        subjects: chain.subjects,
        edges: [...chain.edges, edge(1, 3)],
      );
      final impact = guard.analyzeGraph(graph, 2);

      expect(impact.rewireSuggestions, isEmpty);
    });

    test('bỏ qua cạnh nối tắt sẽ tạo chu trình', () {
      // A -> B -> C và sẵn có C -> A. Xoá B thì nối A -> C sẽ khép vòng.
      final graph = GraphData(
        subjects: [subject(1, 'A'), subject(2, 'B'), subject(3, 'C')],
        edges: [edge(1, 2), edge(2, 3), edge(3, 1)],
      );
      final impact = guard.analyzeGraph(graph, 2);

      expect(impact.rewireSuggestions, isEmpty);
      expect(impact.rewireBlocked, hasLength(1));
      expect(impact.rewireBlocked.single, contains('chu trình'));
    });

    test('nhiều môn trước và nhiều môn sau thì nối đủ mọi cặp', () {
      // (A, B) -> X -> (C, D)
      final graph = GraphData(
        subjects: [
          subject(1, 'A'),
          subject(2, 'B'),
          subject(3, 'X'),
          subject(4, 'C'),
          subject(5, 'D'),
        ],
        edges: [edge(1, 3), edge(2, 3), edge(3, 4), edge(3, 5)],
      );
      final impact = guard.analyzeGraph(graph, 3);

      expect(impact.rewireSuggestions, hasLength(4));
      expect(impact.edgesLost, 4);
    });
  });

  group('môn trở thành đơn độc', () {
    test('phát hiện môn mất hết liên kết sau khi xoá', () {
      // PRF192 -> CSD201, xoá CSD201 thì PRF192 không còn liên kết nào.
      final graph = GraphData(
        subjects: [subject(1, 'PRF192'), subject(2, 'CSD201')],
        edges: [edge(1, 2)],
      );
      final impact = guard.analyzeGraph(graph, 2);

      expect(impact.willBecomeOrphan.map((s) => s.code), ['PRF192']);
    });

    test('môn còn liên kết khác thì không tính là đơn độc', () {
      // PRF192 nối cả CSD201 lẫn MAD101; xoá CSD201 thì PRF192 vẫn còn cạnh.
      final graph = GraphData(
        subjects: [
          subject(1, 'PRF192'),
          subject(2, 'CSD201'),
          subject(3, 'MAD101'),
        ],
        edges: [edge(1, 2), edge(1, 3)],
      );
      final impact = guard.analyzeGraph(graph, 2);

      expect(impact.willBecomeOrphan, isEmpty);
    });
  });

  group('cảnh báo file trong Vault', () {
    test('biết môn này đã có file .md', () {
      final graph = GraphData(
        subjects: [
          Subject(
            id: 1,
            code: 'PRF192',
            name: 'Programming Fundamentals',
            notePath: r'C:\Vault\PRF192.md',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        edges: const [],
      );
      final impact = guard.analyzeGraph(graph, 1);

      expect(impact.hasNoteFile, isTrue);
      expect(impact.details.last, contains('PRF192.md'));
    });
  });

  test('xoá môn không tồn tại thì báo lỗi rõ ràng', () {
    expect(
      () => guard.analyzeGraph(GraphData.empty, 99),
      throwsA(isA<DeleteGuardException>()),
    );
  });
}
