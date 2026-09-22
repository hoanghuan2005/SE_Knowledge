/// Một dòng trong bảng điểm cá nhân (bảng `transcript_entries`).
///
/// Cố ý tách khỏi `Subject`: `subjects` là **danh mục** môn của đồ thị tri
/// thức, còn bảng điểm là **lịch sử học** của một sinh viên. Một môn học lại
/// hai lần sinh ra hai dòng ở đây nhưng vẫn chỉ có một node trên đồ thị, và
/// transcript FAP còn chứa cả những môn không nằm trong khung ngành (Vovinam,
/// tiếng Nhật, tiếng Anh dự bị) — chúng không được phép chui vào đồ thị.
library;

/// Trạng thái một môn trong bảng điểm FAP.
enum SubjectStatus {
  /// `Passed` — đã qua môn.
  passed,

  /// `Not Passed` / `Failed` — đã học nhưng trượt, phải học lại.
  notPassed,

  /// `Studying` — đang học trong kỳ hiện tại, chưa có điểm.
  studying,

  /// `Not started` — nằm trong khung nhưng chưa tới lượt học.
  notStarted,

  /// Chuỗi trạng thái FAP không nhận ra được. Giữ riêng thay vì đoán bừa, để
  /// dòng đó không lặng lẽ bị tính vào GPA.
  unknown,
}

/// Ba kỳ trong một năm học của FPTU.
enum Season { spring, summer, fall }

/// Thứ tự thời gian trong cùng một năm: Spring < Summer < Fall.
extension SeasonRank on Season {
  int get rank => switch (this) {
    Season.spring => 1,
    Season.summer => 2,
    Season.fall => 3,
  };

  /// Nhãn đúng như FAP ghi, để dựng lại chuỗi `Fall2023`.
  String get label => switch (this) {
    Season.spring => 'Spring',
    Season.summer => 'Summer',
    Season.fall => 'Fall',
  };

  String get labelVi => switch (this) {
    Season.spring => 'Xuân',
    Season.summer => 'Hè',
    Season.fall => 'Thu',
  };
}

class TranscriptEntry {
  final int? id;

  /// `subjects.id` khớp được theo mã môn. NULL khi môn chưa có trong đồ thị
  /// (môn ngoài khung ngành), hoặc khi môn đó vừa bị xoá khỏi đồ thị — khoá
  /// ngoại dùng `ON DELETE SET NULL` nên điểm không mất theo.
  final int? subjectId;

  /// Luôn viết hoa. Transcript ghi `SSL101c`, CSDL lưu `SSL101C`; không chuẩn
  /// hoá ở đây thì mọi môn có hậu tố chữ thường sẽ không khớp được môn nào.
  final String subjectCode;

  final String subjectName;

  /// Cột `Term` của FAP — kỳ **trong khung chương trình** (0–9), không phải kỳ
  /// thực tế đã học. Bảng môn tiếng Anh dự bị không có cột này nên để null.
  final int? term;

  /// Kỳ thực tế, nguyên văn: `Fall2023`. Rỗng khi môn chưa học.
  final String semesterLabel;

  final int? semesterYear;
  final Season? season;

  /// `year * 10 + season.rank`, `0` khi chưa học. Có sẵn khoá số này thì mọi
  /// chỗ cần sắp xếp theo thời gian chỉ so sánh một số nguyên, khỏi bóc lại
  /// chuỗi `Fall2023` mỗi lần.
  final int semesterOrder;

  final int credits;

  /// Thang 10. Null khi chưa có điểm (đang học, hoặc môn `Passed` không chấm
  /// điểm như TRS601).
  final double? grade;

  final SubjectStatus status;

  /// Cờ `*` màu đỏ ở cột cuối: môn điều kiện tốt nghiệp, **không** tính vào
  /// điểm trung bình tích luỹ.
  final bool isGraduationCondition;

  /// Dòng này có được cộng vào GPA không. Suy ra lúc nhập bằng
  /// [countsTowardGpaByDefault], nhưng người dùng sửa tay được: FAP thỉnh
  /// thoảng đánh cờ khác với quy chế thực tế của từng khoá.
  final bool countsTowardGpa;

  /// Nguyên văn cột `prerequisite` của FAP, **chỉ để hiển thị**. Cú pháp của
  /// FAP trộn `&`, `/` và `or` (`LAB211&SWE201c/SWE202c&PRJ301/PRJ302`), bóc
  /// sai một dấu là đồ thị có cạnh ma — việc dựng cạnh đã có
  /// `syncPrerequisitesFromFap()` lo, transcript không đụng vào.
  final String rawPrerequisite;

  final String replacedSubject;

  final DateTime importedAt;

  const TranscriptEntry({
    this.id,
    this.subjectId,
    required this.subjectCode,
    this.subjectName = '',
    this.term,
    this.semesterLabel = '',
    this.semesterYear,
    this.season,
    this.semesterOrder = 0,
    this.credits = 0,
    this.grade,
    this.status = SubjectStatus.unknown,
    this.isGraduationCondition = false,
    this.countsTowardGpa = false,
    this.rawPrerequisite = '',
    this.replacedSubject = '',
    required this.importedAt,
  });

  /// Quy tắc mặc định: chỉ môn **đã qua, có điểm, có tín chỉ và không phải môn
  /// điều kiện tốt nghiệp** mới vào GPA. Bốn điều kiện phải đủ cả bốn — thiếu
  /// một cái là GPA lệch so với bảng điểm FAP.
  static bool countsTowardGpaByDefault({
    required SubjectStatus status,
    required double? grade,
    required int credits,
    required bool isGraduationCondition,
  }) =>
      status == SubjectStatus.passed &&
      grade != null &&
      credits > 0 &&
      !isGraduationCondition;

