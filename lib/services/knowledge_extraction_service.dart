import 'dart:math' as math;

import '../models/knowledge.dart';
import 'knowledge_concepts.dart';

/// Trích **khái niệm** và **từ khoá** từ syllabus, rồi tính xem kiến thức của
/// các môn tương quan với nhau thế nào.
///
/// Hai lớp trích chạy song song trên cùng một bộ chuẩn hoá văn bản:
///
/// 1. **Từ điển** ([KnowledgeConcepts]) — độ chính xác cao, là xương sống để
///    nối các môn: "Đồ thị" ở MAD101 và "Đồ thị" ở CSD201 phải là cùng một
///    nút thì mới thấy được hai môn dính nhau.
/// 2. **RAKE + TF-IDF** — tách cụm từ nội dung giữa các từ dừng, chấm điểm
///    theo độ hiếm trên toàn bộ môn. Bắt được những gì từ điển chưa có
///    (`content negotiation`, `state management`...), đồng thời cho ra các
///    khái niệm "tự trích" khi một cụm xuất hiện ở vài môn cùng lúc.
///
/// Thuần Dart và không giữ trạng thái: nhận nguyên liệu, trả về
/// [KnowledgeIndex]. Nhờ vậy chạy được trong isolate phụ và kiểm thử được
/// bằng dữ liệu giả, giống cách `AcademicAnalyticsService` tách khỏi CSDL.
class KnowledgeExtractionService {
  KnowledgeExtractionService._();

  // Trọng số theo vị trí xuất hiện. Tên môn và CLO là lời tuyên bố "môn này
  // dạy gì"; một buổi học chỉ là một mẩu nhỏ của môn.
  static const double nameWeight = 4;
  static const double cloWeight = 3;
  static const double descriptionWeight = 2;
  static const double sessionWeight = 1;

  /// Khái niệm có mặt ở hơn ngần này phần trăm số môn thì coi là kỹ năng
  /// chung, không dùng để nối môn — kể cả khi từ điển không đánh dấu.
  static const double genericDocumentRatio = 0.4;

  /// Dưới ngần này môn thì tỉ lệ ở trên chưa có ý nghĩa thống kê.
  static const int minSubjectsForGenericRule = 10;

  /// Hai môn chỉ được coi là tương quan khi cosine vượt ngưỡng này.
  static const double minLinkSimilarity = 0.1;

  /// Điểm tối thiểu để tính là môn có dạy khái niệm: một lần trong CLO (3),
  /// trong mô tả (2), hay ở hai buổi học khác nhau. Nhắc thoáng qua đúng một
  /// buổi thì chưa đủ làm bằng chứng — nhiều khi chỉ là một từ trùng nghĩa.
  static const double minConceptScore = 2;

  static const int maxEvidencePerConcept = 3;
  static const int maxKeywordsPerSubject = 8;

  /// Cụm tự trích phải có ở ít nhất ngần này môn mới thành khái niệm chung.
  static const int minSubjectsForExtractedConcept = 2;

  /// Khoá không phân biệt chiều của một cặp môn, dùng cho tập cạnh có sẵn.
  static String pairKey(String a, String b) =>
      a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

  /// `PRO192` và `PRO192C` là hai bản của cùng một môn (lớp thường / học
  /// online), lệch nhau đúng một chữ cái cuối — cùng quy ước với
  /// `DbService.resolveSubjectCode`. Nối chúng với nhau là thừa.
  static bool isCodeVariant(String a, String b) {
    final x = a.toUpperCase();
    final y = b.toUpperCase();
    final (short, long) = x.length <= y.length ? (x, y) : (y, x);
    return long.length == short.length + 1 &&
        long.startsWith(short) &&
        RegExp(r'[A-Z]$').hasMatch(long);
  }

