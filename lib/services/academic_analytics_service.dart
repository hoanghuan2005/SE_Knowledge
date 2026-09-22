import '../models/graph_data.dart';
import '../models/transcript_entry.dart';

/// Tính GPA, nhóm năng lực và cảnh báo rủi ro từ bảng điểm.
///
/// Thuần Dart, chỉ nhận dữ liệu đã nạp sẵn ([List] điểm + [GraphData]) nên
/// kiểm thử được mà không cần mở CSDL — cùng cách `SubjectDeleteGuard`
/// tách `analyzeGraph()` ra khỏi `analyze()`.
///
/// Giá trị riêng của lớp này nằm ở [AcademicProfile.risks]: ghép bảng điểm với
/// đồ thị tiên quyết để chỉ ra môn sắp học nào đang đứng trên một nền yếu.
/// Bảng điểm FAP không làm được điều đó vì nó không biết đồ thị.
class AcademicAnalyticsService {
  AcademicAnalyticsService._();
  static final AcademicAnalyticsService instance = AcademicAnalyticsService._();

  /// Dưới ngưỡng này coi là "cần cải thiện". 7.0 là mốc Khá của FPTU, cũng là
  /// mốc mà môn nền bắt đầu đủ yếu để ảnh hưởng tới môn phía sau.
  static const double weakGradeThreshold = 7.0;

  /// Chênh lệch GPA nhóm so với GPA tổng đủ lớn để gọi là mạnh / yếu.
  static const double domainDeltaThreshold = 0.3;

  /// Số môn đã có điểm tối thiểu để dám kết luận về một nhóm năng lực.
  /// Ba môn tiếng Nhật điểm cao không đủ để nói "bạn giỏi ngoại ngữ".
  static const int minSubjectsForConclusion = 3;

  /// Chênh lệch GPA giữa hai cụm kỳ để gọi là đi lên / đi xuống.
  static const double trendThreshold = 0.2;

  /// Dưới ngần này kỳ thì mọi kết luận về xu hướng đều là đoán mò.
  static const int minSemestersForTrend = 4;

  /// Số môn trong danh sách mạnh nhất / yếu nhất.
  static const int highlightCount = 5;

  /// Trần số cảnh báo giữ lại. Đồ thị đầy đủ có hàng chục môn chưa học, liệt
  /// kê hết thì phần đáng đọc chìm nghỉm.
  static const int maxRisks = 20;

  /// Phân loại môn vào nhóm năng lực theo **tiền tố mã môn**.
  ///
  /// Đây là heuristic, không phải phân loại chính thức của nhà trường: FAP
  /// không phát ra thông tin nhóm kiến thức, mà tiền tố mã môn là manh mối
  /// duy nhất đọc được. Để ở một hằng số duy nhất để sửa lại cho dễ khi khung
  /// chương trình đổi mã môn.
  static const Map<String, String> domainByPrefix = {
    // Lập trình
    'PRF': 'Lập trình', 'PRO': 'Lập trình', 'PRJ': 'Lập trình',
    'PRM': 'Lập trình', 'LAB': 'Lập trình', 'CSD': 'Lập trình',
    'WED': 'Lập trình', 'WDU': 'Lập trình',
    // Toán & nền tảng
    'MAE': 'Toán & nền tảng', 'MAD': 'Toán & nền tảng',
    'MAS': 'Toán & nền tảng', 'MAC': 'Toán & nền tảng',
    'CEA': 'Toán & nền tảng', 'CSI': 'Toán & nền tảng',
    'OSG': 'Toán & nền tảng', 'NWC': 'Toán & nền tảng',
    'IOT': 'Toán & nền tảng',
    // Kỹ nghệ phần mềm
    'SWE': 'Kỹ nghệ phần mềm', 'SWR': 'Kỹ nghệ phần mềm',
    'SWT': 'Kỹ nghệ phần mềm', 'SWD': 'Kỹ nghệ phần mềm',
    'SWP': 'Kỹ nghệ phần mềm', 'PMG': 'Kỹ nghệ phần mềm',
    'SEP': 'Kỹ nghệ phần mềm', 'OJT': 'Kỹ nghệ phần mềm',
    // Cơ sở dữ liệu
    'DBI': 'Cơ sở dữ liệu',
    // Kỹ năng & ngoại ngữ
    'SSL': 'Kỹ năng & ngoại ngữ', 'SSG': 'Kỹ năng & ngoại ngữ',
    'ENW': 'Kỹ năng & ngoại ngữ', 'JPD': 'Kỹ năng & ngoại ngữ',
    'TRS': 'Kỹ năng & ngoại ngữ', 'VOV': 'Kỹ năng & ngoại ngữ',
    'OTP': 'Kỹ năng & ngoại ngữ', 'SYB': 'Kỹ năng & ngoại ngữ',
    'TMI': 'Kỹ năng & ngoại ngữ',
    // Chính trị & đạo đức
    'MLN': 'Chính trị & đạo đức', 'VNR': 'Chính trị & đạo đức',
    'HCM': 'Chính trị & đạo đức', 'ITE': 'Chính trị & đạo đức',
  };

