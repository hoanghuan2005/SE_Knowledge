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

  /// True khi ngữ cảnh có kèm điểm của sinh viên. Quyết định hai chuyện: hệ
  /// thống prompt bổ sung bộ quy tắc nhận xét năng lực, và giao diện nói rõ
  /// cho người dùng biết lần hỏi này có gửi điểm đi hay không.
  final bool includesTranscript;

  /// Mã khung CTĐT được dùng làm ngữ cảnh (null nếu dùng toàn bộ CSDL hoặc không giới hạn khung).
  final String? curriculumCode;

  /// Tên chuyên ngành / khung CTĐT hiển thị trên UI.
  final String? curriculumName;

  const GraphRagSummary({
    required this.matchedCodes,
    required this.nodeCount,
    required this.edgeCount,
    required this.approxTokens,
    required this.elapsedMs,
    this.isFallbackFullGraph = false,
    this.includesTranscript = false,
    this.curriculumCode,
    this.curriculumName,
  });

  Map<String, Object?> toJson() => {
        'matchedCodes': matchedCodes,
        'nodeCount': nodeCount,
        'edgeCount': edgeCount,
        'approxTokens': approxTokens,
        'elapsedMs': elapsedMs,
        'isFallbackFullGraph': isFallbackFullGraph,
        'includesTranscript': includesTranscript,
        'curriculumCode': curriculumCode,
        'curriculumName': curriculumName,
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
        includesTranscript: json['includesTranscript'] as bool? ?? false,
        curriculumCode: json['curriculumCode'] as String?,
        curriculumName: json['curriculumName'] as String?,
      );
}

/// Kết quả đầy đủ của một lần trích xuất Graph RAG: [promptText] được ghép
/// vào system prompt gửi cho AI, [summary] là phần nhẹ hiển thị lại cho UI.
class GraphRagContext {
  final String promptText;
  final GraphRagSummary summary;

  const GraphRagContext({required this.promptText, required this.summary});
}
