import '../models/graph_rag_context.dart';
import '../models/prerequisite.dart';
import '../models/subject.dart';
import 'db_service.dart';
import 'fap_markdown_parser.dart';

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

  /// Số môn được đính kèm nguyên đề cương. Đề cương đầy đủ nặng cỡ nghìn
  /// token, chỉ đính cho vài môn khớp mạnh nhất chứ không cho cả subgraph.
  static const int maxSyllabi = 2;

  /// Cắt bớt mô tả từng môn khi liệt kê. Mô tả dài chỉ cần vài dòng đầu là đủ
  /// để AI biết môn đó dạy gì.
  static const int maxDescriptionChars = 160;

  /// Trần khi ghép một đề cương vào prompt. Đề cương FAP có thể tới 60 buổi
  /// và cả chục đầu tài liệu; gửi trọn thì phần lớn token tiêu vào dữ liệu
  /// người hỏi không đụng tới.
  static const int maxSyllabusSessions = 45;
  static const int maxSyllabusMaterials = 8;

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

    // Đề cương chỉ đính cho vài môn được nhắc thẳng trong câu hỏi. Đính cho
    // cả subgraph thì riêng phần này đã vài chục nghìn token.
    final syllabi = await _loadSyllabiFor(seeds.take(maxSyllabi));

    final promptText =
        _renderPrompt(nodes, edges, graph.byId, isFallback, syllabi);
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
  ///
  /// Trả về rỗng khi câu hỏi hướng tới cả chương trình, để [buildContext]
  /// chuyển sang dùng toàn đồ thị.
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

    // Hỏi về cả lộ trình mà lại thu hẹp quanh vài môn thì trả lời sẽ sai bản
    // chất: muốn xếp thứ tự học thì phải nhìn toàn đồ thị. Mã môn viết thẳng
    // vẫn được ưu tiên, vì lúc đó người dùng đang nhắm vào môn cụ thể.
    if (byCode.isEmpty && _looksGlobal(question)) return const [];

    return [...byCode, ..._rankByKeyword(question, rest)];
  }

  bool _looksGlobal(String question) {
    final normalized = _normalize(question);
    return _globalIntentPhrases.any(normalized.contains);
  }

  List<Subject> _rankByKeyword(String question, List<Subject> subjects) {
    final concepts = _conceptsOf(question);
    if (concepts.isEmpty) return const [];

    final scored = <(Subject, int)>[];
    for (final s in subjects) {
      final hit = _score(s, concepts);
      // Bỏ dấu tiếng Việt xong rất nhiều âm tiết trùng nhau: "lập lộ trình"
      // và "lập trình" cùng ra "lap ... trinh". Vài âm tiết lẻ trùng vào phần
      // mô tả vì thế không đủ để coi là nhắc tới môn đó — phải khớp mã/tên,
      // hoặc khớp trọn một cụm từ.
      if (hit.score > 0 && hit.reliable) scored.add((s, hit.score));
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

  /// [reliable] đánh dấu có ít nhất một bằng chứng đáng tin: khớp vào mã/tên
  /// môn, hoặc khớp trọn một cụm từ nhiều chữ. Khớp lẻ từng âm tiết vào phần
  /// mô tả vẫn cộng điểm nhưng không tự nó đủ để chọn môn.
  ({int score, bool reliable}) _score(
    Subject subject,
    List<List<String>> concepts,
  ) {
    final strong = _normalize('${subject.code} ${subject.name}');
    final weak = _normalize(subject.description);
    final strongTokens = strong.split(_tokenSplitter).toSet();
    final weakTokens = weak.split(_tokenSplitter).toSet();

    var score = 0;
    var reliable = false;

    for (final forms in concepts) {
      String? hitForm;
      var inStrong = false;

      for (final f in forms) {
        if (_hits(f, strong, strongTokens)) {
          hitForm = f;
          inStrong = true;
          break;
        }
      }
      if (hitForm == null) {
        for (final f in forms) {
          if (_hits(f, weak, weakTokens)) {
            hitForm = f;
            break;
          }
        }
      }
      if (hitForm == null) continue;

      score += inStrong ? 2 : 1;
      if (inStrong || hitForm.contains(' ')) reliable = true;
    }
    return (score: score, reliable: reliable);
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

  /// Nạp đề cương của vài môn khớp mạnh nhất. Môn chưa nhập đề cương thì bỏ
  /// qua, không phải lỗi.
  Future<List<FapSyllabusImport>> _loadSyllabiFor(Iterable<Subject> seeds) async {
    final result = <FapSyllabusImport>[];
    for (final s in seeds) {
      if (s.id == null) continue;
      try {
        final syl = await _db.getSyllabusDetail(subjectId: s.id);
        if (syl != null) result.add(syl);
      } catch (_) {
        // Chưa có bảng đề cương hoặc dữ liệu hỏng — vẫn trả lời được bằng
        // phần đồ thị.
      }
    }
    return result;
  }

  String _renderPrompt(
    List<Subject> nodes,
    List<Prerequisite> edges,
    Map<int, Subject> byId,
    bool isFallback,
    List<FapSyllabusImport> syllabi,
  ) {
    if (nodes.isEmpty) {
      return 'Không tìm thấy môn học nào liên quan trực tiếp đến câu hỏi trong CSDL.';
    }
    final sb = StringBuffer(isFallback
        ? 'Câu hỏi hướng tới cả chương trình, đây là toàn bộ danh sách môn '
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
      final description = _shorten(s.description);
      sb.writeln(description.isEmpty ? '.' : '. Nội dung: $description');
    }

    for (final syl in syllabi) {
      sb
        ..writeln()
        ..writeln('Đề cương chi tiết của ${syl.subjectCode}:')
        ..writeln(renderSyllabusForPrompt(syl));
    }
    return sb.toString();
  }

  String _shorten(String text) {
    final clean = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length <= maxDescriptionChars) return clean;
    return '${clean.substring(0, maxDescriptionChars)}…';
  }

  /// Dựng đề cương FAP thành văn bản gọn để nhét vào prompt.
  ///
  /// Dùng chung cho cả chat toàn cục lẫn khung chat theo từng môn, nên chỉ có
  /// một định dạng duy nhất phải chỉnh khi muốn đổi cách mớm cho AI.
  ///
  /// Chỉ lấy phần sinh viên thật sự hỏi tới (mô tả, CLO, tài liệu, lịch trình,
  /// đầu điểm) và bỏ hết phần hành chính (số quyết định, ngày duyệt, trạng
  /// thái active...) — những thứ đó chỉ tốn token chứ không giúp trả lời.
  String renderSyllabusForPrompt(FapSyllabusImport syl) {
    final sb = StringBuffer();

    void line(String label, String value) {
      if (value.trim().isNotEmpty) sb.writeln('$label: ${value.trim()}');
    }

    line('Tên môn (EN)', syl.nameEn);
    line('Tên môn (VN)', syl.nameNative);
    line('Bậc đào tạo', syl.degreeLevel);
    line('Phương pháp giảng dạy', syl.learningTeachingMethod);
    line('Phân bổ thời gian', syl.timeAllocation);
    line('Mô tả môn học', syl.description);
    line('Nhiệm vụ của sinh viên', syl.studentTasks);
    line('Công cụ sử dụng', syl.tools);
    if (syl.scoringScale != null) {
      line('Thang điểm', '${syl.scoringScale}');
    }
    if (syl.minAvgMarkToPass != null) {
      line('Điểm trung bình tối thiểu để qua môn', '${syl.minAvgMarkToPass}');
    }
    line('Điều kiện tiên quyết (nguyên văn)', syl.rawPrerequisiteText);

    if (syl.clos.isNotEmpty) {
      sb.writeln('Chuẩn đầu ra môn học (CLO):');
      for (final c in syl.clos) {
        sb.writeln('- ${c.code}: ${c.detail}');
      }
    }

    if (syl.assessments.isNotEmpty) {
      sb.writeln('Các đầu điểm đánh giá:');
      for (final a in syl.assessments) {
        final parts = <String>[
          '${a.category} — ${a.weightPercent}%',
          if (a.type.trim().isNotEmpty) 'hình thức: ${a.type.trim()}',
          if (a.duration.trim().isNotEmpty) 'thời lượng: ${a.duration.trim()}',
          if (a.completionCriteria.trim().isNotEmpty)
            'điều kiện: ${a.completionCriteria.trim()}',
          if (a.cloCodes.isNotEmpty) 'CLO: ${a.cloCodes.join(", ")}',
        ];
        sb.writeln('- ${parts.join(" · ")}');
      }
    }

    if (syl.materials.isNotEmpty) {
      sb.writeln('Tài liệu học tập:');
      for (final m in syl.materials.take(maxSyllabusMaterials)) {
        final tag = m.isMain ? '[Chính] ' : '';
        final author = m.author.trim().isEmpty ? '' : ' — ${m.author.trim()}';
        sb.writeln('- $tag${m.description.trim()}$author');
      }
    }

    if (syl.sessions.isNotEmpty) {
      sb.writeln('Lịch trình học (${syl.sessions.length} buổi):');
      for (final s in syl.sessions.take(maxSyllabusSessions)) {
        final clo = s.cloCodes.isEmpty ? '' : ' (${s.cloCodes.join(", ")})';
        sb.writeln('- Buổi ${s.sessionNo}: ${s.topic.trim()}$clo');
      }
      if (syl.sessions.length > maxSyllabusSessions) {
        sb.writeln(
          '- (còn ${syl.sessions.length - maxSyllabusSessions} buổi nữa, '
          'đã lược bớt)',
        );
      }
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

  /// Dấu hiệu câu hỏi nhắm tới cả chương trình chứ không tới một môn nào.
  /// Những câu này cần nhìn toàn đồ thị mới trả lời đúng được.
  static const Set<String> _globalIntentPhrases = {
    'lo trinh',
    'roadmap',
    'thu tu hoc',
    'hoc theo thu tu',
    'ky toi',
    'ky sau',
    'hoc gi tiep',
    'hoc gi truoc',
    'con lai',
    'con bao nhieu',
    'bao nhieu mon',
    'tat ca cac mon',
    'toan bo',
    'danh sach mon',
    'tong quan',
    'nut that',
    'tot nghiep',
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