  static const String otherDomain = 'Khác';

  static final RegExp _prefixPattern = RegExp(r'^[A-Z]+');

  /// Phân tích toàn bộ bảng điểm. [graph] chỉ dùng cho phần cảnh báo rủi ro,
  /// truyền [GraphData.empty] vào thì các chỉ số còn lại vẫn đúng.
  AcademicProfile analyze(List<TranscriptEntry> entries, GraphData graph) {
    if (entries.isEmpty) return AcademicProfile.empty;

    final counted = effectiveGpaEntries(entries);
    final totalCredits = counted.fold<int>(0, (sum, e) => sum + e.credits);
    final gpa = _weightedGpa(counted);

    final statusByCode = _statusByCode(entries);
    var passed = 0, studying = 0, notStarted = 0;
    for (final status in statusByCode.values) {
      switch (status) {
        case SubjectStatus.passed:
          passed++;
        case SubjectStatus.studying:
          studying++;
        case SubjectStatus.notStarted:
          notStarted++;
        case SubjectStatus.notPassed:
        case SubjectStatus.unknown:
          break;
      }
    }

    final bySemester = _semesterBreakdown(counted);
    final byDomain = _domainBreakdown(counted, gpa);

    final ranked = [...counted]..sort((a, b) {
      final byGrade = (b.grade ?? 0).compareTo(a.grade ?? 0);
      return byGrade != 0 ? byGrade : a.subjectCode.compareTo(b.subjectCode);
    });
    final weakest = ranked.reversed
        .where((e) => (e.grade ?? 0) < weakGradeThreshold)
        .take(highlightCount)
        .toList();

    return AcademicProfile(
      gpa: gpa,
      totalCredits: totalCredits,
      gpaSubjectCount: counted.length,
      passedCount: passed,
      studyingCount: studying,
      notStartedCount: notStarted,
      bySemester: bySemester,
      byDomain: byDomain,
      strongest: ranked.take(highlightCount).toList(),
      weakest: weakest,
      trend: _trendOf(bySemester),
      risks: _risks(entries, graph),
    );
  }

  /// Các dòng thật sự được cộng vào GPA.
  ///
  /// Học lại: cùng một mã môn có nhiều dòng thì **chỉ lấy lần qua môn mới
  /// nhất theo thời gian**. Các lần trước vẫn nằm trong CSDL làm lịch sử
  /// nhưng không cộng vào GPA — nếu không, một môn thi lại sẽ được đếm hai
  /// lần cả tín chỉ lẫn điểm.
  List<TranscriptEntry> effectiveGpaEntries(List<TranscriptEntry> entries) {
    final latest = <String, TranscriptEntry>{};
    for (final e in entries) {
      if (!e.countsTowardGpa || e.grade == null || e.credits <= 0) continue;
      final current = latest[e.subjectCode];
      if (current == null || e.semesterOrder >= current.semesterOrder) {
        latest[e.subjectCode] = e;
      }
    }
    return latest.values.toList()
      ..sort((a, b) {
        final byOrder = a.semesterOrder.compareTo(b.semesterOrder);
        return byOrder != 0 ? byOrder : a.subjectCode.compareTo(b.subjectCode);
      });
  }

  /// GPA = Σ(điểm × tín chỉ) / Σ(tín chỉ), làm tròn 2 chữ số.
  /// Danh sách rỗng trả 0 chứ không chia cho 0.
  double _weightedGpa(List<TranscriptEntry> entries) {
    var weighted = 0.0;
    var credits = 0;
    for (final e in entries) {
      weighted += (e.grade ?? 0) * e.credits;
      credits += e.credits;
    }
    if (credits == 0) return 0;
    return double.parse((weighted / credits).toStringAsFixed(2));
  }

