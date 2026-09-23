import '../models/graph_data.dart';
import '../models/graph_rag_context.dart';
import '../models/prerequisite.dart';
import '../models/subject.dart';
import '../models/transcript_entry.dart';
import 'academic_analytics_service.dart';
import 'db_service.dart';
import 'fap_markdown_parser.dart';
import 'settings_service.dart';

/// Một môn "hạt giống" kèm mức tin cậy của lần khớp.
///
/// [confident] đúng khi môn được gọi thẳng bằng mã, hoặc từ khoá khớp vào
/// chính mã/tên môn. Chỉ những môn như vậy mới được đính nguyên đề cương —
/// đề cương nặng cỡ nghìn token, đính nhầm môn thì vừa tốn vừa làm lệch câu
/// trả lời.
typedef SeedMatch = ({Subject subject, bool confident, bool viaCode});

/// Các mã môn mà một viết tắt trong câu hỏi trỏ tới cùng lúc, tức chỗ AI nên
/// hỏi lại thay vì tự chọn. Rỗng nghĩa là câu hỏi đủ rõ.
///
/// Ba điều kiện, thiếu một là không tính:
///
/// 1. **Khớp qua mã môn.** Gõ "jpd" là đang gọi tên một môn cụ thể nhưng gọi
///    thiếu. Khớp qua tên/chủ đề ("software") lại là câu hỏi rộng thật lòng,
///    hỏi lại chỉ làm phiền.
/// 2. **Không môn nào đủ tin.** Có một môn nổi trội thì cứ trả lời môn đó.
/// 3. **Từ hai môn trở lên.** Một môn thì chẳng có gì để hỏi.
List<String> ambiguousCodeMatches(List<SeedMatch> seeds) {
  if (seeds.any((s) => s.confident)) return const [];
  final codes = [
    for (final s in seeds)
      if (s.viaCode) s.subject.code,
  ];
  return codes.length >= 2 ? codes : const [];
}

