/// Mô hình dữ liệu cho tầng **tri thức** — sâu hơn tầng môn học một cấp.
///
/// Đồ thị tiên quyết trả lời "môn nào học trước môn nào". Tầng này trả lời
/// câu hỏi khác: "kiến thức của môn này dính gì tới kiến thức của môn kia".
/// Nút ở đây là **khái niệm** (danh sách liên kết, đệ quy, SQL, MVC...) được
/// trích ra từ syllabus, và hai môn tương quan với nhau khi chúng cùng dạy
/// những khái niệm đó — kể cả khi giữa chúng không có cạnh tiên quyết nào.
///
/// Toàn bộ là dữ liệu thuần, không phụ thuộc Flutter hay SQLite, để chuyển
/// qua lại giữa các isolate và kiểm thử được bằng `flutter test`.
library;

/// Một đoạn văn bản trong syllabus kèm nhãn nguồn để dẫn chứng lại.
class KnowledgeText {
  /// Nhãn hiển thị: `CLO3`, `Buổi 12`, `Mô tả`...
  final String ref;
  final String text;

  const KnowledgeText(this.ref, this.text);
}

/// Nguyên liệu để trích tri thức của một môn: tên, mô tả, CLO và chủ đề từng
/// buổi học. Môn chưa nạp syllabus vẫn có tên và mô tả ngắn.
class KnowledgeSource {
  final String code;
  final String name;
  final int semester;
  final String description;
  final List<KnowledgeText> clos;
  final List<KnowledgeText> sessions;

  const KnowledgeSource({
    required this.code,
    required this.name,
    this.semester = 0,
    this.description = '',
    this.clos = const [],
    this.sessions = const [],
  });

  bool get hasSyllabus => clos.isNotEmpty || sessions.isNotEmpty;
}

/// Tám nhóm tri thức, cố định thứ tự vì thứ tự này quyết định màu: đổi chỗ
/// là đổi màu của cả một nhóm trên bản đồ.
class KnowledgeCategory {
  KnowledgeCategory._();

  static const String programming = 'Lập trình';
  static const String dsa = 'CTDL & giải thuật';
  static const String database = 'Cơ sở dữ liệu';
  static const String webMobile = 'Web & di động';
  static const String systems = 'Hệ thống & mạng';
  static const String softwareEngineering = 'Kỹ nghệ phần mềm';
  static const String math = 'Toán & dữ liệu';
  static const String society = 'Kỹ năng & xã hội';

  /// Cụm từ tự trích theo tần suất, không nằm trong từ điển.
  static const String extracted = 'Tự trích';

  static const List<String> ordered = [
    programming,
    dsa,
    database,
    webMobile,
    systems,
    softwareEngineering,
    math,
    society,
  ];

  /// Vị trí trong bảng màu phân loại, `-1` cho nhóm tự trích (tô xám).
  static int indexOf(String category) => ordered.indexOf(category);
}

/// Một khái niệm trong từ điển: tên hiển thị, nhóm, và các cách viết của nó
/// trong syllabus (tiếng Anh lẫn tiếng Việt).
class ConceptDef {
  final String id;
  final String label;
  final String category;
  final List<String> patterns;

  /// Kỹ năng chung xuất hiện ở hầu hết môn (làm việc nhóm, dùng công cụ AI).
  /// Vẫn được trích và hiển thị, nhưng không dùng để nối hai môn với nhau —
  /// nếu không, môn nào cũng "tương quan" với môn nào.
  final bool generic;

  const ConceptDef(
    this.id,
    this.label,
    this.category,
    this.patterns, {
    this.generic = false,
  });
}

/// Một chỗ trong syllabus nhắc tới khái niệm — bằng chứng để người đọc tự
/// kiểm tra thay vì phải tin thuật toán.
class ConceptEvidence {
  final String ref;
  final String snippet;

  const ConceptEvidence(this.ref, this.snippet);
}

/// Khái niệm [conceptId] xuất hiện trong một môn cụ thể.
class SubjectConcept {
  final String conceptId;

  /// Điểm thô: số lần xuất hiện nhân trọng số của từng phần (tên môn > CLO >
  /// mô tả > buổi học).
  final double score;

  /// `log(1 + score)` — nén lại để một môn nhắc 30 lần không lấn át hẳn môn
  /// nhắc 3 lần.
  final double weight;

  final List<ConceptEvidence> evidence;

  const SubjectConcept({
    required this.conceptId,
    required this.score,
    required this.weight,
    this.evidence = const [],
  });
}

/// Một khái niệm sau khi đã quét toàn bộ các môn.
class KnowledgeConcept {
  final String id;
  final String label;
  final String category;
  final bool generic;