  /// Dựng chỉ mục tri thức.
  ///
  /// [directEdges] là tập [pairKey] của các cặp môn đã có cạnh tiên quyết
  /// hoặc tham khảo — dùng để tách "tương quan đã biết" khỏi "tương quan ẩn".
  static KnowledgeIndex build(
    List<KnowledgeSource> sources, {
    Set<String> directEdges = const {},
    List<ConceptDef> dictionary = KnowledgeConcepts.all,
  }) {
    final watch = Stopwatch()..start();
    final matcher = _ConceptMatcher(dictionary);
    final defs = {for (final d in dictionary) d.id: d};

    // Mã môn -> khái niệm -> tích luỹ.
    final conceptAcc = <String, Map<String, _ConceptAcc>>{};
    // Mã môn -> cụm từ -> tích luỹ.
    final phraseAcc = <String, Map<String, _PhraseAcc>>{};
    final bySubject = <String, KnowledgeSource>{};

    for (final source in sources) {
      final code = source.code.trim().toUpperCase();
      if (code.isEmpty || bySubject.containsKey(code)) continue;
      bySubject[code] = source;

      final concepts = conceptAcc[code] = {};
      final phrases = phraseAcc[code] = {};

      for (final field in _fieldsOf(source)) {
        final normalized = normalize(field.text);
        // Bỏ dấu và hạ chữ giữ nguyên độ dài chuỗi với tiếng Việt/tiếng Anh,
        // nên vị trí trong bản chuẩn hoá dùng thẳng được trên bản gốc để
        // trích đoạn dẫn chứng. Ký tự lạ làm lệch độ dài thì bỏ phần trích.
        final aligned = normalized.length == field.text.length;
        final tokens = tokenize(normalized);

        for (final m in matcher.match(tokens)) {
          final acc = concepts.putIfAbsent(m.conceptId, _ConceptAcc.new);
          acc.score += field.weight;
          if (acc.evidence.length < maxEvidencePerConcept &&
              !acc.evidence.any((e) => e.ref == field.ref)) {
            acc.evidence.add(
              ConceptEvidence(
                field.ref,
                aligned
                    ? _snippet(field.text, m.start, m.end)
                    : _clip(field.text),
              ),
            );
          }
        }

        // Cụm từ tự trích chỉ lấy từ phần tiếng Anh. Tiếng Việt bỏ dấu thì
        // "câu", "cầu", "cấu" cùng thành "cau", nên cắt cụm theo từ dừng sẽ
        // chặt "cấu trúc dữ liệu" thành "trúc dữ liệu"; phần tiếng Việt đã có
        // từ điển lo.
        if (!aligned) continue;
        for (final phrase in _candidatePhrases(normalized, field.text)) {
          final surface = field.text.substring(phrase.start, phrase.end).trim();
          if (surface.codeUnits.any((c) => c > 0x7F)) continue;
          final acc = phrases.putIfAbsent(phrase.key, _PhraseAcc.new);
          acc.tf += field.weight;
          acc.tokens = phrase.tokens;
          acc.surface ??= surface;
        }
      }
    }

    final n = bySubject.length;
    double idfOf(int df) => math.log(1 + n / math.max(1, df));

    // ------------------------------------------------------------------
    // Khái niệm từ điển
    // ------------------------------------------------------------------
    final conceptSubjects = <String, Map<String, SubjectConcept>>{};
    conceptAcc.forEach((code, map) {
      map.forEach((id, acc) {
        if (acc.score < minConceptScore) return;
        conceptSubjects.putIfAbsent(id, () => {})[code] = SubjectConcept(
          conceptId: id,
          score: acc.score,
          weight: math.log(1 + acc.score),
          evidence: List.unmodifiable(acc.evidence),
        );
      });
    });

    final concepts = <String, KnowledgeConcept>{};
    conceptSubjects.forEach((id, subjects) {
      final def = defs[id]!;
      final ratio = n == 0 ? 0.0 : subjects.length / n;
      final generic =
          def.generic ||
          (n >= minSubjectsForGenericRule && ratio > genericDocumentRatio);
      concepts[id] = KnowledgeConcept(
        id: id,
        label: def.label,
        category: def.category,
        generic: generic,
        bySubject: subjects,
        idf: idfOf(subjects.length),
      );
    });

    // ------------------------------------------------------------------
    // Cụm từ tự trích (RAKE + TF-IDF)
    // ------------------------------------------------------------------
    final phraseDf = <String, int>{};
    phraseAcc.forEach((_, map) {
      for (final key in map.keys) {
        phraseDf[key] = (phraseDf[key] ?? 0) + 1;
      }
    });

    final keywordsBySubject = <String, List<KeywordScore>>{};
    phraseAcc.forEach((code, map) {
      final ranked = <KeywordScore>[];
      map.forEach((key, acc) {
        if (!_isKeywordWorthy(acc, matcher)) return;
        final df = phraseDf[key] ?? 1;
        final lengthBonus = 1 + 0.35 * (acc.tokens.length - 1);
        final score = math.log(1 + acc.tf) * idfOf(df) * lengthBonus;
        ranked.add(KeywordScore(acc.surface ?? key, score));
      });
      ranked.sort((a, b) => b.score.compareTo(a.score));
      // Nhiều cụm cùng một nghĩa ("Stacks" / "stack") -> giữ bản đầu tiên.
      final seen = <String>{};
      keywordsBySubject[code] = [
        for (final k in ranked)
          if (seen.add(k.phrase.toLowerCase())) k,
      ].take(maxKeywordsPerSubject).toList();
    });

    // Cụm xuất hiện ở vài môn cùng lúc thành khái niệm "tự trích": chúng là
    // mạch nối mà từ điển chưa biết tới.
    final maxExtractedDf = math.max(
      minSubjectsForExtractedConcept,
      (n * 0.2).round(),
    );
    final extracted = <String, Map<String, SubjectConcept>>{};
    final extractedLabel = <String, String>{};
    phraseAcc.forEach((code, map) {
      map.forEach((key, acc) {
        final df = phraseDf[key] ?? 0;
        if (df < minSubjectsForExtractedConcept || df > maxExtractedDf) return;
        if (acc.tokens.length < 2 || acc.tf < 2) return;
        if (!_isKeywordWorthy(acc, matcher)) return;
        final id = 'auto:$key';
        extractedLabel.putIfAbsent(id, () => acc.surface ?? key);
        extracted.putIfAbsent(id, () => {})[code] = SubjectConcept(
          conceptId: id,
          score: acc.tf,
          weight: math.log(1 + acc.tf),
        );
      });
    });
    extracted.forEach((id, subjects) {
      // Lọc tf < 2 ở trên có thể làm rơi bớt môn, còn một môn thì không nối
      // được gì nữa.
      if (subjects.length < minSubjectsForExtractedConcept) return;
      concepts[id] = KnowledgeConcept(
        id: id,
        label: _capitalize(extractedLabel[id]!),
        category: KnowledgeCategory.extracted,
        extracted: true,
        bySubject: subjects,
        idf: idfOf(subjects.length),
      );
    });

    // ------------------------------------------------------------------
    // Bức tranh từng môn
    // ------------------------------------------------------------------
    final subjects = <String, SubjectKnowledge>{};
    bySubject.forEach((code, source) {
      final list = <SubjectConcept>[
        for (final c in concepts.values)
          if (c.bySubject[code] != null) c.bySubject[code]!,
      ]..sort((a, b) => b.weight.compareTo(a.weight));

      var programming = 0.0;
      for (final sc in list) {
        final concept = concepts[sc.conceptId]!;
        if (concept.category == KnowledgeCategory.programming &&
            !concept.generic) {
          programming += sc.weight;
        }
      }

      subjects[code] = SubjectKnowledge(
        code: code,
        name: source.name,
        semester: source.semester,
        hasSyllabus: source.hasSyllabus,
        concepts: list,
        keywords: keywordsBySubject[code] ?? const [],
        programmingScore: 1 - math.exp(-programming / 2.5),
      );
    });

    // ------------------------------------------------------------------
    // Tương quan tri thức giữa từng cặp môn
    // ------------------------------------------------------------------
    final vectors = <String, Map<String, double>>{};
    final norms = <String, double>{};
    for (final entry in subjects.entries) {
      final v = <String, double>{};
      for (final sc in entry.value.concepts) {
        final concept = concepts[sc.conceptId]!;
        if (!concept.linking) continue;
        v[sc.conceptId] = sc.weight * concept.idf;
      }
      vectors[entry.key] = v;
      norms[entry.key] = math.sqrt(
        v.values.fold<double>(0, (sum, x) => sum + x * x),
      );
    }

    final codes = subjects.keys.toList()..sort();
    final links = <KnowledgeLink>[];
    for (var i = 0; i < codes.length; i++) {
      final a = codes[i];
      final va = vectors[a]!;
      if (va.isEmpty) continue;
      for (var j = i + 1; j < codes.length; j++) {
        final b = codes[j];
        final vb = vectors[b]!;
        if (vb.isEmpty || isCodeVariant(a, b)) continue;

        var dot = 0.0;
        final shared = <String, double>{};
        final (small, large) = va.length <= vb.length ? (va, vb) : (vb, va);
        small.forEach((id, x) {
          final y = large[id];
          if (y == null) return;
          dot += x * y;
          shared[id] = math.min(x, y);
        });
        if (shared.isEmpty) continue;

        final sim = dot / (norms[a]! * norms[b]!);
        if (sim < minLinkSimilarity) continue;

        final sa = subjects[a]!;
        final sb = subjects[b]!;
        final aFirst = sa.semester != sb.semester
            ? sa.semester < sb.semester
            : a.compareTo(b) <= 0;
        final ids = shared.keys.toList()
          ..sort((x, y) => shared[y]!.compareTo(shared[x]!));

        links.add(
          KnowledgeLink(
            from: aFirst ? a : b,
            to: aFirst ? b : a,
            similarity: sim,
            strength: shared.values.fold<double>(0, (s, x) => s + x),
            sharedConceptIds: ids,
            hasDirectEdge: directEdges.contains(pairKey(a, b)),
          ),
        );
      }
    }
    // Xếp theo độ mạnh chứ không theo cosine: xem [KnowledgeLink.strength].
    links.sort((x, y) => y.strength.compareTo(x.strength));

    watch.stop();
    return KnowledgeIndex(
      concepts: concepts,
      subjects: subjects,
      links: links,
      elapsed: watch.elapsed,
    );
  }

