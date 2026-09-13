/// Tóm tắt một lần trích xuất Graph RAG: đủ dữ liệu để hiển thị UI và để lưu
/// lại cùng tin nhắn trong phiên chat (không cần giữ lại toàn bộ subgraph).
class GraphRagSummary {
  final List<String> matchedCodes;
  final int nodeCount;
  final int edgeCount;
  final int approxTokens;
  final int elapsedMs;

  /// True khi câu hỏi không nhắc trực tiếp môn nào, phải fallback dùng toàn
  /// bộ đồ thị làm ngữ cảnh (thay vì một subgraph nhỏ quanh vài node).
  final bool isFallbackFullGraph;

  const GraphRagSummary({
    required this.matchedCodes,
    required this.nodeCount,
    required this.edgeCount,
    required this.approxTokens,
    required this.elapsedMs,
    this.isFallbackFullGraph = false,
  });

  Map<String, Object?> toJson() => {
        'matchedCodes': matchedCodes,
        'nodeCount': nodeCount,
        'edgeCount': edgeCount,
        'approxTokens': approxTokens,
        'elapsedMs': elapsedMs,
        'isFallbackFullGraph': isFallbackFullGraph,
      };

  factory GraphRagSummary.fromJson(Map<String, dynamic> json) =>
      GraphRagSummary(
        matchedCodes:
            (json['matchedCodes'] as List?)?.whereType<String>().toList() ??
                const [],
        nodeCount: json['nodeCount'] as int? ?? 0,
        edgeCount: json['edgeCount'] as int? ?? 0,
        approxTokens: json['approxTokens'] as int? ?? 0,
        elapsedMs: json['elapsedMs'] as int? ?? 0,
        isFallbackFullGraph: json['isFallbackFullGraph'] as bool? ?? false,
      );
}

/// Kết quả đầy đủ của một lần trích xuất Graph RAG: [promptText] được ghép
/// vào system prompt gửi cho AI, [summary] là phần nhẹ hiển thị lại cho UI.
class GraphRagContext {
  final String promptText;
  final GraphRagSummary summary;

  const GraphRagContext({required this.promptText, required this.summary});
}
