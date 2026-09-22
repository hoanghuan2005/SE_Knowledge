/// Bóc tách Markdown do extension "Page to Markdown Note" sinh ra từ các trang
/// FAP/FLM.
///
/// Điểm mấu chốt: **mọi thứ được quy về "mỗi ô một dòng"**. turndown trần làm
/// phẳng sẵn bảng HTML thành từng dòng riêng; bản turndown có plugin GFM thì
/// giữ bảng dạng `| ô | ô |` và [_significantLines] cắt nó ra thành đúng dạng
/// đó. Cả hai đường đều bỏ hẳn ô rỗng — không để lại dòng trống nào. Nghĩa là
/// số dòng mỗi hàng KHÔNG cố định (4 dòng nếu môn không có tiên quyết, 5 dòng
/// nếu có). Cắt theo cụm 5 dòng là hỏng toàn bộ từ môn đầu tiên không có tiên
/// quyết trở đi.
///
/// Vì vậy thuật toán ở đây **neo vào dòng link `Syllabuses?subCode=...`** —
/// mỗi dòng như vậy là ô "Subject Name" của đúng một hàng — rồi suy ra biên của
/// hàng từ vị trí anchor kế tiếp.
library;

/// Loại trang FAP nhận ra được từ dòng `Source:`.
enum FapPageKind {
  /// `CurriculumDetails?curid=...` — danh sách môn của cả một chương trình.
  curriculum,

  /// `SyllabusDetails?sylID=...` — chi tiết một môn. Chưa hỗ trợ nhập.
  syllabus,

  /// Không nhận ra.
  unknown,
}

/// Một dòng trong bảng môn học của trang Curriculum Details.
class FapSubjectRow {
  /// Mã môn, lấy từ query `subCode` của URL nên luôn sạch escape.
  final String code;

  final String nameEn;
  final String nameVn;

  /// Nguyên văn ô "PreRequisite". Rỗng nếu FAP để trống ô đó.
  final String rawPrerequisite;

  final int semester;
  final int credits;

  const FapSubjectRow({
    required this.code,
    required this.nameEn,
    required this.nameVn,
    required this.rawPrerequisite,
    required this.semester,
    required this.credits,
  });

  /// Tên hiển thị: ưu tiên tên tiếng Anh, không có thì dùng tên tiếng Việt.
  String get displayName => nameEn.isNotEmpty ? nameEn : nameVn;

  /// Tên đầy đủ cả hai ngôn ngữ, dùng khi ghi vào `subjects.name`.
  String get fullName =>
      nameVn.isEmpty ? nameEn : (nameEn.isEmpty ? nameVn : '${nameEn}_$nameVn');

  @override
  String toString() => 'FapSubjectRow($code, kỳ $semester, $credits tín chỉ)';
}

/// Một chuẩn đầu ra cấp chương trình (PLO1..PLOn).
class FapPloRow {
  final String code;
  final String description;

  const FapPloRow({required this.code, required this.description});

  @override
  String toString() => 'FapPloRow($code)';
}

/// Một tài liệu / giáo trình trong bảng Materials của Syllabus Details.
class FapMaterialRow {
  final int seqNo;
  final String description;
  final String author;
  final String publisher;
  final String publishedDate;
  final String edition;
  final String isbn;
  final bool isMain;
  final bool isHardCopy;
  final bool isOnline;
  final String note;

  const FapMaterialRow({
    required this.seqNo,
    required this.description,
    this.author = '',
    this.publisher = '',
    this.publishedDate = '',
    this.edition = '',
    this.isbn = '',
    this.isMain = false,
    this.isHardCopy = false,
    this.isOnline = false,
    this.note = '',
  });

  @override
  String toString() => 'FapMaterialRow(#$seqNo: $description)';
}

/// Một chuẩn đầu ra của môn học (CLO1..CLOn).
class FapCloRow {
  final String code;
  final String detail;

  const FapCloRow({required this.code, required this.detail});

  @override
  String toString() => 'FapCloRow($code)';
}

/// Một buổi học trong lịch trình (Schedule / Sessions).
class FapSessionRow {
  final int sessionNo;
  final String topic;
  final String teachingType;
  final String rawLo;
  final List<String> cloCodes;
  final String itu;
  final String studentMaterials;
  final String downloadUrl;
  final String studentTasks;
  final String urls;

  const FapSessionRow({
    required this.sessionNo,
    required this.topic,
    this.teachingType = '',
    this.rawLo = '',
    this.cloCodes = const [],
    this.itu = '',
    this.studentMaterials = '',
    this.downloadUrl = '',
    this.studentTasks = '',
    this.urls = '',
  });

  @override
  String toString() => 'FapSessionRow(Buổi $sessionNo: $topic)';
}

/// Một thành phần đánh giá điểm của môn học (Assessments).
class FapAssessmentRow {
  final int seqNo;
  final String category;
  final String type;
  final int? part;
  final double weightPercent;
  final String completionCriteria;
  final String duration;
  final String rawClo;
  final List<String> cloCodes;
  final String questionType;
  final int? noQuestion;
  final String knowledgeSkill;
  final String gradingGuide;
  final String note;

  const FapAssessmentRow({
    required this.seqNo,
    required this.category,
    this.type = '',
    this.part,
    required this.weightPercent,
    this.completionCriteria = '',
    this.duration = '',
    this.rawClo = '',
    this.cloCodes = const [],
    this.questionType = '',
    this.noQuestion,
    this.knowledgeSkill = '',
    this.gradingGuide = '',
    this.note = '',
  });