  // ------------------------------------------------------------------
  // CHUẨN HOÁ & TÁCH TỪ
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

  static final Map<int, int> _deaccent = {
    for (final entry in _accentGroups.entries)
      for (final ch in entry.value.codeUnits) ch: entry.key.codeUnitAt(0),
  };

  /// Hạ chữ thường và bỏ dấu tiếng Việt. Giữ nguyên độ dài chuỗi (mỗi ký tự
  /// có dấu thành đúng một ký tự không dấu) để vị trí còn dùng lại được.
  static String normalize(String input) {
    final lower = input.toLowerCase();
    final units = lower.codeUnits;
    final out = List<int>.filled(units.length, 0);
    for (var i = 0; i < units.length; i++) {
      out[i] = _deaccent[units[i]] ?? units[i];
    }
    return String.fromCharCodes(out);
  }

  static bool _isLetter(int c) => c >= 0x61 && c <= 0x7A;
  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
  static bool _isAlnum(int c) => _isLetter(c) || _isDigit(c);

  /// Dấu thanh dạng tổ hợp (Unicode NFD). Vài syllabus FAP gõ "ả" thành
  /// "a" + dấu hỏi rời; không coi dấu rời là một phần của từ thì "Đảng" bị
  /// chặt làm đôi.
  static bool _isCombiningMark(int c) => c >= 0x0300 && c <= 0x036F;

