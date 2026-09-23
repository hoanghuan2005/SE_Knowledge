import 'dart:math' as math;

import '../models/graph_data.dart';
import '../models/transcript_entry.dart';
import 'academic_analytics_service.dart';

/// Lập kế hoạch để đạt một **GPA mục tiêu** (mặc định 8.0).
///
/// Trả lời ba câu hỏi mà bảng điểm FAP không trả lời:
///
/// 1. Các môn còn lại phải đạt trung bình bao nhiêu thì GPA tốt nghiệp chạm
///    mục tiêu?
/// 2. Nếu không kịp, nên đăng ký **học cải thiện** môn nào để được nhiều điểm
///    GPA nhất — xếp theo `tín chỉ × khoảng cách tới mục tiêu`, vì một môn 3
///    tín chỉ từ 6.0 lên 8.5 đáng giá hơn hẳn một môn 2 tín chỉ từ 7.8 lên 8.5.
/// 3. Với một phương án cụ thể (điểm dự kiến + các môn học lại), GPA cuối
///    khoá sẽ là bao nhiêu?
///
/// Thuần Dart như [AcademicAnalyticsService], nhận dữ liệu đã nạp sẵn.
class GoalPlannerService {
  GoalPlannerService._();
  static final GoalPlannerService instance = GoalPlannerService._();

  static const double defaultTarget = 8.0;

  /// Học lại thì giả định đạt mục tiêu + 0.5 (tối đa 10), và ít nhất cao hơn
  /// điểm cũ 0.5 — học lại để được thêm vài phần trăm điểm thì chẳng ai làm.
  static const double retakeMargin = 0.5;

  /// Số môn cải thiện tối đa đưa ra. Nhiều hơn thế thì không còn là lời
  /// khuyên mà là danh sách lại cả bảng điểm.
  static const int maxRetakes = 8;

  /// Tiền tố của các môn không tính GPA khi bảng điểm chưa có dòng của môn
  /// đó (môn trong khung nhưng FAP chưa liệt kê). Có dòng FAP thì cờ `*` của
  /// FAP được tin trước.
  static const Set<String> nonGpaPrefixes = {
    'OTP',
    'VOV',
    'PHE',
    'TRS',
    'GDQP',
    'PEN',
    'TMI',
    'TRG',
    'ENT',
  };

  GoalPlan plan(
    List<TranscriptEntry> entries, {
    double target = defaultTarget,
    GraphData graph = GraphData.empty,
    Set<String> programmingCodes = const {},
    List<PlannedSubject> curriculumSubjects = const [],
  }) {
    final analytics = AcademicAnalyticsService.instance;
    final counted = analytics.effectiveGpaEntries(entries);
    final countedCodes = {for (final e in counted) e.subjectCode.toUpperCase()};

    var points = 0.0;
    var credits = 0;
    for (final e in counted) {
      points += (e.grade ?? 0) * e.credits;
      credits += e.credits;
    }

    // Môn còn phải học và sẽ vào GPA: chưa qua, có tín chỉ, không phải môn
    // điều kiện tốt nghiệp.
    final latest = analytics.latestByCode(entries);
    final remaining = <PlannedSubject>[];
    final seen = <String>{...countedCodes};
    for (final entry in latest.entries) {
      final e = entry.value;
      final code = entry.key;
      if (seen.contains(code)) continue;
      if (e.status == SubjectStatus.passed) continue;
      if (e.isGraduationCondition || e.credits <= 0) continue;
      seen.add(code);
      remaining.add(
        PlannedSubject(
          code: code,
          name: e.subjectName,
          credits: e.credits,
          status: e.status,
        ),
      );
    }
    // Môn có trong khung nhưng bảng điểm không nhắc tới.
    for (final s in curriculumSubjects) {
      final code = s.code.toUpperCase();
      if (seen.contains(code) || s.credits <= 0) continue;
      if (latest.containsKey(code)) continue;
      if (_isNonGpaCode(code)) continue;
      seen.add(code);
      remaining.add(s);
    }
    remaining.sort((a, b) => a.code.compareTo(b.code));

    final remainingCredits = remaining.fold<int>(0, (s, r) => s + r.credits);
    final currentGpa = credits == 0 ? 0.0 : points / credits;

    // Học cải thiện: chỉ môn đã qua và đang dưới mục tiêu.
    final byId = graph.byId;
    final idByCode = {
      for (final s in graph.subjects)
        if (s.id != null) s.code.toUpperCase(): s.id!,
    };
    final totalAfter = credits + remainingCredits;
    final retakes = <RetakeSuggestion>[];
    for (final e in counted) {
      final grade = e.grade ?? 0;
      if (grade >= target) continue;
      final code = e.subjectCode.toUpperCase();
      final assumed = math.min(
        10.0,
        math.max(target + retakeMargin, grade + retakeMargin),
      );
      final delta = (assumed - grade) * e.credits;

      final reasons = <String>[];
      if (programmingCodes.contains(code) ||
          analytics.domainOf(code) == 'Lập trình') {
        reasons.add('môn lập trình');
      }
      final id = idByCode[code];
      if (id != null && byId.containsKey(id)) {
        final dependents = graph.outDegree(id);
        if (dependents >= 2) reasons.add('nền của $dependents môn phía sau');
      }
      if (grade < AcademicAnalyticsService.weakGradeThreshold) {
        reasons.add('dưới mức Khá');
      }

      retakes.add(
        RetakeSuggestion(
          code: code,
          name: e.subjectName,
          credits: e.credits,
          currentGrade: grade,
          assumedGrade: assumed,
          gainNow: credits == 0 ? 0 : delta / credits,
          gainFinal: totalAfter == 0 ? 0 : delta / totalAfter,
          reasons: reasons,
        ),
      );
    }
    retakes.sort((a, b) {
      final byGain = b.gainNow.compareTo(a.gainNow);
      return byGain != 0 ? byGain : a.code.compareTo(b.code);
    });

    return GoalPlan(
      target: target,
      currentGpa: currentGpa,
      countedCredits: credits,
      currentPoints: points,
      remaining: remaining,
      remainingCredits: remainingCredits,
      retakes: retakes.take(maxRetakes).toList(),
      belowTargetCount: retakes.length,
    );
  }