  TranscriptEntry copyWith({
    int? id,
    int? subjectId,
    bool clearSubjectId = false,
    String? subjectCode,
    String? subjectName,
    int? term,
    String? semesterLabel,
    int? semesterYear,
    Season? season,
    int? semesterOrder,
    int? credits,
    double? grade,
    SubjectStatus? status,
    bool? isGraduationCondition,
    bool? countsTowardGpa,
    String? rawPrerequisite,
    String? replacedSubject,
    DateTime? importedAt,
  }) {
    return TranscriptEntry(
      id: id ?? this.id,
      subjectId: clearSubjectId ? null : (subjectId ?? this.subjectId),
      subjectCode: subjectCode ?? this.subjectCode,
      subjectName: subjectName ?? this.subjectName,
      term: term ?? this.term,
      semesterLabel: semesterLabel ?? this.semesterLabel,
      semesterYear: semesterYear ?? this.semesterYear,
      season: season ?? this.season,
      semesterOrder: semesterOrder ?? this.semesterOrder,
      credits: credits ?? this.credits,
      grade: grade ?? this.grade,
      status: status ?? this.status,
      isGraduationCondition:
          isGraduationCondition ?? this.isGraduationCondition,
      countsTowardGpa: countsTowardGpa ?? this.countsTowardGpa,
      rawPrerequisite: rawPrerequisite ?? this.rawPrerequisite,
      replacedSubject: replacedSubject ?? this.replacedSubject,
      importedAt: importedAt ?? this.importedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'subject_id': subjectId,
      'subject_code': subjectCode,
      'subject_name': subjectName,
      'term': term,
      'semester_label': semesterLabel,
      'semester_year': semesterYear,
      'semester_season': season?.name,
      'semester_order': semesterOrder,
      'credits': credits,
      'grade': grade,
      'status': statusToDb(status),
      'is_graduation_condition': isGraduationCondition ? 1 : 0,
      'counts_toward_gpa': countsTowardGpa ? 1 : 0,
      'raw_prerequisite': rawPrerequisite,
      'replaced_subject': replacedSubject,
      'imported_at': importedAt.toIso8601String(),
    };
  }

  factory TranscriptEntry.fromMap(Map<String, Object?> map) {
    return TranscriptEntry(
      id: map['id'] as int?,
      subjectId: map['subject_id'] as int?,
      subjectCode: ((map['subject_code'] as String?) ?? '').toUpperCase(),
      subjectName: (map['subject_name'] as String?) ?? '',
      term: map['term'] as int?,
      semesterLabel: (map['semester_label'] as String?) ?? '',
      semesterYear: map['semester_year'] as int?,
      season: seasonFromName(map['semester_season'] as String?),
      semesterOrder: (map['semester_order'] as int?) ?? 0,
      credits: (map['credits'] as int?) ?? 0,
      grade: (map['grade'] as num?)?.toDouble(),
      status: statusFromDb(map['status'] as String?),
      isGraduationCondition:
          ((map['is_graduation_condition'] as int?) ?? 0) == 1,
      countsTowardGpa: ((map['counts_toward_gpa'] as int?) ?? 0) == 1,
      rawPrerequisite: (map['raw_prerequisite'] as String?) ?? '',
      replacedSubject: (map['replaced_subject'] as String?) ?? '',
      importedAt:
          DateTime.tryParse((map['imported_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  /// Ghi trạng thái xuống CSDL bằng chuỗi viết hoa thay vì số thứ tự enum:
  /// chèn thêm một giá trị vào giữa [SubjectStatus] sau này sẽ không làm sai
  /// lệch dữ liệu đã lưu trên máy người dùng.
  static String statusToDb(SubjectStatus status) => switch (status) {
    SubjectStatus.passed => 'PASSED',
    SubjectStatus.notPassed => 'NOT_PASSED',
    SubjectStatus.studying => 'STUDYING',
    SubjectStatus.notStarted => 'NOT_STARTED',
    SubjectStatus.unknown => 'UNKNOWN',
  };

  static SubjectStatus statusFromDb(String? raw) => switch (raw) {
    'PASSED' => SubjectStatus.passed,
    'NOT_PASSED' => SubjectStatus.notPassed,
    'STUDYING' => SubjectStatus.studying,
    'NOT_STARTED' => SubjectStatus.notStarted,
    _ => SubjectStatus.unknown,
  };

  static Season? seasonFromName(String? raw) => switch (raw) {
    'spring' => Season.spring,
    'summer' => Season.summer,
    'fall' => Season.fall,
    _ => null,
  };

  bool get hasGrade => grade != null;

  /// Điểm để in ra màn hình. Môn chưa có điểm hiện gạch ngang chứ không để
  /// trống — ô trống trông y hệt lỗi không tải được dữ liệu.
  String get displayGrade {
    final g = grade;
    if (g == null) return '—';
    // FAP in "10" chứ không in "10.0", giữ nguyên cách đọc đó.
    return g == g.roundToDouble() ? g.toStringAsFixed(0) : g.toStringAsFixed(1);
  }

  String get statusLabel => switch (status) {
    SubjectStatus.passed => 'Đã qua',
    SubjectStatus.notPassed => 'Chưa qua',
    SubjectStatus.studying => 'Đang học',
    SubjectStatus.notStarted => 'Chưa học',
    SubjectStatus.unknown => 'Không rõ',
  };

  /// Nhãn kỳ để hiển thị. Môn chưa học không có kỳ nên trả gạch ngang.
  String get displaySemester => semesterLabel.isEmpty ? '—' : semesterLabel;

  @override
  String toString() =>
      'TranscriptEntry($subjectCode, $semesterLabel, $displayGrade, '
      '$statusLabel)';
}