  /// Trạng thái tiêu biểu của mỗi mã môn. Đếm theo mã môn chứ không theo
  /// dòng, để một môn học lại không bị tính thành hai môn.
  Map<String, SubjectStatus> _statusByCode(List<TranscriptEntry> entries) => {
    for (final e in latestByCode(entries).entries) e.key: e.value.status,
  };

  List<SemesterGpa> _semesterBreakdown(List<TranscriptEntry> counted) {
    final groups = <int, List<TranscriptEntry>>{};
    for (final e in counted) {
      if (e.semesterOrder <= 0) continue;
      groups.putIfAbsent(e.semesterOrder, () => []).add(e);
    }

    final result = groups.entries.map((g) {
      final rows = g.value;
      return SemesterGpa(
        label: rows.first.semesterLabel,
        order: g.key,
        gpa: _weightedGpa(rows),
        credits: rows.fold<int>(0, (sum, e) => sum + e.credits),
        subjectCount: rows.length,
      );
    }).toList();

    result.sort((a, b) => a.order.compareTo(b.order));
    return result;
  }

  List<DomainScore> _domainBreakdown(
    List<TranscriptEntry> counted,
    double overallGpa,
  ) {
    final groups = <String, List<TranscriptEntry>>{};
    for (final e in counted) {
      groups.putIfAbsent(domainOf(e.subjectCode), () => []).add(e);
    }

    final result = groups.entries.map((g) {
      final gpa = _weightedGpa(g.value);
      return DomainScore(
        name: g.key,
        gpa: gpa,
        delta: double.parse((gpa - overallGpa).toStringAsFixed(2)),
        subjectCount: g.value.length,
        credits: g.value.fold<int>(0, (sum, e) => sum + e.credits),
        codes: g.value.map((e) => e.subjectCode).toList()..sort(),
      );
    }).toList();

    result.sort((a, b) => b.gpa.compareTo(a.gpa));
    return result;
  }

  /// Nhóm năng lực của một mã môn, theo tiền tố chữ cái đầu.
  String domainOf(String subjectCode) {
    final prefix =
        _prefixPattern.firstMatch(subjectCode.toUpperCase())?.group(0) ?? '';
    return domainByPrefix[prefix] ?? otherDomain;
  }

  /// So GPA trung bình 3 kỳ gần nhất với 3 kỳ ngay trước đó.
  TrendDirection _trendOf(List<SemesterGpa> bySemester) {
    if (bySemester.length < minSemestersForTrend) {
      return TrendDirection.unknown;
    }
    final recent = bySemester.sublist(bySemester.length - 3);
    final earlierAll = bySemester.sublist(0, bySemester.length - 3);
    final earlier = earlierAll.length <= 3
        ? earlierAll
        : earlierAll.sublist(earlierAll.length - 3);

    double mean(List<SemesterGpa> list) =>
        list.fold<double>(0, (sum, s) => sum + s.gpa) / list.length;

    final delta = mean(recent) - mean(earlier);
    if (delta > trendThreshold) return TrendDirection.improving;
    if (delta < -trendThreshold) return TrendDirection.declining;
    return TrendDirection.stable;
  }