  /// Ký tự được phép nằm **bên trong** một từ: `c++`, `c#`, dấu rời.
  static bool _isInner(int c) =>
      _isAlnum(c) || c == 0x23 || c == 0x2B || _isCombiningMark(c);

  static final RegExp _letters = RegExp(r'^[a-z]+$');

  /// Tách từ trên văn bản đã [normalize].
  ///
  /// Giữ nguyên các dạng viết đặc thù của ngành: `c++`, `c#`, `.net`,
  /// `asp.net`, `node.js`, `i/o`. Dấu `/` giữa hai từ đủ dài thì tách đôi
  /// (`input/output`, `tcp/ip`, `ui/ux`); gạch nối luôn tách
  /// (`object-oriented`, `Mác-Lênin`).
  static List<KnowledgeToken> tokenize(String s) {
    final out = <KnowledgeToken>[];
    final n = s.length;
    var i = 0;
    while (i < n) {
      final c = s.codeUnitAt(i);
      final leadingDot =
          c == 0x2E &&
          i + 1 < n &&
          _isAlnum(s.codeUnitAt(i + 1)) &&
          (i == 0 || !_isInner(s.codeUnitAt(i - 1)));
      if (!_isAlnum(c) && !leadingDot) {
        i++;
        continue;
      }
      final start = i;
      i++;
      while (i < n) {
        final ch = s.codeUnitAt(i);
        if (_isInner(ch)) {
          i++;
          continue;
        }
        // `/` nằm trong từ khi ngay sau nó vẫn là chữ/số. `.` thì chặt hơn:
        // chữ.chữ (`asp.net`) hoặc số.số (`1.3`), còn "3.Data storage" là
        // số mục dính vào chữ, phải tách ra.
        if (i + 1 < n) {
          final prev = s.codeUnitAt(i - 1);
          final next = s.codeUnitAt(i + 1);
          final slash = ch == 0x2F && _isAlnum(next);
          final dot =
              ch == 0x2E &&
              ((_isLetter(prev) && _isLetter(next)) ||
                  (_isDigit(prev) && _isDigit(next)));
          if (slash || dot) {
            i++;
            continue;
          }
        }
        break;
      }
      final raw = s.substring(start, i);
      if (raw.contains('/')) {
        final parts = raw.split('/');
        if (parts.every((p) => _clean(p).length >= 2)) {
          var offset = start;
          for (final part in parts) {
            out.add(
              KnowledgeToken(stem(_clean(part)), offset, offset + part.length),
            );
            offset += part.length + 1;
          }
          continue;
        }
      }
      out.add(KnowledgeToken(stem(_clean(raw)), start, i));
    }
    return out;
  }

  /// Bỏ dấu rời khỏi một từ. Vị trí của từ vẫn tính trên chuỗi gốc.
  static String _clean(String raw) => raw.codeUnits.any(_isCombiningMark)
      ? String.fromCharCodes(raw.codeUnits.where((c) => !_isCombiningMark(c)))
      : raw;

  /// Bỏ số nhiều tiếng Anh ở mức tối thiểu. Mẫu trong từ điển và văn bản đi
  /// qua cùng một hàm, nên chỉ cần nhất quán chứ không cần đúng ngữ pháp.
  static String stem(String t) {
    if (t.length < 4 || !_letters.hasMatch(t)) return t;
    if (t.endsWith('ies') && t.length > 4) {
      return '${t.substring(0, t.length - 3)}y';
    }
    if (t.endsWith('sses') ||
        t.endsWith('xes') ||
        t.endsWith('ches') ||
        t.endsWith('shes')) {
      return t.substring(0, t.length - 2);
    }
    if (t.endsWith('s') &&
        !t.endsWith('ss') &&
        !t.endsWith('us') &&
        !t.endsWith('is')) {
      return t.substring(0, t.length - 1);
    }
    return t;
  }

  // ------------------------------------------------------------------
  // CÁC PHẦN VĂN BẢN CỦA MỘT MÔN
  // ------------------------------------------------------------------

