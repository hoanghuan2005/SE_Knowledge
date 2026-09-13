/// Bóc tách Markdown do extension "Page to Markdown Note" sinh ra từ các trang
/// FAP/FLM.
///
/// Điểm mấu chốt: **turndown không sinh ra bảng Markdown**. Mọi ô trong bảng
/// HTML của FAP bị làm phẳng thành từng dòng riêng, và ô rỗng bị bỏ hẳn — không
/// để lại dòng trống nào. Nghĩa là số dòng mỗi hàng KHÔNG cố định (4 dòng nếu
/// môn không có tiên quyết, 5 dòng nếu có). Cắt theo cụm 5 dòng là hỏng toàn bộ
/// từ môn đầu tiên không có tiên quyết trở đi.
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

  /// Thông điệp cho người dùng khi [curriculum] là null.
  final String message;

  /// Chỉ khác null khi [kind] là [FapPageKind.curriculum] và bóc được dữ liệu.
  final FapCurriculumImport? curriculum;

  const FapParseResult({
    required this.kind,
    required this.message,
    this.curriculum,
  });

  bool get isSupported => curriculum != null;
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

  /// Phân tích toàn văn Markdown của một trang FAP.
  static FapParseResult parse(String markdown) {
    final lines = _significantLines(markdown);
    final sourceUrl = _findSourceUrl(lines);

    if (sourceUrl.contains('CurriculumDetails?curid=')) {
      return FapParseResult(
        kind: FapPageKind.curriculum,
        message: 'Trang Chương trình đào tạo (Curriculum Details).',
        curriculum: _parseCurriculum(lines, sourceUrl),
      );
    }

    // TODO(Giai đoạn 5.3): bóc trang Syllabus Details vào các bảng syllabi /
    // materials / learning_outcomes / sessions / assessments. Chưa làm lần này
    // nên báo rõ thay vì đoán bừa.
    if (sourceUrl.contains('SyllabusDetails?sylID=')) {
      return const FapParseResult(
        kind: FapPageKind.syllabus,
        message: 'Trang Syllabus chi tiết — chưa hỗ trợ nhập, sẽ làm ở bước sau.',
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
  // Tiện ích dùng chung
  // ------------------------------------------------------------------

  /// Các dòng đã trim, bỏ hết dòng trống — đúng dạng thuật toán neo cần.
  static List<String> _significantLines(String markdown) {
    return markdown
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
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

  /// Gỡ các ký tự turndown đã escape khi làm phẳng HTML.
  static String unescapeTurndown(String text) {
    return text
        .replaceAll(r'\_', '_')
        .replaceAll(r'\*', '*')
        .replaceAll(r'\+', '+')
        .replaceAll(r'\-', '-')
        .replaceAll(r'\.', '.')
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