  /// Ghép bảng điểm với đồ thị tiên quyết để tìm chỗ sắp vỡ.
  ///
  /// Với mỗi môn **chưa học hoặc đang học**, duyệt các môn tiên quyết của nó:
  /// môn nền đã qua nhưng điểm thấp là cảnh báo nền yếu, môn nền chưa qua là
  /// cảnh báo chặn lộ trình. Xếp hạng theo số môn phụ thuộc phía sau nhân với
  /// độ thấp của điểm nền — môn nền yếu mà mở ra nhiều môn là rủi ro nặng
  /// nhất, vì nó kéo theo cả một nhánh của đồ thị.
  List<RiskWarning> _risks(List<TranscriptEntry> entries, GraphData graph) {
    if (graph.isEmpty) return const [];

    final byCode = latestByCode(entries);
    final byId = graph.byId;
    final warnings = <RiskWarning>[];

    for (final subject in graph.subjects) {
      final id = subject.id;
      if (id == null) continue;

      final own = byCode[subject.code.toUpperCase()];
      final ownStatus = own?.status ?? SubjectStatus.notStarted;
      // Môn đã qua rồi thì nền yếu không còn là rủi ro phía trước nữa.
      if (ownStatus == SubjectStatus.passed) continue;

      for (final edge in graph.edges.where((e) => e.subjectId == id)) {
        final prereq = byId[edge.prerequisiteId];
        if (prereq == null) continue;

        final prereqEntry = byCode[prereq.code.toUpperCase()];
        final dependents = graph.outDegree(edge.prerequisiteId);
        final isStudyingNow = ownStatus == SubjectStatus.studying;

        if (prereqEntry?.status == SubjectStatus.passed) {
          final grade = prereqEntry?.grade;
          if (grade == null || grade >= weakGradeThreshold) continue;
          warnings.add(
            RiskWarning(
              kind: RiskKind.weakFoundation,
              subjectCode: subject.code,
              subjectName: subject.name,
              subjectStatus: ownStatus,
              prerequisiteCode: prereq.code,
              prerequisiteName: prereq.name,
              prerequisiteGrade: grade,
              dependentCount: dependents,
              score: (weakGradeThreshold - grade) * (1 + dependents),
              message:
                  '${isStudyingNow ? "Đang học" : "Sắp học"} [[${subject.code}]] '
                  'nhưng nền [[${prereq.code}]] mới '
                  '${prereqEntry!.displayGrade}.',
            ),
          );
        } else {
          warnings.add(
            RiskWarning(
              kind: RiskKind.blockedPath,
              subjectCode: subject.code,
              subjectName: subject.name,
              subjectStatus: ownStatus,
              prerequisiteCode: prereq.code,
              prerequisiteName: prereq.name,
              prerequisiteGrade: null,
              dependentCount: dependents,
              // Nền yếu đáng lo hơn nền chưa học (chưa học là lịch trình bình
              // thường), trừ khi đang học môn sau mà môn nền vẫn chưa qua —
              // lúc đó mới thật sự sai lộ trình.
              score: (isStudyingNow ? 3.0 : 0.5) * (1 + dependents),
              message: isStudyingNow
                  ? 'Đang học [[${subject.code}]] khi môn tiên quyết '
                        '[[${prereq.code}]] chưa qua.'
                  : 'Chưa học được [[${subject.code}]] cho tới khi qua '
                        '[[${prereq.code}]].',
            ),
          );
        }
      }
    }

    warnings.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.subjectCode.compareTo(b.subjectCode);
    });
    return warnings.take(maxRisks).toList();
  }

  /// Dòng tiêu biểu của mỗi mã môn: ưu tiên lần **qua môn mới nhất**, chưa qua
  /// lần nào thì lấy dòng mới nhất. Dùng cho panel chi tiết, tô màu đồ thị và
  /// phần cảnh báo rủi ro.
  Map<String, TranscriptEntry> latestByCode(List<TranscriptEntry> entries) {
    final best = <String, TranscriptEntry>{};
    for (final e in entries) {
      final code = e.subjectCode.toUpperCase();
      final current = best[code];
      if (current == null) {
        best[code] = e;
        continue;
      }
      final currentPassed = current.status == SubjectStatus.passed;
      final newPassed = e.status == SubjectStatus.passed;
      if (newPassed && !currentPassed) {
        best[code] = e;
      } else if (newPassed == currentPassed &&
          e.semesterOrder >= current.semesterOrder) {
        best[code] = e;
      }
    }
    return best;
  }
}

/// Xu hướng điểm qua các kỳ.
enum TrendDirection { improving, stable, declining, unknown }

extension TrendLabel on TrendDirection {
  String get label => switch (this) {
    TrendDirection.improving => 'đi lên',
    TrendDirection.stable => 'đi ngang',
    TrendDirection.declining => 'đi xuống',
    TrendDirection.unknown => 'chưa đủ dữ liệu',
  };
}

/// Loại rủi ro tìm được khi soi bảng điểm trên đồ thị tiên quyết.
enum RiskKind {
  /// Môn tiên quyết đã qua nhưng điểm thấp.
  weakFoundation,

  /// Môn tiên quyết chưa qua — lộ trình đang bị chặn.
  blockedPath,
}