  static List<_Field> _fieldsOf(KnowledgeSource s) {
    final fields = <_Field>[
      if (s.name.trim().isNotEmpty)
        _Field('Tên môn', s.name.replaceAll('_', ' — '), nameWeight),
      if (s.description.trim().isNotEmpty)
        _Field('Mô tả', s.description, descriptionWeight),
      for (final clo in s.clos)
        if (clo.text.trim().isNotEmpty) _Field(clo.ref, clo.text, cloWeight),
    ];

    // Syllabus FAP lặp y nguyên một chủ đề qua nhiều buổi ("Chapter 4: Cache
    // Memory" ba buổi liền). Đếm mỗi chủ đề một lần, cộng thêm theo log số
    // buổi — dạy ba buổi đáng kể hơn một buổi, nhưng không gấp ba.
    final seen = <String, int>{};
    final firstRef = <String, String>{};
    final original = <String, String>{};
    for (final session in s.sessions) {
      final key = _sessionKey(session.text);
      if (key.isEmpty) continue;
      seen[key] = (seen[key] ?? 0) + 1;
      firstRef.putIfAbsent(key, () => session.ref);
      original.putIfAbsent(key, () => session.text);
    }
    seen.forEach((key, count) {
      fields.add(
        _Field(
          firstRef[key]!,
          original[key]!,
          sessionWeight * (1 + math.log(count.toDouble())),
        ),
      );
    });
    return fields;
  }

  static final RegExp _contSuffix = RegExp(
    r"\((cont|contd|cnt|continue|continued|con't)[^)]*\)",
    caseSensitive: false,
  );

  static String _sessionKey(String topic) =>
      normalize(topic)
          .replaceAll(_contSuffix, '')
          .replaceAll(RegExp(r'[^a-z0-9#+]+'), ' ')
          .trim();

  // ------------------------------------------------------------------
  // TRÍCH ĐOẠN DẪN CHỨNG
  // ------------------------------------------------------------------

  static const int _snippetMax = 150;

  static String _clip(String text) {
    final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= _snippetMax ? t : '${t.substring(0, _snippetMax)}…';
  }

  static String _snippet(String text, int start, int end) {
    final flat = text.replaceAll(RegExp(r'\s'), ' ');
    if (flat.length <= _snippetMax) return _clip(flat);
    var from = math.max(0, start - 55);
    var to = math.min(flat.length, end + 80);
    // Lùi/tiến tới khoảng trắng gần nhất để không cắt đôi một từ.
    while (from > 0 && flat[from - 1] != ' ') {
      from--;
    }
    while (to < flat.length && flat[to] != ' ') {
      to++;
    }
    final body = flat.substring(from, to).replaceAll(RegExp(r' +'), ' ').trim();
    return '${from > 0 ? '…' : ''}$body${to < flat.length ? '…' : ''}';
  }

  // ------------------------------------------------------------------
  // CỤM TỪ ỨNG VIÊN (RAKE)
  // ------------------------------------------------------------------

  /// Ranh giới mệnh đề: dấu câu, xuống dòng, gạch đầu dòng. Cụm từ không
  /// bao giờ vắt qua một ranh giới.
  static final RegExp _clauseBreak = RegExp(
    r'[,;:()\[\]!?•\n\r\t|"“”&=<>*]|\.(?=\s|$)|\s[-–—]\s|\s-(?=\w)',
  );

  /// Số, nhãn CLO/PLO, số buổi và cả mã môn khác (`pro192`): chúng là tham
  /// chiếu chứ không phải tri thức.
  static final RegExp _junkToken = RegExp(
    r'^([\d.]+|c?lo\d.*|plo\d.*|s\d+|lab\d+|\d+\w*|[a-z]{3}\d{3}[a-z]?)$',
  );

  /// Chữ có dấu tiếng Việt, kể cả dấu rời dạng tổ hợp.
  static bool _isVietnameseChar(int c) =>
      _deaccent.containsKey(c) ||
      _isCombiningMark(c) ||
      c == 0x0110 || // Đ
      c == 0x0111;

  /// Cụm từ ứng viên của một đoạn văn bản gốc [original] (bản chuẩn hoá là
  /// [normalized], cùng độ dài).
  ///
  /// Tiếng Việt bị loại ở mức **từ**: từ có dấu là ranh giới, và một cụm
  /// không dấu mà đứng sát một từ có dấu cũng bị bỏ — "xung quanh", "tham
  /// gia" hay mẩu "duy khoa" trong "Tư duy khoa học" vốn không có dấu nhưng
  /// vẫn là tiếng Việt.
  static Iterable<_Candidate> _candidatePhrases(
    String normalized,
    String original,
  ) sync* {
    bool vietnamese(KnowledgeToken t) =>
        original.substring(t.start, t.end).codeUnits.any(_isVietnameseChar);

    var segmentStart = 0;
    final breaks = [
      ..._clauseBreak.allMatches(normalized).map((m) => (m.start, m.end)),
      (normalized.length, normalized.length),
    ];
    for (final (bStart, bEnd) in breaks) {
      if (bStart > segmentStart) {
        final segment = normalized.substring(segmentStart, bStart);
        final tokens = [
          for (final t in tokenize(segment))
            KnowledgeToken(
              t.text,
              t.start + segmentStart,
              t.end + segmentStart,
            ),
        ];
        final isVi = [for (final t in tokens) vietnamese(t)];

        var runStart = -1;
        _Candidate? candidate(int from, int to) {
          // [from, to) là chỉ số từ trong đoạn.
          if (to - from < 1 || to - from > 4) return null;
          if (from > 0 && isVi[from - 1]) return null;
          if (to < tokens.length && isVi[to]) return null;
          final run = tokens.sublist(from, to);
          return _Candidate(
            run.map((t) => t.text).join(' '),
            run.map((t) => t.text).toList(),
            run.first.start,
            run.last.end,
          );
        }

        for (var i = 0; i < tokens.length; i++) {
          final t = tokens[i];
          final isBreak =
              isVi[i] ||
              _stopwords.contains(t.text) ||
              t.text.length < 2 ||
              _junkToken.hasMatch(t.text);
          if (isBreak) {
            if (runStart >= 0) {
              final c = candidate(runStart, i);
              if (c != null) yield c;
              runStart = -1;
            }
          } else if (runStart < 0) {
            runStart = i;
          }
        }
        if (runStart >= 0) {
          final c = candidate(runStart, tokens.length);
          if (c != null) yield c;
        }
      }
      segmentStart = bEnd;
    }
  }