  @override
  String toString() => 'FapAssessmentRow($category: $weightPercent%)';
}

/// Toàn bộ dữ liệu bóc được từ một trang Syllabus Details.
class FapSyllabusImport {
  final int? fapSyllabusId;
  final String subjectCode;
  final String nameEn;
  final String nameNative;
  final String degreeLevel;
  final String learningTeachingMethod;
  final String timeAllocation;
  final String description;
  final String studentTasks;
  final String tools;
  final int? scoringScale;
  final String decisionNo;
  final String decisionDate;
  final bool isApproved;
  final bool isScored;
  final double? minAvgMarkToPass;
  final bool isActive;
  final String approvedDate;
  final String rawPrerequisiteText;
  final String sourceUrl;

  final List<FapMaterialRow> materials;
  final List<FapCloRow> clos;
  final List<FapSessionRow> sessions;
  final List<FapAssessmentRow> assessments;

  const FapSyllabusImport({
    required this.fapSyllabusId,
    required this.subjectCode,
    required this.nameEn,
    required this.nameNative,
    required this.degreeLevel,
    required this.learningTeachingMethod,
    required this.timeAllocation,
    required this.description,
    required this.studentTasks,
    required this.tools,
    required this.scoringScale,
    required this.decisionNo,
    required this.decisionDate,
    required this.isApproved,
    required this.isScored,
    required this.minAvgMarkToPass,
    required this.isActive,
    required this.approvedDate,
    required this.rawPrerequisiteText,
    required this.sourceUrl,
    required this.materials,
    required this.clos,
    required this.sessions,
    required this.assessments,
  });

  String get displayName => nameEn.isNotEmpty ? nameEn : nameNative;
  String get fullName => nameNative.isEmpty
      ? nameEn
      : (nameEn.isEmpty ? nameNative : '${nameEn}_$nameNative');
}

/// Toàn bộ dữ liệu bóc được từ một trang Curriculum Details.
class FapCurriculumImport {
  /// `curid` trên URL FAP — khoá tự nhiên để upsert. Null nếu không đọc được.
  final int? fapCurriculumId;

  final String code;
  final String name;
  final String decisionNo;
  final String sourceUrl;

  /// Tổng tín chỉ ghi trên trang (dòng "48 subjects, 145 credits").
  final int? totalCredits;

  final List<FapSubjectRow> subjects;
  final List<FapPloRow> plos;

  const FapCurriculumImport({
    required this.fapCurriculumId,
    required this.code,
    required this.name,
    required this.decisionNo,
    required this.sourceUrl,
    required this.totalCredits,
    required this.subjects,
    required this.plos,
  });

  /// Số môn ghi trên trang có thể lệch với số môn bóc được nếu trang bị cắt —
  /// dialog xem trước hiển thị cả hai để người dùng tự đối chiếu.
  int get subjectCount => subjects.length;
}

/// Kết quả phân tích một file Markdown bất kỳ từ extension.
class FapParseResult {
  final FapPageKind kind;

  /// Thông điệp cho người dùng khi không bóc được dữ liệu.
  final String message;

  /// Khác null khi [kind] là [FapPageKind.curriculum] và bóc được dữ liệu.
  final FapCurriculumImport? curriculum;

  /// Khác null khi [kind] là [FapPageKind.syllabus] và bóc được dữ liệu.
  final FapSyllabusImport? syllabus;

  const FapParseResult({
    required this.kind,
    required this.message,
    this.curriculum,
    this.syllabus,
  });

  bool get isSupported => curriculum != null || syllabus != null;
}

class FapMarkdownParser {
  FapMarkdownParser._();

  /// Dòng "Subject Name" của một hàng trong bảng môn. Phần host để tuỳ chọn vì
  /// FAP thường trả link tương đối nhưng không phải lúc nào cũng vậy.
  static final RegExp _subjectLink = RegExp(
    r'^\[(.+)\]\((?:https?://[^/]+)?/gui/role/student/Syllabuses'
    r'\?subCode=([^&]+)&curriculumID=(\d+)\)$',
  );

  static final RegExp _sourceLine = RegExp(r'^Source:\s*(\S+)');
  static final RegExp _curId = RegExp(r'[?&]curid=(\d+)', caseSensitive: false);
  static final RegExp _ploCode = RegExp(r'^PLO\s*\d+$', caseSensitive: false);
  static final RegExp _subjectsCredits = RegExp(
    r'(\d+)\s+subjects?\s*,\s*(\d+)\s+credits?',
    caseSensitive: false,
  );

  /// Mã khung CTĐT của một trang "Curriculum Details", `null` nếu file này
  /// không phải trang đó.
  ///
  /// Tách riêng khỏi [parse] vì luồng nạp Obsidian Vault chỉ cần đúng cái mã
  /// để đoán "lượt quét này thuộc khung nào" (BIT_SE_K19B...), không cần bóc
  /// cả bảng môn — bóc cả bảng cho từng file trong Vault thì quá tốn.
  static String? curriculumCodeOf(String markdown) {
    if (!markdown.contains('CurriculumCode')) return null;
    final lines = _significantLines(markdown);
    final sourceUrl = _findSourceUrl(lines);
    final isCurriculumPage = sourceUrl.contains('CurriculumDetails?curid=') ||
        lines.any((l) => l.startsWith('# Curriculum Details'));
    if (!isCurriculumPage) return null;

    final code = unescapeTurndown(_valueAfterLabel(lines, 'CurriculumCode:'))
        .trim()
        .toUpperCase();
    return code.isEmpty ? null : code;
  }