/// GPA của một kỳ, dùng vẽ biểu đồ đường.
class SemesterGpa {
  final String label;
  final int order;
  final double gpa;
  final int credits;
  final int subjectCount;

  const SemesterGpa({
    required this.label,
    required this.order,
    required this.gpa,
    required this.credits,
    required this.subjectCount,
  });

  @override
  String toString() => '$label: $gpa ($credits tín chỉ)';
}

/// Điểm trung bình của một nhóm năng lực.
class DomainScore {
  final String name;
  final double gpa;

  /// Chênh lệch so với GPA tích luỹ. Dương là mạnh hơn mặt bằng của chính
  /// mình, âm là yếu hơn.
  final double delta;

  final int subjectCount;
  final int credits;

  /// Mã các môn thuộc nhóm, để giao diện và AI dẫn được bằng chứng cụ thể.
  final List<String> codes;

  const DomainScore({
    required this.name,
    required this.gpa,
    required this.delta,
    required this.subjectCount,
    required this.credits,
    this.codes = const [],
  });

  /// Đủ số môn để dám kết luận chưa. Dưới ngưỡng thì giao diện hiển thị mờ và
  /// AI bị cấm kết luận mạnh/yếu từ nhóm này.
  bool get isSignificant =>
      subjectCount >= AcademicAnalyticsService.minSubjectsForConclusion;

  bool get isStrong =>
      isSignificant && delta > AcademicAnalyticsService.domainDeltaThreshold;

  bool get isWeak =>
      isSignificant && delta < -AcademicAnalyticsService.domainDeltaThreshold;

  /// Nhãn chênh lệch kèm dấu: `+0.4`, `−0.6`.
  ///
  /// Chênh lệch nhỏ hơn nửa vạch làm tròn thì ghi `±0.0` chứ không ghi `−0.0`
  /// — dấu trừ trước số không làm người đọc tưởng nhóm đó đang yếu đi.
  String get deltaLabel {
    final rounded = double.parse(delta.toStringAsFixed(1));
    if (rounded == 0) return '±0.0';
    return '${rounded > 0 ? '+' : '−'}${rounded.abs().toStringAsFixed(1)}';
  }

  @override
  String toString() => '$name: $gpa ($subjectCount môn, $deltaLabel)';
}

/// Một cảnh báo rủi ro dựng từ đồ thị tiên quyết.
class RiskWarning {
  final RiskKind kind;

  /// Môn sắp học / đang học đang chịu rủi ro.
  final String subjectCode;
  final String subjectName;
  final SubjectStatus subjectStatus;

  /// Môn nền gây ra rủi ro.
  final String prerequisiteCode;
  final String prerequisiteName;
  final double? prerequisiteGrade;

  /// Số môn khác cũng phụ thuộc vào môn nền này.
  final int dependentCount;

  /// Điểm xếp hạng nội bộ, càng cao càng đáng xử lý trước.
  final double score;

  /// Câu mô tả đã có sẵn `[[MÃ MÔN]]` để giao diện bóc thành liên kết.
  final String message;

  const RiskWarning({
    required this.kind,
    required this.subjectCode,
    required this.subjectName,
    required this.subjectStatus,
    required this.prerequisiteCode,
    required this.prerequisiteName,
    this.prerequisiteGrade,
    this.dependentCount = 0,
    required this.score,
    required this.message,
  });

  @override
  String toString() => message;
}

/// Bức tranh học lực đầy đủ, tính một lần sau mỗi lần nạp bảng điểm.
class AcademicProfile {
  final double gpa;
  final int totalCredits;

  /// Số môn thật sự được cộng vào GPA (đã loại môn điều kiện tốt nghiệp, môn
  /// không điểm, môn 0 tín chỉ và các lần học lại cũ).
  final int gpaSubjectCount;

  final int passedCount;
  final int studyingCount;
  final int notStartedCount;

  final List<SemesterGpa> bySemester;
  final List<DomainScore> byDomain;
  final List<TranscriptEntry> strongest;
  final List<TranscriptEntry> weakest;
  final TrendDirection trend;
  final List<RiskWarning> risks;

  const AcademicProfile({
    required this.gpa,
    required this.totalCredits,
    required this.gpaSubjectCount,
    required this.passedCount,
    required this.studyingCount,
    required this.notStartedCount,
    this.bySemester = const [],
    this.byDomain = const [],
    this.strongest = const [],
    this.weakest = const [],
    this.trend = TrendDirection.unknown,
    this.risks = const [],
  });