  /// Cụm có đáng làm từ khoá không. Cụm trùng hẳn một khái niệm từ điển thì
  /// thôi, vì khái niệm đó đã được hiển thị rồi.
  static bool _isKeywordWorthy(_PhraseAcc acc, _ConceptMatcher matcher) {
    final tokens = acc.tokens;
    if (tokens.isEmpty) return false;
    if (tokens.length == 1) {
      final t = tokens.first;
      if (t.length < 4 || _genericSingles.contains(t)) return false;
      // Từ đơn thường chỉ là một động từ lạc ra khỏi câu ("Utilize",
      // "choose"). Chỉ nhận khi nó trông như thuật ngữ — viết hoa giữa từ
      // hoặc có chữ số (OData, CSS3, IPv6) — hoặc được nhấn đi nhấn lại.
      final surface = acc.surface ?? t;
      final termLike = RegExp(r'^.+[A-Z]|\d').hasMatch(surface);
      if (!termLike && acc.tf < 8) return false;
    }
    if (tokens.every(_genericSingles.contains)) return false;
    final matches = matcher.match([
      for (var i = 0; i < tokens.length; i++)
        KnowledgeToken(tokens[i], i, i + 1),
    ]);
    return matches.isEmpty;
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Từ dừng tiếng Anh, từ chỉ hoạt động học tập và từ dừng tiếng Việt (đã
  /// bỏ dấu). Chúng là ranh giới cắt cụm từ, không bao giờ nằm trong cụm.
  static final Set<String> _stopwords = {
    // Tiếng Anh chức năng
    'a', 'an', 'the', 'and', 'or', 'but', 'if', 'then', 'else', 'of', 'in',
    'on', 'at', 'to', 'for', 'from', 'by', 'with', 'without', 'about', 'into',
    'onto', 'over', 'under', 'between', 'through', 'during', 'before',
    'after', 'above', 'below', 'up', 'down', 'out', 'off', 'again',
    'further', 'once', 'here', 'there', 'when', 'where', 'why', 'how', 'all',
    'any', 'both', 'each', 'few', 'more', 'most', 'other', 'some', 'such',
    'no', 'nor', 'not', 'only', 'own', 'same', 'so', 'than', 'too', 'very',
    'can', 'will', 'just', 'should', 'now', 'is', 'are', 'was', 'were', 'be',
    'been', 'being', 'have', 'has', 'had', 'having', 'do', 'doe', 'did',
    'doing', 'i', 'me', 'my', 'we', 'our', 'you', 'your', 'he', 'she', 'it',
    'its', 'they', 'them', 'their', 'what', 'which', 'who', 'whom',
    'this', 'that', 'these', 'those', 'am', 'as', 'until', 'while', 'also',
    'etc', 'e.g', 'i.e', 'via', 'per', 'vs', 'like', 'well', 'able', 'must',
    'may', 'might', 'shall', 'would', 'could', 'upon', 'within', 'across',
    'toward', 'towards', 'among', 'along', 'against', 'whether', 'every',
    'many', 'much', 'one', 'two', 'three', 'first', 'second', 'third',
    'next', 'last', 'let', 'get', 'make', 'way', 'lot', 'yet', 'still',
    // Hoạt động học tập — nói về việc học chứ không phải nội dung học
    'student', 'course', 'chapter', 'session', 'lecture', 'lecturer', 'lab',
    'review', 'practice', 'practical', 'assignment', 'exercise', 'exam',
    'progress', 'final', 'midterm', 'quiz', 'week', 'module', 'part',
    'section', 'topic', 'introduction', 'intro', 'overview', 'summary',
    'basic', 'basics', 'fundamental', 'concept', 'knowledge', 'skill',
    'understand', 'understanding', 'describe', 'explain', 'discuss',
    'demonstrate', 'apply', 'applying', 'use', 'using', 'used',
    'learn', 'learning', 'learned', 'study', 'studying', 'know', 'identify',
    'define', 'list', 'present', 'perform', 'implement', 'implementing',
    'develop', 'developing', 'create', 'creating', 'build', 'building',
    'analyze', 'analyse', 'evaluate', 'compare', 'provide', 'include',
    'including', 'cover', 'focus', 'main', 'key', 'important', 'essential',
    'various', 'different', 'simple', 'new', 'common', 'general', 'specific',
    'related', 'relevant', 'level', 'example', 'case', 'detail', 'content',
    'material', 'activity', 'task', 'guide', 'guiding', 'guilding',
    'evaluation', 'assessment', 'assessing', 'cont', 'contd', 'cnt',
    'continue', 'continued', 'con\'t', 'finishing',
    'proficient', 'proficiency', 'ability', 'experience', 'good', 'effective',
    'effectively', 'advanced', 'overall', 'appropriate', 'certain',
    'mentor', 'orientation', 'preparation', 'mock', 'self', 'real', 'world',
    'abet', 'lo', 'clo', 'plo', 'test', 'workshop', 'classwork', 'project',
    'step', 'issue', 'problem', 'solution', 'field', 'area', 'subject',
    'teaching', 'method', 'assigning', 'assign', 'assigned', 'academic',
    'creative', 'instructor', 'teacher', 'guest', 'speaker', 'video',
    'slide', 'book', 'textbook', 'reference', 'grade', 'score', 'mark',
    'credit', 'hour', 'minute', 'semester', 'term', 'classroom', 'homework',
    'deadline', 'submission', 'feedback', 'home',
    // Động từ hành động trong CLO — nói cách học, không phải thứ được học
    'futher', 'explore', 'exploring', 'write', 'writing',
    'written', 'read', 'reading', 'choose', 'choosing', 'utilize',
    'utilizing', 'detect', 'designed', 'perceive', 'remove', 'allocate',
    'going', 'draw', 'install', 'required', 'require', 'complete',
    'completed', 'completing', 'completion', 'meaning', 'illustrate',
    'solve', 'solving', 'pas', 'pass', 'select', 'organize', 'manipulate',
    'find', 'calculate', 'compute', 'determine', 'check', 'construct',
    'verify', 'formulate', 'deliver', 'prepare', 'prepared', 'participate',
    'conduct', 'launch', 'exchange', 'optimize', 'integrate', 'enable',
    'add', 'enhance', 'enhancing', 'improve', 'improving', 'investigate',
    'communicate', 'given', 'based', 'need', 'want', 'help', 'try',
    'take', 'give', 'show', 'see', 'look', 'keep', 'making', 'done',
    'following', 'follow', 'contain', 'consist', 'involve', 'involving',
    'involved', 'allow', 'represent', 'recognize', 'distinguish',
    'classify', 'summarize', 'mastering', 'master', 'gain', 'gaining',
    'acquire', 'acquainted', 'practise', 'propose', 'ensure', 'achieve',
    'supporting', 'combine', 'combining', 'configure', 'configuring',
    'focuse', 'focused', 'understood', 'aware', 'become', 'provided',
    // Tính từ/trạng từ chung chung
    'independently', 'continuously', 'continuosly', 'clearly',
    'relatively', 'several', 'numerous', 'large', 'small', 'high', 'higher',
    'low', 'strong', 'useful', 'actual', 'possible', 'impossible', 'proper',
    'properly', 'diverse', 'suitable', 'serious', 'successful',
    'successfully', 'efficient', 'efficiently', 'reliable', 'specialized',
    'modern', 'central', 'core', 'underlying', 'original', 'already',
    'dynamically', 'right', 'unless', 'shoud', 'him', 'her', 'his',
    'mainly', 'especially', 'particular', 'particularly', 'typical',
    'typically', 'comprehensive', 'thorough', 'detailed', 'deep', 'deeper',
    'broad', 'wide', 'whole', 'entire', 'full', 'fully', 'better', 'best',
    'great', 'greater', 'quick', 'quickly', 'rapid', 'rapidly', 'easy',
    'easily', 'hard', 'difficult', 'multiple', 'individual', 'personal',
    'initial', 'later', 'early', 'current', 'latest', 'recent', 'major',
    'minor', 'total', 'wise', 'assistance', 'mooc', 'approach', 'blend',
    'considering', 'consider', 'differentiate', 'expect', 'learner',
    'respect', 'variety', 'surrounding', 'aspect', 'wrap', 'specialization',
    'inside', 'viewed', 'skip', 'lecturing', 'providing', 'combined',
    'capable', 'emphasize', 'emphasizing', 'today',
    // Tiếng Việt (đã bỏ dấu)
    'cac', 'cua', 'va', 'nhung', 'duoc', 'cho', 'trong', 'voi', 'mot', 'la',
    'co', 'de', 'khi', 've', 'tu', 'den', 'theo', 'nhu', 'cung', 'da', 'se',
    'dang', 'nay', 'tai', 'hoac', 'hay', 'thi', 'ma', 'neu', 'vi',
    'boi', 'sinh', 'vien', 'mon', 'hoc', 'kien', 'thuc', 'ky', 'nang',
    'hieu', 'biet', 'nam', 'vung', 'van', 'dung', 'hanh', 'giang', 'day',
    'bai', 'chuong', 'buoi', 'phan', 'gioi', 'thieu', 'muc', 'tieu', 'yeu',
    'cau', 'noi', 'ban', 'duoi', 'tren', 'ra', 'vao', 'nhat', 'nhieu',
    'moi', 'gi', 'nao', 'sao', 'ay', 'kia', 'rat', 'qua', 'lai', 'con',
    'chua', 'khong', 'thanh', 'viec', 'nguoi', 'kha',
    'tot', 'hon', 'tro', 'len', 'xuong', 'dong', 'thoi', 'cach', 'nhom',
  };

  /// Từ quá rộng để đứng một mình làm từ khoá ("data", "system"), dù vẫn
  /// đứng được trong một cụm dài hơn ("data link layer").
  static const Set<String> _genericSingles = {
    'data',
    'system',
    'software',
    'application',
    'computer',
    'information',
    'design',
    'development',
    'management',
    'process',
    'model',
    'technique',
    'method',
    'tool',
    'structure',
    'type',
    'operation',
    'function',
    'principle',
    'environment',
    'technology',
    'service',
    'program',
    'language',
    'component',
    'element',
    'feature',
    'object',
    'value',
    'user',
    'time',
    'performance',
    'quality',
    'business',
    'analysis',
    'work',
    'working',
    'group',
    'team',
    'class',
    'member',
    'result',
    'report',
    'product',
    'question',
    'answer',
    'form',
    'number',
    'role',
    'purpose',
    'goal',
    'context',
    'approach',
    'strategy',
    'practice',
    'framework',
    'standard',
    'plan',
    'planning',
    'implementation',
    'requirement',
    'specification',
    'phase',
    'flow',
    'screen',
    'page',
    'file',
    'text',
    'code',
    'support',
    'tip',
    'idea',
    'change',
    'people',
    'world',
    'understand',
    'basic',
    'online',
    'offline',
    'home',
    'kit',
    'demo',
  };
}

/// Một từ sau khi tách, kèm vị trí trong chuỗi đã chuẩn hoá.
class KnowledgeToken {
  final String text;
  final int start;
  final int end;

  const KnowledgeToken(this.text, this.start, this.end);

  @override
  String toString() => text;
}

class _Field {
  final String ref;
  final String text;
  final double weight;

  const _Field(this.ref, this.text, this.weight);
}

class _ConceptAcc {
  double score = 0;
  final List<ConceptEvidence> evidence = [];
}

class _PhraseAcc {
  double tf = 0;
  List<String> tokens = const [];
  String? surface;
}

class _Candidate {
  final String key;
  final List<String> tokens;
  final int start;
  final int end;

  const _Candidate(this.key, this.tokens, this.start, this.end);
}

class _Match {
  final String conceptId;
  final int start;
  final int end;

  const _Match(this.conceptId, this.start, this.end);
}

class _Pattern {
  final String conceptId;
  final List<String> tokens;

  /// Phần phải đứng ngay sau nhưng **không** bị nuốt — viết sau dấu `~`
  /// trong từ điển (`c ~programming`). Nhờ vậy "C programming" vừa tính cho
  /// "Ngôn ngữ C" vừa để "programming" tính tiếp cho "Lập trình".
  final List<String> lookahead;

  const _Pattern(this.conceptId, this.tokens, this.lookahead);

  int get span => tokens.length + lookahead.length;
}

/// So khớp từ điển theo lối **cụm dài nhất thắng**, quét trái sang phải.
class _ConceptMatcher {
  final Map<String, List<_Pattern>> _byFirst = {};

  _ConceptMatcher(List<ConceptDef> dictionary) {
    for (final def in dictionary) {
      for (final raw in def.patterns) {
        final cut = raw.indexOf('~');
        final head = cut < 0 ? raw : raw.substring(0, cut);
        final tail = cut < 0 ? '' : raw.substring(cut + 1);
        final tokens = _tokensOf(head);
        if (tokens.isEmpty) continue;
        final pattern = _Pattern(def.id, tokens, _tokensOf(tail));
        _byFirst.putIfAbsent(tokens.first, () => []).add(pattern);
      }
    }
    for (final list in _byFirst.values) {
      list.sort((a, b) => b.span.compareTo(a.span));
    }
  }

  static List<String> _tokensOf(String text) => [
    for (final t in KnowledgeExtractionService.tokenize(
      KnowledgeExtractionService.normalize(text),
    ))
      t.text,
  ];

  List<_Match> match(List<KnowledgeToken> tokens) {
    final out = <_Match>[];
    var i = 0;
    while (i < tokens.length) {
      final candidates = _byFirst[tokens[i].text];
      _Pattern? best;
      if (candidates != null) {
        for (final p in candidates) {
          if (i + p.span > tokens.length) continue;
          var ok = true;
          for (var k = 0; k < p.tokens.length && ok; k++) {
            ok = tokens[i + k].text == p.tokens[k];
          }
          for (var k = 0; k < p.lookahead.length && ok; k++) {
            ok = tokens[i + p.tokens.length + k].text == p.lookahead[k];
          }
          if (ok) {
            best = p;
            break;
          }
        }
      }
      if (best == null) {
        i++;
        continue;
      }
      out.add(
        _Match(
          best.conceptId,
          tokens[i].start,
          tokens[i + best.tokens.length - 1].end,
        ),
      );
      i += best.tokens.length;
    }
    return out;
  }
}
