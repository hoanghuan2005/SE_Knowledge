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

  static final RegExp _tokenSplitter = RegExp(r'[^a-z0-9]+');

  /// Cụm viết hoa liền nhau ("AI", "SQL"), dùng để tách viết tắt khỏi từ
  /// tiếng Việt viết thường trùng mặt chữ.
  static final RegExp _upperCasePattern = RegExp(r'\b[A-Z]{2,}\b');

  /// Số môn hạt giống tối đa suy ra từ từ khoá, để một câu hỏi chung chung
  /// không kéo theo cả chục môn rồi phình ngược ngữ cảnh.
  static const int maxKeywordSeeds = 5;

  /// Trần số node của subgraph. Đồ thị thật có vài chục môn, BFS 2 bước từ
  /// nhiều seed có thể chạm gần hết đồ thị và làm mất ý nghĩa của việc thu hẹp.
  static const int maxNodes = 24;

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

    final seeds = findSeeds(question, graph.subjects);
    final isFallback = seeds.isEmpty;

    // Nhánh fallback cố tình KHÔNG cắt bớt: lúc đã không đoán được câu hỏi
    // nhắm vào môn nào, đưa thiếu môn còn tai hại hơn là đưa dư.
    final Set<int> subgraphIds;
    if (isFallback) {
      subgraphIds = graph.subjects.map((s) => s.id!).toSet();
    } else {
      final ordered = _expand(seeds.map((s) => s.id!).toList(), graph.edges, hops);
      subgraphIds = ordered.take(maxNodes).toSet();
    }

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

  /// Tìm các môn "hạt giống" để bung subgraph. Hai đường vào:
  ///
  /// 1. Mã môn viết thẳng trong câu hỏi ("PRJ301") — tín hiệu chắc chắn nhất.
  /// 2. Từ khoá trong câu hỏi đối chiếu với mã, tên và mô tả môn.
  ///
  /// Đường thứ hai là bắt buộc: phần lớn câu hỏi thật không đọc mã môn ra,
  /// mà hỏi theo chủ đề ("em muốn theo hướng AI thì học gì trước").
  List<Subject> findSeeds(String question, List<Subject> subjects) {
    final codeHits = _codePattern
        .allMatches(question.toUpperCase())
        .map((m) => m.group(0)!)
        .toSet();

    final byCode = <Subject>[];
    final rest = <Subject>[];
    for (final s in subjects) {
      if (codeHits.contains(s.code.toUpperCase())) {
        byCode.add(s);
      } else {
        rest.add(s);
      }
    }

    return [...byCode, ..._rankByKeyword(question, rest)];
  }

  List<Subject> _rankByKeyword(String question, List<Subject> subjects) {
    final concepts = _conceptsOf(question);
    if (concepts.isEmpty) return const [];

    final scored = <(Subject, int)>[];
    for (final s in subjects) {
      final score = _score(s, concepts);
      if (score > 0) scored.add((s, score));
    }
    if (scored.isEmpty) return const [];

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final best = scored.first.$2;

    // Ngưỡng tương đối: khi đã có môn khớp mạnh thì loại các môn chỉ khớp
    // lướt qua ở phần mô tả; còn khi cả nhóm đều khớp yếu thì vẫn giữ lại,
    // vì lúc đó chúng là manh mối duy nhất.
    final cutoff = (best * 2 / 3).ceil();
    return scored
        .where((x) => x.$2 >= cutoff)
        .take(maxKeywordSeeds)
        .map((x) => x.$1)
        .toList();
  }

  /// Mỗi "khái niệm" là một nhóm cách viết cùng nghĩa. Khớp được bất kỳ cách
  /// viết nào cũng chỉ tính điểm một lần, để câu hỏi nhắc "AI" không ăn điểm
  /// gấp bốn lần chỉ vì bảng viết tắt liệt kê bốn biến thể.
  List<List<String>> _conceptsOf(String question) {
    final tokens = _normalize(question)
        .split(_tokenSplitter)
        .where((t) => t.isNotEmpty)
        .toList();
    final upperTokens = _upperCasePattern
        .allMatches(question)
        .map((m) => m.group(0)!.toLowerCase())
        .toSet();

    final concepts = <List<String>>[];
    for (final t in tokens) {
      if (t.length < 2 || _stopwords.contains(t)) continue;
      final forms = <String>[t];
      final aliases = _aliases[t];
      // Viết tắt hai chữ cái dễ đụng từ tiếng Việt thường ("ai" là "who"),
      // nên chỉ bung nghĩa viết tắt khi người dùng gõ hoa cả cụm: "hướng AI"
      // được mở rộng, còn "Ai là người dạy môn này" thì không.
      if (aliases != null && (t.length > 2 || upperTokens.contains(t))) {
        forms.addAll(aliases);
      }
      concepts.add(forms);
    }

    // Cụm hai từ liền nhau ("cau truc", "do thi") phân biệt tốt hơn từ đơn và
    // không bị danh sách stopword cắt mất — quan trọng với tiếng Việt, nơi bỏ
    // dấu xong "đồ" và "đó" đều thành "do".
    for (var i = 0; i + 1 < tokens.length; i++) {
      concepts.add(['${tokens[i]} ${tokens[i + 1]}']);
    }
    return concepts;
  }

  int _score(Subject subject, List<List<String>> concepts) {
    final strong = _normalize('${subject.code} ${subject.name}');
    final weak = _normalize(subject.description);
    final strongTokens = strong.split(_tokenSplitter).toSet();
    final weakTokens = weak.split(_tokenSplitter).toSet();

    var score = 0;
    for (final forms in concepts) {
      if (forms.any((f) => _hits(f, strong, strongTokens))) {
        score += 2;
      } else if (forms.any((f) => _hits(f, weak, weakTokens))) {
        score += 1;
      }
    }
    return score;
  }

  /// Cụm nhiều từ thì dò nguyên cụm; từ đơn phải khớp trọn một từ trong text
  /// (hoặc là tiền tố của nó) chứ không khớp kiểu chuỗi con lẫn lộn — nếu
  /// không, "ai" sẽ khớp bừa vào "mail", "detail".
  bool _hits(String form, String text, Set<String> textTokens) {
    if (form.contains(' ')) return text.contains(form);
    if (textTokens.contains(form)) return true;
    return form.length >= 3 && textTokens.any((t) => t.startsWith(form));
  }

  /// Bỏ dấu tiếng Việt và hạ chữ thường, để "Toán rời rạc", "toan roi rac"
  /// hay "TOÁN RỜI RẠC" đều quy về cùng một dạng so khớp.
  String _normalize(String input) {
    final buffer = StringBuffer();
    for (final ch in input.toLowerCase().split('')) {
      buffer.write(_deaccent[ch] ?? ch);
    }
    return buffer.toString();
  }

  /// BFS hai chiều (cả môn tiên quyết lẫn môn được mở ra) từ tập seed, giới
  /// hạn [hops] bước. Trả về id theo đúng thứ tự BFS, nhờ vậy khi phải cắt
  /// bớt cho vừa [maxNodes] thì các môn gần seed nhất được giữ lại.
  List<int> _expand(List<int> seedIds, List<Prerequisite> edges, int hops) {
    final neighbors = <int, Set<int>>{};
    for (final e in edges) {
      neighbors.putIfAbsent(e.subjectId, () => {}).add(e.prerequisiteId);
      neighbors.putIfAbsent(e.prerequisiteId, () => {}).add(e.subjectId);
    }

    final ordered = <int>[...seedIds];
    final visited = <int>{...seedIds};
    var frontier = <int>[...seedIds];

    for (var step = 0; step < hops; step++) {
      final next = <int>[];
      for (final id in frontier) {
        for (final n in neighbors[id] ?? const <int>{}) {
          if (visited.add(n)) {
            ordered.add(n);
            next.add(n);
          }
        }
      }
      if (next.isEmpty) break;
      frontier = next;
    }
    return ordered;
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

  // ------------------------------------------------------------------
  // Bảng tra dùng chung cho việc so khớp từ khoá
  // ------------------------------------------------------------------

  static const Map<String, String> _accentGroups = {
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'e': 'èéẹẻẽêềếệểễ',
    'i': 'ìíịỉĩ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'u': 'ùúụủũưừứựửữ',
    'y': 'ỳýỵỷỹ',
    'd': 'đ',
  };

  static final Map<String, String> _deaccent = {
    for (final entry in _accentGroups.entries)
      for (final ch in entry.value.split('')) ch: entry.key,
  };

  /// Từ chức năng trong câu hỏi tiếng Việt. Lọc ra để chúng không vô tình
  /// khớp vào phần mô tả môn và kéo theo những môn chẳng liên quan.
  static const Set<String> _stopwords = {
    'em', 'anh', 'chi', 'toi', 'minh', 'ban', 'thay', 'co',
    'muon', 'can', 'nen', 'phai', 'duoc', 'bi', 'se', 'da', 'dang', 'con',
    'hoc', 'mon', 'hoi', 'biet', 'giup', 'xin', 'cho', 'lam', 'theo', 'huong',
    'nao', 'gi', 'sao', 'the', 'nay', 'do', 'kia', 'ay',
    'la', 'thi', 'ma', 'va', 'hay', 'hoac', 'nhung',
    'cua', 'voi', 've', 'tu', 'den', 'trong', 'ngoai', 'tren', 'duoi',
    'truoc', 'sau', 'khi', 'neu', 'de', 'vao', 'ra', 'boi', 'vi',
    'cac', 'moi', 'mot', 'hai', 'ba', 'nhieu', 'it', 'het', 'ca',
    'khong', 'ko', 'chua', 'roi', 'xong', 'nhe', 'nha', 'oi', 'day',
    'bao', 'gio', 'dau', 'tai', 'nhat', 'rat', 'qua', 'cung', 'van',
  };

  /// Viết tắt hay gặp trong câu hỏi nhưng không xuất hiện nguyên văn trong
  /// tên môn. Thiếu bảng này thì hỏi "hướng AI" không khớp nổi môn nào, vì
  /// môn tên "Artificial Intelligence" chứ không tên "AI".
  static const Map<String, List<String>> _aliases = {
    'ai': ['artificial intelligence', 'tri tue nhan tao', 'machine learning'],
    'ml': ['machine learning', 'hoc may'],
    'db': ['database', 'co so du lieu'],
    'csdl': ['database', 'co so du lieu'],
    'sql': ['database', 'co so du lieu'],
    'oop': ['object oriented', 'huong doi tuong'],
    'dsa': ['data structures', 'cau truc du lieu', 'thuat toan'],
    'mobile': ['mobile', 'di dong'],
    'mang': ['network', 'mang may tinh'],
    'toan': ['mathematics'],
  };
}