  /// File này có phải một trang FAP thô (Curriculum/Syllabus Details) không.
  ///
  /// Phép thử rẻ tiền bằng chuỗi con, dùng để luồng nạp Vault tách riêng nhóm
  /// file đó ra khỏi nhóm ghi chú môn học mà không phải [parse] từng file.
  static bool looksLikeFapPage(String markdown) {
    if (markdown.contains('SyllabusDetails?sylID=') ||
        markdown.contains('SyllabusDetails.aspx') ||
        markdown.contains('CurriculumDetails?curid=')) {
      return true;
    }
    return markdown.contains('# Syllabus Details') ||
        markdown.contains('# Curriculum Details');
  }

  /// Phân tích toàn văn Markdown của một trang FAP.
  static FapParseResult parse(String markdown) {
    final lines = _significantLines(markdown);
    final sourceUrl = _findSourceUrl(lines);

    if (sourceUrl.contains('CurriculumDetails?curid=') ||
        (sourceUrl.isEmpty && lines.any((l) => l.startsWith('# Curriculum Details')))) {
      return FapParseResult(
        kind: FapPageKind.curriculum,
        message: 'Trang Chương trình đào tạo (Curriculum Details).',
        curriculum: _parseCurriculum(lines, sourceUrl),
      );
    }

    if (sourceUrl.contains('SyllabusDetails?sylID=') ||
        sourceUrl.contains('SyllabusDetails.aspx') ||
        lines.any((l) => l.startsWith('# Syllabus Details'))) {
      final syllabus = _parseSyllabus(lines, sourceUrl);
      return FapParseResult(
        kind: FapPageKind.syllabus,
        message: 'Trang Đề cương môn học (Syllabus Details): ${syllabus.subjectCode}',
        syllabus: syllabus,
      );
    }

    return FapParseResult(
      kind: FapPageKind.unknown,
      message: sourceUrl.isEmpty
          ? 'Không nhận ra đây là trang FAP nào (file không có dòng "Source:").'
          : 'Không nhận ra đây là trang FAP nào: $sourceUrl',
    );
  }

  // ------------------------------------------------------------------
  // Curriculum Details
  // ------------------------------------------------------------------

  static FapCurriculumImport _parseCurriculum(
    List<String> lines,
    String sourceUrl,
  ) {
    final anchors = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (_subjectLink.hasMatch(lines[i])) anchors.add(i);
    }

    final subjects = <FapSubjectRow>[];
    for (var i = 0; i < anchors.length; i++) {
      final start = anchors[i];
      // Dòng ngay trước anchor kế tiếp là ô "Subject Code" của hàng SAU, nên
      // vùng dữ liệu của hàng này dừng trước nó một dòng nữa.
      final end = (i + 1 < anchors.length)
          ? anchors[i + 1] - 2
          : _lastRowEnd(lines, start);
      final row = _parseSubjectRow(lines, start, end);
      if (row != null) subjects.add(row);
    }

