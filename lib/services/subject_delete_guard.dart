import '../models/graph_data.dart';
import '../models/prerequisite.dart';
import '../models/subject.dart';
import 'db_service.dart';
import 'obsidian_service.dart';

/// Mức độ rủi ro khi xoá một môn học.
enum DeleteRisk {
  /// Môn đứng một mình, không liên kết với môn nào. Xoá thoải mái.
  safe,

  /// Môn lá: có môn tiên quyết nhưng không môn nào phụ thuộc vào nó.
  /// Xoá thì đồ thị vẫn liền mạch, chỉ mất vài cạnh.
  warning,

  /// Có môn khác phụ thuộc vào môn này. Xoá là **bẻ gãy lộ trình học**.
  danger,
}

/// Cách xử lý các liên kết khi xoá.
enum DeleteStrategy {
  /// Xoá thẳng, mọi cạnh liên quan biến mất theo `ON DELETE CASCADE`.
  cascade,

  /// Nối tắt trước khi xoá: môn tiên quyết của nó được nối thẳng tới các môn
  /// đang phụ thuộc vào nó, nhờ vậy lộ trình học không bị đứt đoạn.
  rewire,
}

/// Một cạnh nối tắt được đề xuất để vá chỗ đứt sau khi xoá môn ở giữa.
///
/// Ví dụ `PRF192 -> CSD201 -> PRJ301`, xoá `CSD201` thì đề xuất nối thẳng
/// `PRF192 -> PRJ301`.
class RewireSuggestion {
  /// Môn tiên quyết của môn sắp bị xoá.
  final Subject from;

  /// Môn đang phụ thuộc vào môn sắp bị xoá.
  final Subject to;

  const RewireSuggestion({required this.from, required this.to});

  Prerequisite toEdge() => Prerequisite(
    subjectId: to.id!,
    prerequisiteId: from.id!,
    relationType: Prerequisite.kPrerequisite,
  );

  @override
  String toString() => '${from.code} -> ${to.code}';
}

/// Kết quả phân tích trước khi xoá — dữ liệu để dựng hộp thoại cảnh báo.
class DeleteImpact {
  final Subject target;

  /// Các môn tiên quyết của [target]. Xoá xong thì các cạnh này mất.
  final List<Subject> prerequisites;

  /// Các môn đang phụ thuộc vào [target]. Đây là nhóm bị ảnh hưởng nặng nhất.
  final List<Subject> dependents;

  /// Các môn sẽ mất hết liên kết, trở thành node đơn độc trên đồ thị.
  /// Tính theo phương án [DeleteStrategy.cascade] — nối tắt sẽ cứu được
  /// phần lớn trong số này.
  final List<Subject> willBecomeOrphan;

  /// Các cạnh nối tắt an toàn (đã loại những cạnh gây chu trình).
  final List<RewireSuggestion> rewireSuggestions;

  /// Những cặp bị bỏ qua vì nối vào sẽ tạo chu trình, kèm lý do.
  final List<String> rewireBlocked;

  /// Đường dẫn file `.md` trong Vault, nếu môn này đã từng được export.
  final String? notePath;

  const DeleteImpact({
    required this.target,
    required this.prerequisites,
    required this.dependents,
    required this.willBecomeOrphan,
    required this.rewireSuggestions,
    required this.rewireBlocked,
    this.notePath,
  });

  /// Tổng số cạnh sẽ mất khi xoá.
  int get edgesLost => prerequisites.length + dependents.length;

  bool get hasNoteFile => (notePath ?? '').isNotEmpty;

  DeleteRisk get risk {
    if (dependents.isNotEmpty) return DeleteRisk.danger;
    if (prerequisites.isNotEmpty) return DeleteRisk.warning;
    return DeleteRisk.safe;
  }

  bool get canRewire => rewireSuggestions.isNotEmpty;

  /// Câu tóm tắt một dòng cho tiêu đề hộp thoại.
  String get headline {
    switch (risk) {
      case DeleteRisk.safe:
        return 'Môn này chưa liên kết với môn nào, xoá không ảnh hưởng đồ thị.';
      case DeleteRisk.warning:
        return 'Xoá môn này sẽ gỡ $edgesLost liên kết tiên quyết.';
      case DeleteRisk.danger:
        return 'Có ${dependents.length} môn đang phụ thuộc vào '
            '${target.code} — xoá sẽ làm đứt lộ trình học.';
    }
  }