  /// Không có trong từ điển, do thuật toán tự trích theo tần suất.
  final bool extracted;

  /// Mã môn -> mức độ môn đó dạy khái niệm này.
  final Map<String, SubjectConcept> bySubject;

  /// `ln(1 + N / df)`: khái niệm càng hiếm càng có giá trị nối hai môn.
  final double idf;

  const KnowledgeConcept({
    required this.id,
    required this.label,
    required this.category,
    this.generic = false,
    this.extracted = false,
    required this.bySubject,
    required this.idf,
  });

  int get subjectCount => bySubject.length;

  /// Có thể dùng để nối các môn với nhau.
  bool get linking => !generic && bySubject.length >= 2;
}

/// Cụm từ khoá đặc trưng của một môn (TF-IDF trên các cụm RAKE).
class KeywordScore {
  final String phrase;
  final double score;

  const KeywordScore(this.phrase, this.score);
}

/// Bức tranh tri thức của một môn.
class SubjectKnowledge {
  final String code;
  final String name;
  final int semester;
  final bool hasSyllabus;

  /// Khái niệm từ điển, xếp theo độ đậm giảm dần.
  final List<SubjectConcept> concepts;

  /// Cụm từ khoá đặc trưng tự trích, không trùng với khái niệm đã có.
  final List<KeywordScore> keywords;

  /// Độ "lập trình" của môn đọc từ syllabus (0..1). Cho phép nhận ra môn
  /// không mang mã lập trình nhưng vẫn dạy lập trình, như IoT hay HĐH.
  final double programmingScore;

  const SubjectKnowledge({
    required this.code,
    required this.name,
    required this.semester,
    required this.hasSyllabus,
    this.concepts = const [],
    this.keywords = const [],
    this.programmingScore = 0,
  });

  SubjectConcept? conceptOf(String conceptId) {
    for (final c in concepts) {
      if (c.conceptId == conceptId) return c;
    }
    return null;
  }
}

/// Hai môn tương quan về tri thức.
class KnowledgeLink {
  /// Môn học trước (kỳ nhỏ hơn); cùng kỳ thì xếp theo mã.
  final String from;
  final String to;

  /// Cosine giữa hai vector khái niệm (đã nhân IDF), 0..1.
  final double similarity;

  /// Tổng độ quan trọng của phần tri thức chung (không chuẩn hoá). Cosine
  /// cho hai môn chỉ chung đúng một khái niệm (Thể chất 1 ↔ Thể chất 2) điểm
  /// tuyệt đối; độ mạnh này mới đưa được những cặp chia sẻ **nhiều** tri
  /// thức như MAD101 ↔ CSD201 lên đầu.
  final double strength;

  /// Khái niệm chung, quan trọng nhất trước.
  final List<String> sharedConceptIds;

  /// Hai môn đã nối với nhau bằng một cạnh tiên quyết/tham khảo (chiều nào
  /// cũng được). `false` nghĩa là **tương quan ẩn**: tri thức dính nhau mà
  /// chương trình không nói ra.
  final bool hasDirectEdge;

  const KnowledgeLink({
    required this.from,
    required this.to,
    required this.similarity,
    this.strength = 0,
    required this.sharedConceptIds,
    required this.hasDirectEdge,
  });

  /// Tương quan ẩn đáng kể: chưa có quan hệ trên sơ đồ nhưng dùng chung từ
  /// hai khái niệm trở lên — một khái niệm trùng thì dễ chỉ là tình cờ.
  bool get isNotableHidden => !hasDirectEdge && sharedConceptIds.length >= 2;

  bool involves(String code) => from == code || to == code;

  String other(String code) => from == code ? to : from;
}

/// Kết quả trích tri thức cho toàn bộ CSDL.
class KnowledgeIndex {
  final Map<String, KnowledgeConcept> concepts;
  final Map<String, SubjectKnowledge> subjects;
  final List<KnowledgeLink> links;
  final Duration elapsed;

  const KnowledgeIndex({
    required this.concepts,
    required this.subjects,
    required this.links,
    this.elapsed = Duration.zero,
  });

  static const KnowledgeIndex empty = KnowledgeIndex(
    concepts: {},
    subjects: {},
    links: [],
  );

  bool get isEmpty => subjects.isEmpty;

  int get syllabusCount => subjects.values.where((s) => s.hasSyllabus).length;

  List<KnowledgeLink> linksOf(String code) =>
      links.where((l) => l.involves(code)).toList();

  KnowledgeLink? linkBetween(String a, String b) {
    for (final l in links) {
      if ((l.from == a && l.to == b) || (l.from == b && l.to == a)) return l;
    }
    return null;
  }
}