/// Một khái niệm trong câu hỏi, kèm đánh giá độ hiếm của nó trong danh mục.
///
/// [specific] đúng khi khái niệm chỉ khớp một nhúm môn — lúc đó nó thật sự
/// trỏ tới môn cụ thể. Từ rộng như "engineer" (khớp 5/64 môn) vẫn được dùng
/// để tìm môn, nhưng không đủ tư cách để app dám đính nguyên đề cương.
typedef _Concept = ({List<String> forms, bool specific});

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
  final SettingsService _settings = SettingsService.instance;

  /// Bắt các mã môn kiểu "PRF192", "CSD201" xuất hiện trong câu hỏi.
  static final RegExp _codePattern = RegExp(r'\b[A-Z]{2,4}\d{2,4}[A-Z]?\b');

  static final RegExp _tokenSplitter = RegExp(r'[^a-z0-9]+');

  /// Cụm viết hoa liền nhau ("AI", "SQL"), dùng để tách viết tắt khỏi từ
  /// tiếng Việt viết thường trùng mặt chữ.
  static final RegExp _upperCasePattern = RegExp(r'\b[A-Z]{2,}\b');

  /// Số môn hạt giống tối đa suy ra từ từ khoá, để một câu hỏi chung chung
  /// không kéo theo cả chục môn rồi phình ngược ngữ cảnh.
  static const int maxKeywordSeeds = 5;

  /// Điểm cho từng nơi khớp, xếp theo mức chắc chắn của bằng chứng.
  ///
  /// Mã môn nặng nhất vì nó là định danh duy nhất, và người dùng rất hay viết
  /// tắt mã ("csd", "swr", "prf"). Ca thật đã xảy ra: câu "điểm trung bình
  /// csd và swr của tôi là bao nhiêu" từng mất hẳn SWR302 — hồi đó khớp mã và
  /// khớp tên được tính điểm ngang nhau, nên mấy môn tình cờ có chữ "trung"
  /// trong tên đủ sức hoà điểm rồi chen chỗ, mà chỉ giữ 5 hạt giống.
  static const int scoreCodeHit = 4;
  static const int scoreNameHit = 2;
  static const int scoreDescriptionHit = 1;

  /// Trần số node của subgraph. Đồ thị thật có vài chục môn, BFS 2 bước từ
  /// nhiều seed có thể chạm gần hết đồ thị và làm mất ý nghĩa của việc thu hẹp.
  static const int maxNodes = 24;

  /// Trần thấp hơn khi có kèm điểm.
  ///
  /// Mỗi dòng môn dài thêm khoảng 55 ký tự (~14 token) vì phần điểm, cộng với
  /// khối tóm tắt học lực ở đầu prompt (~90 token). Hạ trần xuống 20 giữ tổng
  /// token của phần đồ thị xấp xỉ như cũ, để phần đề cương phía sau không bị
  /// nhà cung cấp cắt mất.
  static const int maxNodesWithGrades = 20;

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

  /// Chặn trên cho phần mô tả trong bản đề cương rút gọn.
  static const int maxOutlineDescriptionChars = 400;

  /// Từ khoá khớp quá tỉ lệ này trong danh mục thì bị bỏ, vì nó không chỉ ra
  /// được môn nào cả.
  ///
  /// Câu "tôi muốn làm AI Engineer nên học gì" từng kéo về `GRC490`,
  /// `SWE201C`, `SE_GRA_ELE`: chữ "engineer" khớp tiền tố vào "Engineering"
  /// nằm trong tên hàng loạt môn, lấn át tín hiệu thật là "AI". Chữ càng phổ
  /// biến trong danh mục thì càng ít giá trị phân biệt — đúng ý tưởng IDF
  /// trong tìm kiếm, và đếm được ngay tại chỗ nên không tốn token nào.
  static const double maxConceptMatchRatio = 0.25;

  /// Danh mục nhỏ hơn mức này thì bỏ qua phép lọc trên: 25% của 6 môn chỉ là
  /// 1-2 môn, tỉ lệ lúc đó không nói lên điều gì.
  static const int minSubjectsForCommonFilter = 12;

  /// Từ khoá chỉ được coi là **đặc hiệu** khi khớp không quá ngần này môn.
  ///
  /// Con số nhỏ và tuyệt đối, không theo tỉ lệ danh mục, vì câu hỏi cần trả
  /// lời là "từ khoá này có trỏ tới đúng một môn không". Đo trên dữ liệu thật
  /// (64 môn): "engineer" khớp 4 môn — chọn 2 trong 4 để đính đề cương chỉ là
  /// tung đồng xu, còn một từ khớp 1-2 môn thì gần như chắc chắn đúng ý người
  /// hỏi.
  ///
  /// Chỉ dùng để quyết định có đính nguyên đề cương hay không, không loại môn
  /// khỏi ngữ cảnh: khớp rộng vẫn đáng đưa vào danh sách, chỉ là không đáng
  /// trả giá nghìn token cho mỗi đề cương.
  static const int maxMatchesForSpecific = 2;

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

    // Bảng điểm chỉ được đính khi người dùng còn bật công tắc trong Cài đặt —
    // đây là chỗ dữ liệu cá nhân rời khỏi máy, nên tôn trọng lựa chọn đó ngay
    // tại nguồn chứ không chỉ ẩn nút ở giao diện.
    final grades = await _loadGrades(graph);

    final seedMatches = seedsWithConfidence(question, graph.subjects);
    final seeds = seedMatches.map((s) => s.subject).toList();
    final isFallback = seeds.isEmpty;


    // Nhánh fallback cố tình KHÔNG cắt bớt: lúc đã không đoán được câu hỏi
    // nhắm vào môn nào, đưa thiếu môn còn tai hại hơn là đưa dư.
    final Set<int> subgraphIds;
    if (isFallback) {
      subgraphIds = graph.subjects.map((s) => s.id!).toSet();
    } else {
      final ordered = _expand(seeds.map((s) => s.id!).toList(), graph.edges, hops);
      subgraphIds = ordered
          .take(grades.isEmpty ? maxNodes : maxNodesWithGrades)
          .toSet();
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

    // Đề cương nặng cỡ nghìn token mỗi môn, nên chỉ đính khi đã chắc đúng
    // môn: được gọi thẳng bằng mã, hoặc từ khoá khớp vào chính mã/tên môn.
    // Khớp mập mờ ở phần mô tả thì chỉ đưa mã + tên + mô tả ngắn — trước đây
    // vẫn đính đề cương cho cả những môn đoán sai, vừa tốn vừa làm lệch câu
    // trả lời.
    final syllabi = await _loadSyllabiFor(
      seedMatches.where((s) => s.confident).map((s) => s.subject).take(maxSyllabi),
    );

    final promptText = _renderPrompt(
      nodes,
      edges,
      graph.byId,
      isFallback,
      syllabi,
      grades.byCode,
      grades.profile,
      ambiguousCodeMatches(seedMatches),
    );
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
        includesTranscript: grades.isNotEmpty,
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
  List<Subject> findSeeds(String question, List<Subject> subjects) =>
      seedsWithConfidence(question, subjects).map((s) => s.subject).toList();

  /// Như [findSeeds] nhưng kèm mức tin cậy của từng môn, để [buildContext]
  /// biết môn nào đáng đính nguyên đề cương.
  List<SeedMatch> seedsWithConfidence(String question, List<Subject> subjects) {
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

    return [
      // Gọi thẳng mã môn đầy đủ là tín hiệu chắc chắn nhất, luôn đủ tin.
      for (final s in byCode) (subject: s, confident: true, viaCode: true),
      ..._rankByKeyword(question, rest),
    ];
  }

  bool _looksGlobal(String question) {
    final normalized = _normalize(question);
    return _globalIntentPhrases.any(normalized.contains);
  }

  List<SeedMatch> _rankByKeyword(String question, List<Subject> subjects) {
    final concepts = _weighConcepts(_conceptsOf(question), subjects);
    if (concepts.isEmpty) return const [];

    final scored = <({Subject subject, int score, bool strong, bool viaCode})>[];
    for (final s in subjects) {
      final hit = _score(s, concepts);
      // Bỏ dấu tiếng Việt xong rất nhiều âm tiết trùng nhau: "lập lộ trình"
      // và "lập trình" cùng ra "lap ... trinh". Vài âm tiết lẻ trùng vào phần
      // mô tả vì thế không đủ để coi là nhắc tới môn đó — phải khớp mã/tên,
      // hoặc khớp trọn một cụm từ.
      if (hit.score > 0 && hit.reliable) {
        scored.add((
          subject: s,
          score: hit.score,
          strong: hit.strong,
          viaCode: hit.codeHit,
        ));
      }
    }
    if (scored.isEmpty) return const [];

    // Hoà điểm thì xếp theo mã môn, để cùng một câu hỏi luôn ra cùng kết quả.
    // Trước đây thứ tự phụ thuộc vào cách sort xử lý phần tử bằng nhau, nên
    // môn nào lọt vào top 5 là chuyện hên xui.
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.subject.code.compareTo(b.subject.code);
    });
    final best = scored.first.score;

    // Ngưỡng tương đối: khi đã có môn khớp mạnh thì loại các môn chỉ khớp
    // lướt qua ở phần mô tả; còn khi cả nhóm đều khớp yếu thì vẫn giữ lại,
    // vì lúc đó chúng là manh mối duy nhất.
    final cutoff = (best * 2 / 3).ceil();
    return scored
        .where((x) => x.score >= cutoff)
        .take(maxKeywordSeeds)
        // Khớp vào mã/tên môn mới đủ chắc để dám đính nguyên đề cương; khớp
        // vào phần mô tả thì chỉ đủ để đưa môn đó vào danh sách.
        .map((x) =>
            (subject: x.subject, confident: x.strong, viaCode: x.viaCode))
        .toList();
  }

  /// Đếm độ phổ biến của từng khái niệm trong danh mục, bỏ những khái niệm
  /// quá phổ biến và đánh dấu những khái niệm đủ hiếm để tin.
  ///
  /// Một chữ xuất hiện ở 1/4 số môn thì không giúp chọn ra môn nào — giữ lại
  /// chỉ khiến các môn vô can lọt vào ngữ cảnh, vừa tốn token vừa làm câu trả
  /// lời loãng đi.
  List<_Concept> _weighConcepts(
    List<List<String>> concepts,
    List<Subject> subjects,
  ) {
    // Danh mục quá nhỏ thì không đo được độ phổ biến; coi mọi khái niệm là
    // đặc hiệu, tức giữ nguyên hành vi cũ.
    if (subjects.length < minSubjectsForCommonFilter) {
      return [for (final forms in concepts) (forms: forms, specific: true)];
    }

    final dropAbove = (subjects.length * maxConceptMatchRatio).ceil();

    final kept = <_Concept>[];
    for (final forms in concepts) {
      var matches = 0;
      for (final s in subjects) {
        if (_matchesAny(forms, s)) matches++;
        if (matches > dropAbove) break;
      }
      if (matches > dropAbove) continue;
      kept.add((
        forms: forms,
        specific: matches > 0 && matches <= maxMatchesForSpecific,
      ));
    }
    return kept;
  }

  bool _matchesAny(List<String> forms, Subject subject) {
    final strong = _normalize('${subject.code} ${subject.name}');
    final weak = _normalize(subject.description);
    final strongTokens = strong.split(_tokenSplitter).toSet();
    final weakTokens = weak.split(_tokenSplitter).toSet();

    for (final f in forms) {
      if (_hits(f, strong, strongTokens) || _hits(f, weak, weakTokens)) {
        return true;
      }
    }
    return false;
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
  ///
  /// [strong] chặt hơn: có khớp thẳng vào mã hoặc tên môn. Tên môn là thứ mô
  /// tả môn đó đúng nhất, nên đây là mức tin cậy đủ để dám đính nguyên đề
  /// cương — khớp vào phần mô tả thì chưa.
  ({int score, bool reliable, bool strong, bool codeHit}) _score(
    Subject subject,
    List<_Concept> concepts,
  ) {
    final code = _normalize(subject.code);
    final name = _normalize(subject.name);
    final description = _normalize(subject.description);
    final codeTokens = code.split(_tokenSplitter).toSet();
    final nameTokens = name.split(_tokenSplitter).toSet();
    final descriptionTokens = description.split(_tokenSplitter).toSet();

    var score = 0;
    var reliable = false;
    var matchedStrongField = false;
    var matchedCode = false;

    for (final concept in concepts) {
      String? hitForm;
      int? points;
      var inStrongField = false;

      for (final f in concept.forms) {
        if (_hits(f, code, codeTokens)) {
          hitForm = f;
          points = scoreCodeHit;
          inStrongField = true;
          matchedCode = true;
          break;
        }
      }
      if (hitForm == null) {
        for (final f in concept.forms) {
          if (_hits(f, name, nameTokens)) {
            hitForm = f;
            points = scoreNameHit;
            inStrongField = true;
            break;
          }
        }
      }
      if (hitForm == null) {
        for (final f in concept.forms) {
          if (_hits(f, description, descriptionTokens)) {
            hitForm = f;
            points = scoreDescriptionHit;
            break;
          }
        }
      }
      if (hitForm == null) continue;

      score += points!;
      // Chỉ khớp bằng từ đặc hiệu vào mã/tên môn mới đủ chắc để đính đề
      // cương. "engineer" khớp tên 4 môn kỹ thuật không nói lên câu hỏi đang
      // nhắm vào môn nào trong số đó.
      if (inStrongField && concept.specific) matchedStrongField = true;
      if (inStrongField || hitForm.contains(' ')) reliable = true;
    }
    return (
      score: score,
      reliable: reliable,
      strong: matchedStrongField,
      codeHit: matchedCode,
    );
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

  /// Nạp bảng điểm để đính kèm ngữ cảnh.
  ///
  /// Trả về rỗng khi chưa nhập bảng điểm hoặc khi người dùng đã tắt công tắc
  /// "Gửi bảng điểm kèm câu hỏi cho AI" — hai trường hợp đó đi cùng một
  /// nhánh: prompt không có một con điểm nào.
  Future<_TranscriptContext> _loadGrades(GraphData graph) async {
    try {
      if (!await _settings.getSendTranscriptToAi()) {
        return const _TranscriptContext.empty();
      }
      final entries = await _db.getTranscript();
      if (entries.isEmpty) return const _TranscriptContext.empty();
      return _TranscriptContext(
        byCode: AcademicAnalyticsService.instance.latestByCode(entries),
        profile: AcademicAnalyticsService.instance.analyze(entries, graph),
      );
    } catch (_) {
      // Chưa có bảng điểm hoặc dữ liệu hỏng — vẫn trả lời được bằng phần
      // đồ thị, không để cả câu hỏi chết vì phần phụ này.
      return const _TranscriptContext.empty();
    }
  }

  /// Một câu mô tả tình hình học môn này, nối vào cuối dòng của môn đó.
  ///
  /// Môn chưa học cũng phải có câu của nó: im lặng thì AI không phân biệt được
  /// "chưa học" với "không có dữ liệu" và sẽ suy diễn bừa về năng lực.
  String _gradeSentence(TranscriptEntry? entry) {
    if (entry == null) return ' Sinh viên chưa học.';
    switch (entry.status) {
      case SubjectStatus.passed:
        final when = entry.semesterLabel.isEmpty
            ? ''
            : ' (${entry.semesterLabel})';
        return entry.hasGrade
            ? ' Điểm của sinh viên: ${entry.displayGrade} — Đã qua$when.'
            : ' Sinh viên đã qua môn này, môn không chấm điểm$when.';
      case SubjectStatus.notPassed:
        return entry.hasGrade
            ? ' Sinh viên chưa qua môn này (điểm ${entry.displayGrade}).'
            : ' Sinh viên chưa qua môn này.';
      case SubjectStatus.studying:
        return ' Sinh viên đang học.';
      case SubjectStatus.notStarted:
      case SubjectStatus.unknown:
        return ' Sinh viên chưa học.';
    }
  }

  String _renderPrompt(
    List<Subject> nodes,
    List<Prerequisite> edges,
    Map<int, Subject> byId,
    bool isFallback,
    List<FapSyllabusImport> syllabi,
    Map<String, TranscriptEntry> gradeByCode,
    AcademicProfile? profile,
    List<String> ambiguousCodes,
  ) {
    if (nodes.isEmpty) {
      return 'Không tìm thấy môn học nào liên quan trực tiếp đến câu hỏi trong CSDL.';
    }
    final sb = StringBuffer();
    if (ambiguousCodes.isNotEmpty) {
      // Đặt lên đầu prompt để AI đọc thấy trước cả danh sách môn, khỏi lỡ
      // chọn đại một môn rồi mới thấy dòng này ở cuối.
      sb
        ..writeln(
          'LƯU Ý: mã môn viết tắt trong câu hỏi khớp nhiều môn cùng lúc: '
          '${ambiguousCodes.join(", ")}. Nếu câu hỏi nhắm tới một môn cụ thể, '
          'hãy hỏi lại người dùng muốn môn nào trong số đó thay vì tự chọn. '
          'Nếu câu hỏi áp dụng cho cả nhóm thì cứ trả lời cho cả nhóm.',
        )
        ..writeln();
    }
    if (profile != null) {
      sb
        ..writeln(profile.summaryLine)
        ..writeln();
    }
    sb.write(isFallback
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
      sb.write(description.isEmpty ? '.' : '. Nội dung: $description');
      sb.writeln(
        gradeByCode.isEmpty
            ? ''
            : _gradeSentence(gradeByCode[s.code.toUpperCase()]),
      );
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
  /// Bản rút gọn của [renderSyllabusForPrompt], dùng cho việc sinh câu hỏi
  /// gợi ý chứ không phải để trả lời.
  ///
  /// Để đặt được 4 câu hỏi sát nội dung thì chỉ cần biết môn dạy gì và có
  /// những loại đánh giá nào — không cần đọc trọn 45 buổi học, từng chuẩn đầu
  /// ra hay từng tiêu chí chấm. Giữ đúng phần gợi được câu hỏi, bỏ phần còn
  /// lại, nên nhẹ hơn bản đầy đủ khoảng một bậc.
  ///
  /// Vẫn nêu *số lượng* buổi học và chuẩn đầu ra, vì chính những con số đó
  /// giúp AI đặt câu hỏi cụ thể thay vì hỏi chung chung.
  String renderSyllabusOutlineForPrompt(FapSyllabusImport syl) {
    final sb = StringBuffer();

    final description = syl.description.trim();
    if (description.isNotEmpty) {
      // Mô tả là trường hữu ích nhất ở đây, nhưng vẫn chặn trên phòng khi
      // trường này dài bất thường, kẻo mất luôn ý nghĩa của bản rút gọn.
      sb.writeln(
        'Mô tả môn học: '
        '${description.length <= maxOutlineDescriptionChars ? description : '${description.substring(0, maxOutlineDescriptionChars)}…'}',
      );
    }
    if (syl.clos.isNotEmpty) {
      sb.writeln('Môn có ${syl.clos.length} chuẩn đầu ra (CLO).');
    }
    if (syl.assessments.isNotEmpty) {
      final parts = syl.assessments
          .map((a) => '${a.category} ${a.weightPercent}%')
          .join(', ');
      sb.writeln('Các đầu điểm đánh giá: $parts.');
    }
    if (syl.sessions.isNotEmpty) {
      sb.writeln('Lịch trình gồm ${syl.sessions.length} buổi học.');
    }
    return sb.toString();
  }

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
    // Từ hay gặp khi hỏi về điểm số. Không môn nào tên là "điểm" hay "trung
    // bình", nên để lại chỉ tổ khớp bừa vào tên/mô tả rồi chen chỗ của môn
    // thật — đúng ca "điểm trung bình csd và swr" đã gặp.
    'diem', 'trung', 'binh',
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

/// Bảng điểm đã nạp sẵn cho một lần dựng ngữ cảnh.
class _TranscriptContext {
  final Map<String, TranscriptEntry> byCode;
  final AcademicProfile? profile;

  const _TranscriptContext({required this.byCode, required this.profile});

  const _TranscriptContext.empty() : byCode = const {}, profile = null;

  bool get isEmpty => byCode.isEmpty;
  bool get isNotEmpty => byCode.isNotEmpty;
}