  static bool _isNonGpaCode(String code) {
    final prefix = RegExp(r'^[A-Z]+').firstMatch(code)?.group(0) ?? '';
    return nonGpaPrefixes.contains(prefix);
  }
}

/// Một môn còn phải học (hoặc học lại vì chưa qua).
class PlannedSubject {
  final String code;
  final String name;
  final int credits;
  final SubjectStatus status;

  const PlannedSubject({
    required this.code,
    this.name = '',
    required this.credits,
    this.status = SubjectStatus.notStarted,
  });
}

/// Một môn nên cân nhắc đăng ký học cải thiện.
class RetakeSuggestion {
  final String code;
  final String name;
  final int credits;
  final double currentGrade;

  /// Điểm giả định nếu học lại — xem [GoalPlannerService.retakeMargin].
  final double assumedGrade;

  /// GPA hiện tại tăng thêm bao nhiêu nếu học lại ngay.
  final double gainNow;

  /// GPA tốt nghiệp tăng thêm bao nhiêu (mẫu số gồm cả tín chỉ còn lại).
  final double gainFinal;

  final List<String> reasons;

  const RetakeSuggestion({
    required this.code,
    this.name = '',
    required this.credits,
    required this.currentGrade,
    required this.assumedGrade,
    required this.gainNow,
    required this.gainFinal,
    this.reasons = const [],
  });
}

/// Mức độ khả thi của mục tiêu.
enum GoalStatus {
  /// Đã đạt và các môn còn lại chỉ cần qua môn là giữ được.
  secured,

  /// Giữ phong độ hiện tại là đạt.
  onTrack,

  /// Đạt được nhưng phải học tốt hơn hiện tại.
  stretch,

  /// Kể cả 10 điểm mọi môn còn lại cũng không kịp — phải học cải thiện.
  needsRetake,
}

class GoalPlan {
  final double target;
  final double currentGpa;
  final int countedCredits;
  final double currentPoints;
  final List<PlannedSubject> remaining;
  final int remainingCredits;
  final List<RetakeSuggestion> retakes;

  /// Tổng số môn đã qua mà điểm dưới mục tiêu (kể cả những môn không lọt
  /// vào danh sách gợi ý rút gọn [retakes]).
  final int belowTargetCount;

  const GoalPlan({
    required this.target,
    required this.currentGpa,
    required this.countedCredits,
    required this.currentPoints,
    required this.remaining,
    required this.remainingCredits,
    required this.retakes,
    required this.belowTargetCount,
  });

  static const GoalPlan empty = GoalPlan(
    target: GoalPlannerService.defaultTarget,
    currentGpa: 0,
    countedCredits: 0,
    currentPoints: 0,
    remaining: [],
    remainingCredits: 0,
    retakes: [],
    belowTargetCount: 0,
  );

  bool get isEmpty => countedCredits == 0 && remainingCredits == 0;

  int get totalCredits => countedCredits + remainingCredits;

  /// Điểm trung bình các môn còn lại cần đạt, `null` khi không còn môn nào.
  double? get requiredAverage {
    if (remainingCredits == 0) return null;
    return (target * totalCredits - currentPoints) / remainingCredits;
  }