  static const AcademicProfile empty = AcademicProfile(
    gpa: 0,
    totalCredits: 0,
    gpaSubjectCount: 0,
    passedCount: 0,
    studyingCount: 0,
    notStartedCount: 0,
  );

  bool get isEmpty => gpaSubjectCount == 0 && passedCount == 0;

  String get gpaLabel => gpa.toStringAsFixed(2);

  List<DomainScore> get significantDomains =>
      byDomain.where((d) => d.isSignificant).toList();

  DomainScore? get strongestDomain {
    final list = significantDomains;
    return list.isEmpty ? null : list.first;
  }

  DomainScore? get weakestDomain {
    final list = significantDomains;
    return list.isEmpty ? null : list.last;
  }

  /// Câu tóm tắt một dòng, nhét vào đầu prompt Graph RAG.
  String get summaryLine {
    final sb = StringBuffer(
      'Tình hình học tập của sinh viên: GPA tích luỹ $gpaLabel trên '
      '$totalCredits tín chỉ, đã qua $passedCount môn, đang học '
      '$studyingCount môn, còn $notStartedCount môn chưa bắt đầu.',
    );
    final strong = strongestDomain;
    final weak = weakestDomain;
    if (strong != null && weak != null && strong.name != weak.name) {
      sb.write(
        ' Nhóm mạnh: ${strong.name} (${strong.gpa.toStringAsFixed(1)}). '
        'Nhóm yếu: ${weak.name} (${weak.gpa.toStringAsFixed(1)}).',
      );
    }
    if (trend != TrendDirection.unknown) {
      sb.write(' Xu hướng 3 kỳ gần nhất: ${trend.label}.');
    }
    return sb.toString();
  }

  /// Dựng toàn bộ hồ sơ thành văn bản để gửi kèm câu hỏi cho AI.
  ///
  /// Chỉ đưa số liệu, không đưa nhận xét: phần kết luận là việc của AI, và
  /// nhồi sẵn kết luận vào đây thì câu trả lời chỉ chép lại lời của app.
  String renderForPrompt() {
    final sb = StringBuffer()
      ..writeln(summaryLine)
      ..writeln();

    if (bySemester.isNotEmpty) {
      sb.writeln('GPA từng kỳ (cũ -> mới):');
      for (final s in bySemester) {
        sb.writeln(
          '- ${s.label}: ${s.gpa.toStringAsFixed(2)} '
          '(${s.subjectCount} môn, ${s.credits} tín chỉ)',
        );
      }
      sb.writeln();
    }

    if (byDomain.isNotEmpty) {
      sb.writeln('Điểm trung bình theo nhóm năng lực:');
      for (final d in byDomain) {
        sb.writeln(
          '- ${d.name}: ${d.gpa.toStringAsFixed(2)} '
          '(${d.subjectCount} môn có điểm, lệch ${d.deltaLabel} so với GPA '
          'tích luỹ)'
          '${d.isSignificant ? "" : " — chưa đủ 3 môn, không đủ dữ liệu để kết luận"}'
          '. Gồm: ${d.codes.join(", ")}',
        );
      }
      sb.writeln();
    }

    if (strongest.isNotEmpty) {
      sb.writeln('Các môn điểm cao nhất:');
      for (final e in strongest) {
        sb.writeln(
          '- ${e.subjectCode} (${e.subjectName}): ${e.displayGrade} '
          '— ${e.displaySemester}',
        );
      }
      sb.writeln();
    }

    if (weakest.isNotEmpty) {
      sb.writeln('Các môn điểm thấp nhất:');
      for (final e in weakest) {
        sb.writeln(
          '- ${e.subjectCode} (${e.subjectName}): ${e.displayGrade} '
          '— ${e.displaySemester}',
        );
      }
      sb.writeln();
    }

    if (risks.isNotEmpty) {
      sb.writeln('Rủi ro đọc được từ đồ thị tiên quyết:');
      for (final r in risks) {
        sb.writeln(
          '- ${r.message} Môn nền ${r.prerequisiteCode} mở ra '
          '${r.dependentCount} môn phía sau.',
        );
      }
    }
    return sb.toString();
  }
}
