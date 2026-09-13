import '../models/graph_rag_context.dart';
import '../models/prerequisite.dart';
import '../models/subject.dart';
import 'db_service.dart';

/// Trích một subgraph liên quan trực tiếp đến câu hỏi từ đồ thị tiên quyết,
/// thay vì gửi nguyên toàn bộ CSDL vào mọi prompt.
///
/// Vì đề tài chỉ giới hạn phạm vi syllabus FPTU-SE, việc thu hẹp ngữ cảnh này
/// giúp: (1) tiết kiệm token nên AI không bị cắt câu trả lời giữa chừng,
/// (2) trả lời bám sát đúng các môn được hỏi thay vì lan man sang môn không
/// liên quan, (3) chạy nhanh hơn vì prompt ngắn hơn.
class GraphRagService {
  GraphRagService._();
  static final GraphRagService instance = GraphRagService._();

  final DbService _db = DbService.instance;

  /// Bắt các mã môn kiểu "PRF192", "CSD201" xuất hiện trong câu hỏi.
  static final RegExp _codePattern = RegExp(r'\b[A-Z]{2,4}\d{2,4}[A-Z]?\b');

  Future<GraphRagContext> buildContext(String question, {int hops = 2}) async {
    final stopwatch = Stopwatch()..start();
    final graph = await _db.loadGraph();

    if (graph.isEmpty) {
      stopwatch.stop();
      return GraphRagContext(
        promptText: 'Người dùng chưa có môn học nào trong hệ thống.',
        summary: GraphRagSummary(
          matchedCodes: const [],
          nodeCount: 0,
          edgeCount: 0,
          approxTokens: 0,
          elapsedMs: stopwatch.elapsedMilliseconds,
        ),
      );
    }

    final seeds = _findSeeds(question, graph.subjects);
    final isFallback = seeds.isEmpty;
    final seedIds = isFallback
        ? graph.subjects.map((s) => s.id!).toSet()
        : seeds.map((s) => s.id!).toSet();

    final subgraphIds =
        isFallback ? seedIds : _expand(seedIds, graph.edges, hops);

    final nodes =
        graph.subjects.where((s) => subgraphIds.contains(s.id)).toList()
          ..sort((a, b) {
            final bySem = a.semester.compareTo(b.semester);
            return bySem != 0 ? bySem : a.code.compareTo(b.code);
          });
    final edges = graph.edges
        .where((e) =>
            subgraphIds.contains(e.subjectId) &&
            subgraphIds.contains(e.prerequisiteId))
        .toList();

    final promptText = _renderPrompt(nodes, edges, graph.byId, isFallback);
    stopwatch.stop();

    return GraphRagContext(
      promptText: promptText,
      summary: GraphRagSummary(
        matchedCodes: seeds.map((s) => s.code).toList(),
        nodeCount: nodes.length,
        edgeCount: edges.length,
        approxTokens: _estimateTokens(promptText),
        elapsedMs: stopwatch.elapsedMilliseconds,
        isFallbackFullGraph: isFallback,
      ),
    );
  }

  /// Tìm node "hạt giống": môn được nhắc trực tiếp trong câu hỏi, theo mã môn
  /// (VD "PRJ301") hoặc theo tên môn xuất hiện nguyên văn trong câu hỏi.
  List<Subject> _findSeeds(String question, List<Subject> subjects) {
    final upper = question.toUpperCase();
    final lower = question.toLowerCase();
    final codeHits =
        _codePattern.allMatches(upper).map((m) => m.group(0)!).toSet();

    final seeds = <Subject>[];
    for (final s in subjects) {
      final byCode = codeHits.contains(s.code.toUpperCase());
      final byName =
          s.name.trim().length >= 4 && lower.contains(s.name.toLowerCase());
      if (byCode || byName) seeds.add(s);
    }
    return seeds;
  }

  /// BFS hai chiều (cả môn tiên quyết lẫn môn được mở ra) từ tập seed, giới
  /// hạn [hops] bước để subgraph không phình to bằng cả đồ thị.
  Set<int> _expand(Set<int> seedIds, List<Prerequisite> edges, int hops) {
    final neighbors = <int, Set<int>>{};
    for (final e in edges) {
      neighbors.putIfAbsent(e.subjectId, () => {}).add(e.prerequisiteId);
      neighbors.putIfAbsent(e.prerequisiteId, () => {}).add(e.subjectId);
    }

    var frontier = Set<int>.from(seedIds);
    final visited = Set<int>.from(seedIds);
    for (var step = 0; step < hops; step++) {
      final next = <int>{};
      for (final id in frontier) {
        for (final n in neighbors[id] ?? const <int>{}) {
          if (visited.add(n)) next.add(n);
        }
      }
      if (next.isEmpty) break;
      frontier = next;
    }
    return visited;
  }

  String _renderPrompt(
    List<Subject> nodes,
    List<Prerequisite> edges,
    Map<int, Subject> byId,
    bool isFallback,
  ) {
    if (nodes.isEmpty) {
      return 'Không tìm thấy môn học nào liên quan trực tiếp đến câu hỏi trong CSDL.';
    }
    final sb = StringBuffer(isFallback
        ? 'Câu hỏi không nhắc môn cụ thể nào, đây là toàn bộ danh sách môn '
            'học và quan hệ tiên quyết hiện có:\n'
        : 'Các môn học liên quan trực tiếp đến câu hỏi và quan hệ tiên '
            'quyết của chúng:\n');
    for (final s in nodes) {
      final prereqCodes = edges
          .where((e) => e.subjectId == s.id)
          .map((e) => byId[e.prerequisiteId]?.code)
          .whereType<String>()
          .toList();
      sb.write('- ${s.code} (${s.name}), kỳ ${s.semester}, ${s.credits} tín chỉ');
      sb.write(prereqCodes.isEmpty
          ? ', không có môn tiên quyết'
          : ', tiên quyết: ${prereqCodes.join(", ")}');
      sb.writeln('.');
    }
    return sb.toString();
  }

  /// Ước lượng số token theo heuristic đơn giản (~4 ký tự / token), chỉ để
  /// hiển thị tham khảo trên UI, không cần chính xác tuyệt đối.
  int _estimateTokens(String text) => (text.length / 4).ceil();
}