  /// Các dòng chi tiết để liệt kê trong hộp thoại cảnh báo.
  List<String> get details {
    final lines = <String>[];

    if (dependents.isNotEmpty) {
      lines.add(
        'Mất môn tiên quyết: '
        '${dependents.map((s) => s.code).join(', ')}',
      );
    }
    if (prerequisites.isNotEmpty) {
      lines.add(
        'Gỡ liên kết tới: '
        '${prerequisites.map((s) => s.code).join(', ')}',
      );
    }
    if (willBecomeOrphan.isNotEmpty) {
      lines.add(
        'Trở thành môn đơn độc: '
        '${willBecomeOrphan.map((s) => s.code).join(', ')}',
      );
    }
    if (rewireSuggestions.isNotEmpty) {
      lines.add(
        'Có thể nối tắt để vá: '
        '${rewireSuggestions.join(', ')}',
      );
    }
    if (hasNoteFile) {
      lines.add('File ghi chú trong Vault: $notePath');
    }
    return lines;
  }
}

/// Kết quả sau khi đã xoá xong.
class DeleteResult {
  final String code;
  final int edgesRemoved;
  final List<RewireSuggestion> rewired;
  final bool noteFileDeleted;
  final List<String> warnings;

  const DeleteResult({
    required this.code,
    required this.edgesRemoved,
    required this.rewired,
    required this.noteFileDeleted,
    required this.warnings,
  });

  String get summary {
    final sb = StringBuffer('Đã xoá $code');
    if (edgesRemoved > 0) sb.write(', gỡ $edgesRemoved liên kết');
    if (rewired.isNotEmpty) sb.write(', nối tắt ${rewired.length} liên kết');
    if (noteFileDeleted) sb.write(', xoá file .md');
    return '$sb.';
  }
}

/// Kiểm tra ràng buộc **trước** khi xoá một môn học.
///
/// `ON DELETE CASCADE` của SQLite xoá sạch mọi cạnh liên quan mà không báo một
/// tiếng nào. Với đồ thị tiên quyết thì đó là mất dữ liệu âm thầm: xoá một môn
/// nằm giữa chuỗi `A -> B -> C` là cắt đôi lộ trình học, và không có cách nào
/// hoàn tác. Lớp này phân tích hậu quả trước, để giao diện hỏi người dùng.
class SubjectDeleteGuard {
  SubjectDeleteGuard._();
  static final SubjectDeleteGuard instance = SubjectDeleteGuard._();

  final DbService _db = DbService.instance;
  final ObsidianService _vault = ObsidianService.instance;

  /// Phân tích hậu quả của việc xoá [subjectId]. Chỉ đọc, không ghi gì.
  Future<DeleteImpact> analyze(int subjectId) async =>
      analyzeGraph(await _db.loadGraph(), subjectId);

  /// Phần phân tích thuần trên đồ thị đã nạp sẵn, tách riêng để kiểm thử
  /// được mà không cần mở cơ sở dữ liệu.
  DeleteImpact analyzeGraph(GraphData graph, int subjectId) {
    final target = graph.byId[subjectId];
    if (target == null) {
      throw DeleteGuardException('Không tìm thấy môn học cần xoá.');
    }

    final byId = graph.byId;

    final prerequisites = graph.edges
        .where((e) => e.subjectId == subjectId)
        .map((e) => byId[e.prerequisiteId])
        .whereType<Subject>()
        .toList()
      ..sort((a, b) => a.code.compareTo(b.code));

    final dependents = graph.edges
        .where((e) => e.prerequisiteId == subjectId)
        .map((e) => byId[e.subjectId])
        .whereType<Subject>()
        .toList()
      ..sort((a, b) => a.code.compareTo(b.code));

    final remaining = graph.edges
        .where((e) => e.subjectId != subjectId && e.prerequisiteId != subjectId)
        .toList();

    final orphans = _findOrphans(
      candidates: [...prerequisites, ...dependents],
      remainingEdges: remaining,
    );

    final (suggestions, blocked) = _planRewire(
      prerequisites: prerequisites,
      dependents: dependents,
      remainingEdges: remaining,
    );

    return DeleteImpact(
      target: target,
      prerequisites: prerequisites,
      dependents: dependents,
      willBecomeOrphan: orphans,
      rewireSuggestions: suggestions,
      rewireBlocked: blocked,
      notePath: target.notePath,
    );
  }