    return FapCurriculumImport(
      fapCurriculumId: int.tryParse(_curId.firstMatch(sourceUrl)?.group(1) ?? ''),
      code: unescapeTurndown(_valueAfterLabel(lines, 'CurriculumCode:')),
      name: unescapeTurndown(_valueAfterLabel(lines, 'Name:')),
      decisionNo: unescapeTurndown(_valueAfterLabel(lines, 'DecisionNo')),
      sourceUrl: sourceUrl,
      totalCredits: _totalCredits(lines),
      subjects: subjects,
      plos: _parsePlos(lines),
    );
  }

  /// Hàng cuối cùng không có anchor kế tiếp làm mốc, nên phải tự dừng lại:
  /// nhận tối đa Semester + NoCredit + PreRequisite, và chỉ nhận PreRequisite
  /// nếu dòng đó còn trông giống một ô dữ liệu chứ không phải nội dung trang.
  static int _lastRowEnd(List<String> lines, int start) {
    var end = start;
    for (var offset = 1; offset <= 2; offset++) {
      final i = start + offset;
      if (i >= lines.length || int.tryParse(lines[i]) == null) return end;
      end = i;
    }
    final prereq = start + 3;
    if (prereq < lines.length && _looksLikeCell(lines[prereq])) {
      end = prereq;
    }
    return end;
  }

  static bool _looksLikeCell(String line) {
    if (line.isEmpty || line.length > 400) return false;
    if (line.startsWith('#') || line.startsWith('[') || line.startsWith('|')) {
      return false;
    }
    return true;
  }

  static FapSubjectRow? _parseSubjectRow(List<String> lines, int start, int end) {
    final match = _subjectLink.firstMatch(lines[start]);
    if (match == null) return null;

    // Mã môn lấy từ URL chứ không lấy dòng đứng trước anchor: dòng đó đã bị
    // turndown escape (`PHE\_COM\*1`), còn query string thì sạch.
    final code = _decode(match.group(2)!);
    final name = unescapeTurndown(match.group(1)!);
    final split = _splitName(name);

    final semester = (start + 1 <= end) ? int.tryParse(lines[start + 1]) ?? 0 : 0;
    final credits = (start + 2 <= end) ? int.tryParse(lines[start + 2]) ?? 0 : 0;

    final prereqParts = <String>[];
    for (var i = start + 3; i <= end && i < lines.length; i++) {
      prereqParts.add(lines[i]);
    }

    return FapSubjectRow(
      code: code,
      nameEn: split.$1,
      nameVn: split.$2,
      rawPrerequisite: unescapeTurndown(prereqParts.join(' ')).trim(),
      semester: semester,
      credits: credits,
    );
  }

  /// Tên môn trên FAP có dạng `English Name_Tên tiếng Việt`. Tách tại dấu `_`
  /// ĐẦU TIÊN; không có `_` thì coi như chỉ có tên tiếng Anh.
  static (String, String) _splitName(String name) {
    final idx = name.indexOf('_');
    if (idx < 0) return (name.trim(), '');
    return (name.substring(0, idx).trim(), name.substring(idx + 1).trim());
  }

  static List<FapPloRow> _parsePlos(List<String> lines) {
    final plos = <FapPloRow>[];
    final seen = <String>{};
    for (var i = 0; i < lines.length - 1; i++) {
      if (!_ploCode.hasMatch(lines[i])) continue;
      final code = lines[i].replaceAll(RegExp(r'\s+'), '').toUpperCase();
      if (!seen.add(code)) continue;
      plos.add(
        FapPloRow(code: code, description: unescapeTurndown(lines[i + 1])),
      );
    }
    return plos;
  }

  static int? _totalCredits(List<String> lines) {
    for (final line in lines) {
      final m = _subjectsCredits.firstMatch(line);
      if (m != null) return int.tryParse(m.group(2)!);
    }
    return null;
  }

  // ------------------------------------------------------------------
  // Syllabus Details
  // ------------------------------------------------------------------

  static FapSyllabusImport _parseSyllabus(
    List<String> lines,
    String sourceUrl,
  ) {
    final sylIdMatch = RegExp(r'[?&]sylID=(\d+)', caseSensitive: false).firstMatch(sourceUrl);
    final fapSyllabusId = int.tryParse(sylIdMatch?.group(1) ?? '') ??
        int.tryParse(_valueAfterLabel(lines, 'Syllabus ID:'));

    final subjectCodeRaw = _valueAfterLabel(lines, 'Subject Code:');
    final subjectCode = subjectCodeRaw.replaceAll('*', '').trim().toUpperCase();

    final courseNameEnglish = _stripBold(unescapeTurndown(_valueAfterLabel(lines, 'Course Name English:')));
    final courseNameNative = _stripBold(unescapeTurndown(_valueAfterLabel(lines, 'Course Name Native:')));
    final syllabusName = _stripBold(unescapeTurndown(_valueAfterLabel(lines, 'Syllabus Name:')));

    String nameEn = courseNameEnglish;
    String nameNative = courseNameNative;
    if (nameNative.isEmpty && syllabusName.isNotEmpty) {
      final split = _splitName(syllabusName);
      if (nameEn.isEmpty) nameEn = split.$1;
      if (split.$2.isNotEmpty) nameNative = split.$2;
    } else if (nameEn.isEmpty && syllabusName.isNotEmpty) {
      final split = _splitName(syllabusName);
      nameEn = split.$1;
      if (nameNative.isEmpty) nameNative = split.$2;
    }

    final decisionRaw = unescapeTurndown(_valueAfterLabel(lines, 'DecisionNo'));
    final decisionDateMatch = RegExp(r'dated\s+(\d{1,2}/\d{1,2}/\d{4})', caseSensitive: false).firstMatch(decisionRaw);
    final approvedDate = unescapeTurndown(_valueAfterLabel(lines, 'ApprovedDate:'));
    final decisionDate = decisionDateMatch?.group(1) ?? approvedDate;

    return FapSyllabusImport(
      fapSyllabusId: fapSyllabusId,
      subjectCode: subjectCode,
      nameEn: nameEn,
      nameNative: nameNative,
      degreeLevel: unescapeTurndown(_valueAfterLabel(lines, 'Degree Level:')),
      learningTeachingMethod: unescapeTurndown(_valueAfterLabel(lines, 'Learning-Teaching Method:')),
      timeAllocation: unescapeTurndown(_valueAfterLabel(lines, 'Time Allocation:')),
      description: unescapeTurndown(_valueBetween(lines, 'Description:', ['StudentTasks:', "Student's Tasks:", 'Tools:', 'Scoring Scale:'])),
      studentTasks: unescapeTurndown(_valueBetween(lines, 'StudentTasks:', ['Tools:', 'Scoring Scale:'])),
      tools: unescapeTurndown(_valueAfterLabel(lines, 'Tools:')),
      scoringScale: int.tryParse(_valueAfterLabel(lines, 'Scoring Scale:')),
      decisionNo: decisionRaw,
      decisionDate: decisionDate,
      isApproved: _valueAfterLabel(lines, 'IsApproved:').toLowerCase().contains('true'),
      isScored: _valueAfterLabel(lines, 'Is Scored:').isNotEmpty
          ? _valueAfterLabel(lines, 'Is Scored:').toLowerCase().contains('true')
          : true,
      minAvgMarkToPass: double.tryParse(_valueAfterLabel(lines, 'MinAvgMarkToPass:')),
      isActive: _valueAfterLabel(lines, 'IsActive:').toLowerCase().contains('true'),
      approvedDate: approvedDate,
      rawPrerequisiteText: unescapeTurndown(_prerequisiteFromLines(lines)),
      sourceUrl: sourceUrl,
      materials: _parseMaterials(lines),
      clos: _parseClos(lines),
      sessions: _parseSessions(lines),
      assessments: _parseAssessments(lines),
    );
  }

  static String _prerequisiteFromLines(List<String> lines) {
    for (final label in ['Pre-Requisite:', 'PreRequisite:', 'Prerequisite:']) {
      final val = _valueAfterLabel(lines, label);
      if (val.isNotEmpty) {
        final clean = unescapeTurndown(val).trim();
        if (clean.endsWith(':') ||
            clean.toLowerCase().startsWith('description') ||
            clean.toLowerCase().startsWith('learning') ||
            clean.toLowerCase().startsWith('tools') ||
            clean.toLowerCase() == 'none' ||
            clean.toLowerCase() == 'không' ||
            clean.toLowerCase() == 'khong' ||
            clean.toLowerCase() == 'n/a') {
          return '';
        }
        return val;
      }
    }
    return '';
  }

  /// Bóc tách danh sách mã môn tiên quyết từ chuỗi thô.
  /// Hỗ trợ định dạng đơn ("PRO192"), danh sách ("MLN111, MLN122"), hoặc lựa chọn ("MAE101 or MAC101").
  static List<String> extractPrerequisiteCodes(String rawText) {
    if (rawText.trim().isEmpty) return const [];
    final upper = rawText.toUpperCase();
    if (upper == 'NONE' || upper == 'KHÔNG' || upper == 'KHONG' || upper == 'N/A') {
      return const [];
    }
    final regex = RegExp(r'\b([A-Za-z]{2,4}\d{2,4}[A-Za-z]?)\b');
    final matches = regex.allMatches(rawText);
    final codes = <String>{};
    for (final m in matches) {
      final code = m.group(1)?.trim();
      if (code != null && code.isNotEmpty) {
        codes.add(code.toUpperCase());
      }
    }
    return codes.toList();
  }


  static String _valueBetween(List<String> lines, String startLabel, List<String> stopLabels) {
    final startNeedle = startLabel.toLowerCase();
    var startIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].toLowerCase().startsWith(startNeedle)) {
        startIndex = i;
        break;
      }
    }
    if (startIndex == -1) return '';

    final parts = <String>[];
    final colon = lines[startIndex].indexOf(':');
    if (colon >= 0 && colon + 1 < lines[startIndex].length) {
      final inline = lines[startIndex].substring(colon + 1).trim();
      if (inline.isNotEmpty) parts.add(inline);
    }

    for (var i = startIndex + 1; i < lines.length; i++) {
      final line = lines[i];
      final isStop = stopLabels.any((s) => line.toLowerCase().startsWith(s.toLowerCase()));
      if (isStop) break;
      if (line.startsWith('#') || line.contains('material(s)') || line.contains('LO(s)')) break;
      parts.add(line);
    }
    return parts.join('\n').trim();
  }

  static List<String> _extractCloCodes(String raw) {
    if (raw.isEmpty) return const [];
    final codes = <String>{};

    final rangeRegex = RegExp(r'(?:C?LO)?(\d+)\s*[-–—]\s*(?:C?L?O)?(\d+)', caseSensitive: false);
    for (final m in rangeRegex.allMatches(raw)) {
      final start = int.tryParse(m.group(1) ?? '');
      final end = int.tryParse(m.group(2) ?? '');
      if (start != null && end != null && start <= end && end - start <= 50) {
        for (var i = start; i <= end; i++) {
          codes.add('CLO$i');
        }
      }
    }

    final singleRegex = RegExp(r'\b(?:C?LO)\s*(\d+)\b', caseSensitive: false);
    for (final m in singleRegex.allMatches(raw)) {
      final num = m.group(1);
      if (num != null) codes.add('CLO$num');
    }

    return codes.toList()..sort((a, b) {
      final numA = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final numB = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
      return numA.compareTo(numB);
    });
  }

  static List<FapMaterialRow> _parseMaterials(List<String> lines) {
    final matHeaderIdx = lines.indexWhere(
      (l) => RegExp(r'^\d+\s+material\(s\)', caseSensitive: false).hasMatch(l),
    );
    if (matHeaderIdx == -1) return const [];

    final tableEndIdx = lines.indexWhere(
      (l) => RegExp(r'^\d+\s+(?:LO|learning outcome)\(s\)', caseSensitive: false).hasMatch(l) ||
             l.startsWith('[View mapping') ||
             l.contains('Download All Student Material'),
      matHeaderIdx + 1,
    );
    final end = tableEndIdx == -1 ? lines.length : tableEndIdx;

    final rowStarts = <(int rowNum, int lineIdx)>[];
    var expectedNum = 1;
    var seenBools = true;
    for (var i = matHeaderIdx + 1; i < end; i++) {
      final line = lines[i];
      if (seenBools && line == expectedNum.toString()) {
        rowStarts.add((expectedNum, i));
        expectedNum++;
        seenBools = false;
      } else {
        final clean = line.toLowerCase().replaceAll('*', '');
        if (clean == 'true' || clean == 'false') {
          seenBools = true;
        }
      }
    }

    final materials = <FapMaterialRow>[];
    for (var r = 0; r < rowStarts.length; r++) {
      final seqNo = rowStarts[r].$1;
      final start = rowStarts[r].$2;
      final rowEnd = (r + 1 < rowStarts.length) ? rowStarts[r + 1].$2 : end;

      final rowLines = lines.sublist(start + 1, rowEnd);
      if (rowLines.isEmpty) continue;

      final description = unescapeTurndown(rowLines[0]);
      final boolIdxs = <int>[];
      for (var b = 1; b < rowLines.length; b++) {
        final val = rowLines[b].toLowerCase().replaceAll('*', '');
        if (val == 'true' || val == 'false') {
          boolIdxs.add(b);
        }
      }

      bool isMain = false;
      bool isHardCopy = false;
      bool isOnline = false;
      String author = '';
      String publisher = '';
      String publishedDate = '';
      String edition = '';
      String isbn = '';
      String note = '';

      if (boolIdxs.length >= 3) {
        isMain = rowLines[boolIdxs[0]].toLowerCase().contains('true');
        isHardCopy = rowLines[boolIdxs[1]].toLowerCase().contains('true');
        isOnline = rowLines[boolIdxs[2]].toLowerCase().contains('true');

        final preBools = rowLines.sublist(1, boolIdxs[0]);
        if (preBools.isNotEmpty) author = unescapeTurndown(preBools[0]);
        if (preBools.length > 1) publisher = unescapeTurndown(preBools[1]);
        if (preBools.length > 2) publishedDate = unescapeTurndown(preBools[2]);
        if (preBools.length > 3) edition = unescapeTurndown(preBools[3]);
        if (preBools.length > 4) isbn = unescapeTurndown(preBools[4]);

        final postBools = rowLines.sublist(boolIdxs[2] + 1);
        if (postBools.isNotEmpty) {
          note = unescapeTurndown(postBools.join(' '));
        }
      } else if (rowLines.length > 1) {
        note = unescapeTurndown(rowLines.sublist(1).join(' '));
      }

      materials.add(FapMaterialRow(
        seqNo: seqNo,
        description: description,
        author: author,
        publisher: publisher,
        publishedDate: publishedDate,
        edition: edition,
        isbn: isbn,
        isMain: isMain,
        isHardCopy: isHardCopy,
        isOnline: isOnline,
        note: note,
      ));
    }

    return materials;
  }

  static List<FapCloRow> _parseClos(List<String> lines) {
    final loHeaderIdx = lines.indexWhere(
      (l) => RegExp(r'^\d+\s+(?:LO|learning outcome)\(s\)', caseSensitive: false).hasMatch(l),
    );
    if (loHeaderIdx == -1) return const [];

    final tableEndIdx = lines.indexWhere(
      (l) => l.startsWith('[View mapping') ||
             l.contains('Download All Student Material') ||
             l == 'Session',
      loHeaderIdx + 1,
    );
    final end = tableEndIdx == -1 ? lines.length : tableEndIdx;

    final cloAnchors = <(String code, int lineIdx)>[];
    final cloRegex = RegExp(r'^(?:CLO|LO)\s*(\d+)$', caseSensitive: false);
    for (var i = loHeaderIdx + 1; i < end; i++) {
      final m = cloRegex.firstMatch(lines[i]);
      if (m != null) {
        cloAnchors.add(('CLO${m.group(1)}', i));
      }
    }

    final clos = <FapCloRow>[];
    for (var i = 0; i < cloAnchors.length; i++) {
      final code = cloAnchors[i].$1;
      final start = cloAnchors[i].$2;
      final rowEnd = (i + 1 < cloAnchors.length) ? cloAnchors[i + 1].$2 : end;

      final detailLines = <String>[];
      for (var j = start + 1; j < rowEnd; j++) {
        final line = lines[j];
        if (int.tryParse(line) != null && (i + 2 < cloAnchors.length || j == rowEnd - 1)) {
          continue;
        }
        detailLines.add(line);
      }

      clos.add(FapCloRow(
        code: code,
        detail: unescapeTurndown(detailLines.join('\n')).trim(),
      ));
    }

    return clos;
  }

  static List<FapSessionRow> _parseSessions(List<String> lines) {
    final schedHeaderIdx = lines.indexWhere(
      (l) => l.contains('Download All Student Material') ||
             (l == 'Session' && lines.contains('Learning-Teaching Type')),
    );
    if (schedHeaderIdx == -1) return const [];

    final tableEndIdx = lines.indexWhere(
      (l) => RegExp(r'^\d+\s+(?:assessment|constructive question)\(s\)', caseSensitive: false).hasMatch(l) ||
             (l == 'No.' && lines.skip(schedHeaderIdx + 1).take(50).contains('Session No')),
      schedHeaderIdx + 1,
    );
    final end = tableEndIdx == -1 ? lines.length : tableEndIdx;

    final sessionStarts = <(int sessNo, int lineIdx)>[];
    var expectedSess = 1;
    for (var i = schedHeaderIdx + 1; i < end; i++) {
      if (lines[i] == expectedSess.toString()) {
        sessionStarts.add((expectedSess, i));
        expectedSess++;
      }
    }

    final sessions = <FapSessionRow>[];
    for (var s = 0; s < sessionStarts.length; s++) {
      final sessNo = sessionStarts[s].$1;
      final start = sessionStarts[s].$2;
      final rowEnd = (s + 1 < sessionStarts.length) ? sessionStarts[s + 1].$2 : end;

      final rowLines = lines.sublist(start + 1, rowEnd);
      if (rowLines.isEmpty) continue;

      final topic = unescapeTurndown(rowLines[0]);
      String teachingType = '';
      String rawLo = '';
      String itu = '';
      String downloadUrl = '';
      final materialsList = <String>[];
      final tasksList = <String>[];
      final urlsList = <String>[];

      for (var i = 1; i < rowLines.length; i++) {
        final line = rowLines[i];
        final lower = line.toLowerCase();

        if (teachingType.isEmpty && (lower == 'offline' || lower == 'online' || lower.contains('in-class'))) {
          teachingType = line;
          continue;
        }

        if (rawLo.isEmpty && RegExp(r'\b(?:C?LO)\s*\d+', caseSensitive: false).hasMatch(line)) {
          rawLo = line;
          continue;
        }

        if (itu.isEmpty && RegExp(r'^(?:I|T|U|IT|TU|ITU|I/T/U)$', caseSensitive: false).hasMatch(line)) {
          itu = line;
          continue;
        }

        if (line.contains('/download/') || line.contains('drive.google.com') || (line.startsWith('[') && line.contains('http'))) {
          downloadUrl = line;
          continue;
        }

        if (line.startsWith('http://') || line.startsWith('https://')) {
          urlsList.add(line);
          continue;
        }

        if (lower.contains('task') || lower.contains('exercise') || lower.contains('assignment') || lower.contains('nhiệm vụ') || lower.contains('bài tập')) {
          tasksList.add(line);
        } else {
          materialsList.add(line);
        }
      }

      sessions.add(FapSessionRow(
        sessionNo: sessNo,
        topic: topic,
        teachingType: teachingType,
        rawLo: rawLo,
        cloCodes: _extractCloCodes(rawLo),
        itu: itu,
        studentMaterials: unescapeTurndown(materialsList.join('\n')),
        downloadUrl: downloadUrl,
        studentTasks: unescapeTurndown(tasksList.join('\n')),
        urls: urlsList.join('\n'),
      ));
    }

    return sessions;
  }

  static List<FapAssessmentRow> _parseAssessments(List<String> lines) {
    final astHeaderIdx = lines.indexWhere(
      (l) => RegExp(r'^\d+\s+assessment\(s\)', caseSensitive: false).hasMatch(l),
    );
    if (astHeaderIdx == -1) return const [];

    final tableEndIdx = lines.indexWhere(
      (l) => l.startsWith(r'$(') || l.startsWith('<script') || l.startsWith('function '),
      astHeaderIdx + 1,
    );
    final end = tableEndIdx == -1 ? lines.length : tableEndIdx;

    final astStarts = <(int astNo, int lineIdx)>[];
    var expectedNo = 1;
    var seenWeight = true;
    for (var i = astHeaderIdx + 1; i < end; i++) {
      final line = lines[i];
      if (seenWeight && line == expectedNo.toString()) {
        astStarts.add((expectedNo, i));
        expectedNo++;
        seenWeight = false;
      } else if (RegExp(r'^\d+(?:\.\d+)?\s*%$').hasMatch(line)) {
        seenWeight = true;
      }
    }

    final assessments = <FapAssessmentRow>[];
    for (var a = 0; a < astStarts.length; a++) {
      final seqNo = astStarts[a].$1;
      final start = astStarts[a].$2;
      final rowEnd = (a + 1 < astStarts.length) ? astStarts[a + 1].$2 : end;

      final rowLines = lines.sublist(start + 1, rowEnd);
      if (rowLines.isEmpty) continue;

      final weightIdx = rowLines.indexWhere(
        (l) => RegExp(r'^(\d+(?:\.\d+)?)\s*%$').hasMatch(l),
      );

      double weight = 0.0;
      int? part;
      String type = '';
      String category = '';

      if (weightIdx != -1) {
        final match = RegExp(r'^(\d+(?:\.\d+)?)\s*%$').firstMatch(rowLines[weightIdx]);
        weight = double.tryParse(match?.group(1) ?? '') ?? 0.0;

        if (weightIdx > 0 && int.tryParse(rowLines[weightIdx - 1]) != null) {
          part = int.tryParse(rowLines[weightIdx - 1]);
          if (weightIdx > 1) {
            type = unescapeTurndown(rowLines[weightIdx - 2]);
            category = unescapeTurndown(rowLines.sublist(0, weightIdx - 2).join(' '));
          } else {
            category = unescapeTurndown(rowLines[0]);
          }
        } else if (weightIdx > 0) {
          type = unescapeTurndown(rowLines[weightIdx - 1]);
          category = unescapeTurndown(rowLines.sublist(0, weightIdx - 1).join(' '));
        }
      } else {
        category = unescapeTurndown(rowLines[0]);
      }

      if (category.isEmpty && rowLines.isNotEmpty) {
        category = unescapeTurndown(rowLines[0]);
      }

      String completionCriteria = '';
      String duration = '';
      String rawClo = '';
      String questionType = '';
      int? noQuestion;
      String knowledgeSkill = '';
      String gradingGuide = '';
      final noteParts = <String>[];

      final postWeight = (weightIdx != -1 && weightIdx + 1 < rowLines.length)
          ? rowLines.sublist(weightIdx + 1)
          : (rowLines.length > 2 ? rowLines.sublist(2) : <String>[]);

      for (var i = 0; i < postWeight.length; i++) {
        final line = postWeight[i];
        if (completionCriteria.isEmpty && (line.contains('>0') || line.contains(r'\>0') || line.toLowerCase() == 'none')) {
          completionCriteria = unescapeTurndown(line);
          continue;
        }

        if (rawClo.isEmpty && RegExp(r'\b(?:C?LO)\s*\d+', caseSensitive: false).hasMatch(line)) {
          rawClo = line;
          continue;
        }

        if (duration.isEmpty && (RegExp(r"^\d+'$").hasMatch(line) || line.toLowerCase().contains('minutes') || line.startsWith('Option 1:'))) {
          duration = line;
          continue;
        }

        if (noQuestion == null && int.tryParse(line) != null && int.parse(line) <= 200) {
          noQuestion = int.tryParse(line);
          continue;
        }

        noteParts.add(line);
      }

      assessments.add(FapAssessmentRow(
        seqNo: seqNo,
        category: category,
        type: type,
        part: part,
        weightPercent: weight,
        completionCriteria: completionCriteria,
        duration: duration,
        rawClo: rawClo,
        cloCodes: _extractCloCodes(rawClo),
        questionType: questionType,
        noQuestion: noQuestion,
        knowledgeSkill: knowledgeSkill,
        gradingGuide: gradingGuide,
        note: unescapeTurndown(noteParts.join('\n')),
      ));
    }

    return assessments;
  }

  // ------------------------------------------------------------------
  // Tiện ích dùng chung
  // ------------------------------------------------------------------

  /// Các dòng đã trim, bỏ hết dòng trống — đúng dạng thuật toán neo cần.
  ///
  /// Có hai đời extension sinh ra hai dạng Markdown khác nhau cho cùng một
  /// trang FAP:
  ///  - turndown "trần": bảng HTML bị làm phẳng sẵn, mỗi ô một dòng;
  ///  - turndown + plugin GFM: bảng giữ nguyên dạng `| ô | ô |`.
  ///
  /// Hàm này kéo dạng thứ hai về dạng thứ nhất — mỗi ô thành một dòng, hàng
  /// gạch ngăn bị bỏ — để toàn bộ phần còn lại của parser không phải biết bảng
  /// là gì. Ô rỗng vẫn bị bỏ hẳn, đúng như turndown trần vẫn làm.
  static List<String> _significantLines(String markdown) {
    final out = <String>[];
    for (final raw in markdown.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (!_isTableRow(line)) {
        out.add(line);
        continue;
      }
      if (_isTableSeparatorRow(line)) continue;
      out.addAll(_tableCells(line));
    }
    return out;
  }

  /// Dấu `|` không bị escape — biên giữa hai ô của một hàng bảng GFM.
  static final RegExp _cellSplitter = RegExp(r'(?<!\\)\|');

  /// Ô bảng của FAP hay chứa `<br>` thay cho xuống dòng (Tools, StudentTasks...).
  static final RegExp _brTag = RegExp(r'<br\s*/?>', caseSensitive: false);

  /// Hàng gạch ngăn header: `| --- | :--- |`.
  static final RegExp _separatorCell = RegExp(r'^:?-{1,}:?$');

  static bool _isTableRow(String line) => line.length > 1 && line.startsWith('|');

  static bool _isTableSeparatorRow(String line) {
    final cells = _splitRow(line);
    if (cells.isEmpty) return false;
    return cells.every((c) => _separatorCell.hasMatch(c.trim()));
  }

  /// Nội dung từng ô của một hàng, đã gỡ `<br>` thành dòng riêng và bỏ ô rỗng.
  static List<String> _tableCells(String line) {
    final cells = <String>[];
    for (final rawCell in _splitRow(line)) {
      final cell = rawCell.replaceAll(r'\|', '|').replaceAll(_brTag, '\n');
      for (final piece in cell.split('\n')) {
        final trimmed = piece.trim();
        if (trimmed.isNotEmpty) cells.add(trimmed);
      }
    }
    return cells;
  }

  /// Cắt một hàng thành các ô thô: bỏ `|` mở/đóng rồi tách theo `|` chưa escape.
  static List<String> _splitRow(String line) {
    var body = line.substring(1);
    if (body.endsWith('|') && !body.endsWith(r'\|')) {
      body = body.substring(0, body.length - 1);
    }
    return body.split(_cellSplitter);
  }

  static String _findSourceUrl(List<String> lines) {
    for (final line in lines) {
      final m = _sourceLine.firstMatch(line);
      if (m != null) return m.group(1)!;
    }
    return '';
  }

  /// Lấy giá trị đi kèm một nhãn: ưu tiên phần nằm ngay sau dấu hai chấm trên
  /// cùng dòng, không có thì lấy trọn dòng kế tiếp.
  static String _valueAfterLabel(List<String> lines, String label) {
    final needle = label.toLowerCase();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.toLowerCase().startsWith(needle)) continue;
      final colon = line.indexOf(':');
      if (colon >= 0 && colon + 1 < line.length) {
        final inline = line.substring(colon + 1).trim();
        if (inline.isNotEmpty) return inline;
      }
      if (i + 1 < lines.length) return lines[i + 1];
      return '';
    }
    return '';
  }

  /// FLM in đậm vài ô của bảng đầu trang (`**PRO192c**`). Dấu `**` là trang
  /// trí chứ không phải dữ liệu, để nguyên thì nó chui thẳng vào tên môn.
  static String _stripBold(String text) {
    final t = text.trim();
    if (t.length > 4 && t.startsWith('**') && t.endsWith('**')) {
      return t.substring(2, t.length - 2).trim();
    }
    return t;
  }

  /// Gỡ các ký tự turndown đã escape khi làm phẳng HTML.
  static String unescapeTurndown(String text) {
    return text
        .replaceAll(r'\_', '_')
        .replaceAll(r'\*', '*')
        .replaceAll(r'\+', '+')
        .replaceAll(r'\-', '-')
        .replaceAll(r'\.', '.')
        .replaceAll(r'\>', '>')
        .replaceAll(r'\<', '<')
        .replaceAll(r'\\', r'\');
  }

  /// `PHE_COM%2A1` -> `PHE_COM*1`. Mã lạ không decode được thì giữ nguyên.
  static String _decode(String raw) {
    try {
      return Uri.decodeComponent(raw).trim();
    } on FormatException {
      return raw.trim();
    }
  }
}