  /// GPA cao nhất có thể đạt nếu mọi môn còn lại đều 10 và không học lại.
  double get maxReachableGpa => totalCredits == 0
      ? 0
      : (currentPoints + 10.0 * remainingCredits) / totalCredits;

  GoalStatus get status {
    final required = requiredAverage;
    if (required == null) {
      return currentGpa >= target ? GoalStatus.secured : GoalStatus.needsRetake;
    }
    if (required <= 5.0) return GoalStatus.secured;
    if (required <= currentGpa) return GoalStatus.onTrack;
    if (required <= 10.0) return GoalStatus.stretch;
    return GoalStatus.needsRetake;
  }

  /// GPA cuối khoá dự kiến.
  ///
  /// [remainingAverage] là điểm trung bình giả định cho các môn còn lại,
  /// [retakeCodes] là các môn sẽ học cải thiện (lấy điểm giả định của
  /// [RetakeSuggestion]).
  double projectedGpa({
    required double remainingAverage,
    Set<String> retakeCodes = const {},
  }) {
    if (totalCredits == 0) return 0;
    var points = currentPoints + remainingAverage * remainingCredits;
    for (final r in retakes) {
      if (!retakeCodes.contains(r.code)) continue;
      points += (r.assumedGrade - r.currentGrade) * r.credits;
    }
    return points / totalCredits;
  }

  /// Ít môn cải thiện nhất (theo thứ tự lợi nhất trước) để GPA dự kiến chạm
  /// mục tiêu khi các môn còn lại đạt [remainingAverage]. Rỗng nếu không cần
  /// hoặc học lại hết cũng không đủ.
  List<RetakeSuggestion> minimalRetakes({required double remainingAverage}) {
    if (projectedGpa(remainingAverage: remainingAverage) >= target) {
      return const [];
    }
    final chosen = <RetakeSuggestion>[];
    final codes = <String>{};
    for (final r in retakes) {
      chosen.add(r);
      codes.add(r.code);
      if (projectedGpa(
            remainingAverage: remainingAverage,
            retakeCodes: codes,
          ) >=
          target) {
        return chosen;
      }
    }
    return const [];
  }

  /// Nhãn ngắn cho những chỗ chật (dải tóm tắt trên bảng học kỳ).
  String get shortStatusLabel => switch (status) {
    GoalStatus.secured => 'Đã chắc chắn',
    GoalStatus.onTrack => 'Đúng hướng',
    GoalStatus.stretch => 'Cần cố hơn',
    GoalStatus.needsRetake => 'Phải học cải thiện',
  };

  String get statusLabel => switch (status) {
    GoalStatus.secured => 'Đã nắm chắc mục tiêu',
    GoalStatus.onTrack => 'Đúng hướng — giữ phong độ là đạt',
    GoalStatus.stretch => 'Đạt được nếu học tốt hơn hiện tại',
    GoalStatus.needsRetake => 'Cần học cải thiện mới đạt',
  };

  /// Kế hoạch dạng văn bản để gửi kèm câu hỏi cho AI.
  String renderForPrompt() {
    final sb = StringBuffer()
      ..writeln(
        'Mục tiêu GPA tốt nghiệp: ${target.toStringAsFixed(1)}. GPA hiện tại '
        '${currentGpa.toStringAsFixed(2)} trên $countedCredits tín chỉ đã tính.',
      );
    final required = requiredAverage;
    if (required == null) {
      sb.writeln('Không còn môn nào phải học trong bảng điểm.');
    } else {
      sb.writeln(
        'Còn ${remaining.length} môn ($remainingCredits tín chỉ) chưa có điểm. '
        'Các môn này cần trung bình ${required.toStringAsFixed(2)} để đạt mục '
        'tiêu. Nếu tất cả đạt 10 thì GPA cao nhất là '
        '${maxReachableGpa.toStringAsFixed(2)}.',
      );
    }
    sb.writeln('Đánh giá: $statusLabel.');
    if (retakes.isNotEmpty) {
      sb.writeln(
        'Các môn đã qua nhưng dưới mục tiêu, xếp theo lợi ích nếu học cải '
        'thiện (giả định đạt điểm ghi trong ngoặc):',
      );
      for (final r in retakes) {
        sb.writeln(
          '- ${r.code} (${r.name}), ${r.credits} tín chỉ: '
          '${r.currentGrade.toStringAsFixed(1)} -> '
          '${r.assumedGrade.toStringAsFixed(1)}, GPA hiện tại tăng '
          '+${r.gainNow.toStringAsFixed(2)}'
          '${r.reasons.isEmpty ? '' : ' — ${r.reasons.join(', ')}'}',
        );
      }
    }
    return sb.toString();
  }
}