  /// Thực hiện xoá theo phương án đã chọn.
  ///
  /// Toàn bộ thao tác nằm trong một transaction: nếu nối tắt hỏng giữa chừng
  /// thì môn học cũng không bị xoá, đồ thị giữ nguyên trạng thái cũ.
  Future<DeleteResult> execute(
    DeleteImpact impact, {
    DeleteStrategy strategy = DeleteStrategy.cascade,
    bool deleteNoteFile = false,
  }) async {
    final id = impact.target.id;
    if (id == null) {
      throw DeleteGuardException('Môn học chưa được lưu vào cơ sở dữ liệu.');
    }

    final warnings = <String>[...impact.rewireBlocked];
    final rewired = strategy == DeleteStrategy.rewire
        ? impact.rewireSuggestions
        : const <RewireSuggestion>[];

    await _db.deleteSubjectWithRewire(
      id: id,
      rewireEdges: rewired.map((r) => r.toEdge()).toList(),
    );

    var noteDeleted = false;
    if (deleteNoteFile && impact.hasNoteFile) {
      try {
        await _vault.deleteNote(impact.notePath!);
        noteDeleted = true;
      } catch (e) {
        warnings.add('Không xoá được file ${impact.notePath}: $e');
      }
    } else if (!deleteNoteFile && impact.hasNoteFile) {
      // Cảnh báo quan trọng: file .md còn nằm trong Vault, lần "Nạp vào CSDL"
      // kế tiếp sẽ dựng lại đúng môn vừa xoá.
      warnings.add(
        'File ${impact.target.code}.md vẫn còn trong Vault — lần nhập dữ liệu '
        'tới sẽ tạo lại môn này.',
      );
    }

    return DeleteResult(
      code: impact.target.code,
      edgesRemoved: impact.edgesLost,
      rewired: rewired,
      noteFileDeleted: noteDeleted,
      warnings: warnings,
    );
  }

  // ------------------------------------------------------------------
  // LOGIC ĐỒ THỊ (thuần bộ nhớ, không truy vấn thêm)
  // ------------------------------------------------------------------

  /// Môn nào sau khi xoá sẽ không còn cạnh nào nối vào lẫn nối ra.
  List<Subject> _findOrphans({
    required List<Subject> candidates,
    required List<Prerequisite> remainingEdges,
  }) {
    final connected = <int>{};
    for (final e in remainingEdges) {
      connected.add(e.subjectId);
      connected.add(e.prerequisiteId);
    }

    final seen = <int>{};
    final result = <Subject>[];
    for (final s in candidates) {
      final id = s.id;
      if (id == null || !seen.add(id)) continue;
      if (!connected.contains(id)) result.add(s);
    }
    result.sort((a, b) => a.code.compareTo(b.code));
    return result;
  }

  /// Dựng danh sách cạnh nối tắt, loại sẵn những cạnh sẽ tạo chu trình.
  ///
  /// Kiểm tra chu trình phải làm **ở đây**, trước transaction: nếu để tới lúc
  /// ghi mới phát hiện thì đã xoá mất môn học rồi.
  (List<RewireSuggestion>, List<String>) _planRewire({
    required List<Subject> prerequisites,
    required List<Subject> dependents,
    required List<Prerequisite> remainingEdges,
  }) {
    final suggestions = <RewireSuggestion>[];
    final blocked = <String>[];

    // parents[mônCon] = danh sách môn tiên quyết của nó.
    final parents = <int, List<int>>{};
    for (final e in remainingEdges) {
      parents.putIfAbsent(e.subjectId, () => []).add(e.prerequisiteId);
    }

    for (final from in prerequisites) {
      for (final to in dependents) {
        final fromId = from.id;
        final toId = to.id;
        if (fromId == null || toId == null || fromId == toId) continue;

        // Đã có sẵn cạnh này thì khỏi nối lại.
        if (parents[toId]?.contains(fromId) ?? false) continue;

        if (_createsCycle(parents, subjectId: toId, prerequisiteId: fromId)) {
          blocked.add(
            'Bỏ qua nối tắt ${from.code} -> ${to.code}: sẽ tạo chu trình.',
          );
          continue;
        }

        suggestions.add(RewireSuggestion(from: from, to: to));
        // Cập nhật ngay để cạnh vừa thêm được tính vào lần kiểm tra kế tiếp.
        parents.putIfAbsent(toId, () => []).add(fromId);
      }
    }
    return (suggestions, blocked);
  }

  /// Thêm cạnh `prerequisiteId -> subjectId` có sinh chu trình không.
  /// Có, nếu `subjectId` vốn đã là tổ tiên của `prerequisiteId`.
  bool _createsCycle(
    Map<int, List<int>> parents, {
    required int subjectId,
    required int prerequisiteId,
  }) {
    final stack = <int>[prerequisiteId];
    final seen = <int>{};
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (current == subjectId) return true;
      if (!seen.add(current)) continue;
      stack.addAll(parents[current] ?? const []);
    }
    return false;
  }
}

class DeleteGuardException implements Exception {
  final String message;
  DeleteGuardException(this.message);
  @override
  String toString() => message;
}
