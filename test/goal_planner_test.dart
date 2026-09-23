import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/models/graph_data.dart';
import 'package:se_knowledge/models/prerequisite.dart';
import 'package:se_knowledge/models/subject.dart';
import 'package:se_knowledge/models/transcript_entry.dart';
import 'package:se_knowledge/services/goal_planner_service.dart';

/// Kiểm thử phần lập kế hoạch đạt GPA mục tiêu và gợi ý học cải thiện.
void main() {
  final planner = GoalPlannerService.instance;
  final now = DateTime(2026, 9, 1);

  TranscriptEntry entry(
    String code, {
    double? grade,
    int credits = 3,
    SubjectStatus status = SubjectStatus.passed,
    int semesterOrder = 20243,
    bool graduationCondition = false,
  }) {
    return TranscriptEntry(
      subjectCode: code,
      subjectName: 'Môn $code',
      semesterLabel: 'Fall2024',
      semesterOrder: semesterOrder,
      credits: credits,
      grade: grade,
      status: status,
      isGraduationCondition: graduationCondition,
      countsTowardGpa: TranscriptEntry.countsTowardGpaByDefault(
        status: status,
        grade: grade,
        credits: credits,
        isGraduationCondition: graduationCondition,
      ),
      importedAt: now,
    );
  }

  Subject subject(int id, String code) => Subject(
    id: id,
    code: code,
    name: 'Môn $code',
    createdAt: now,
    updatedAt: now,
  );

  group('điểm trung bình cần đạt', () {
    // 12 tín chỉ đã qua, TB 7.0; 12 tín chỉ chưa học.
    final entries = [
      entry('PRF192', grade: 6.0),
      entry('MAE101', grade: 7.0),
      entry('CEA201', grade: 7.5),
      entry('CSI104', grade: 7.5),
      entry('PRO192', status: SubjectStatus.notStarted),
      entry('MAD101', status: SubjectStatus.notStarted),
      entry('CSD201', status: SubjectStatus.studying),
      entry('DBI202', status: SubjectStatus.notPassed, grade: 3.0),
      // Môn điều kiện tốt nghiệp không bao giờ vào GPA.
      entry(
        'VOV114',
        status: SubjectStatus.notStarted,
        graduationCondition: true,
      ),
    ];

    test('GPA hiện tại, số tín chỉ còn lại và TB cần đạt', () {
      final plan = planner.plan(entries, target: 8.0);
      expect(plan.currentGpa, closeTo(7.0, 1e-9));
      expect(plan.countedCredits, 12);
      expect(plan.remainingCredits, 12);
      expect(plan.remaining.map((r) => r.code), isNot(contains('VOV114')));
      // (8.0 × 24 − 84) / 12 = 9.0
      expect(plan.requiredAverage, closeTo(9.0, 1e-9));
      expect(plan.status, GoalStatus.stretch);
      expect(plan.maxReachableGpa, closeTo(8.5, 1e-9));
    });

    test('mục tiêu thấp hơn GPA hiện tại là đúng hướng', () {
      expect(planner.plan(entries, target: 6.5).status, GoalStatus.onTrack);
    });

    test('mục tiêu vượt cả điểm 10 thì phải học cải thiện', () {
      final plan = planner.plan(entries, target: 9.0);
      expect(plan.requiredAverage, greaterThan(10));
      expect(plan.status, GoalStatus.needsRetake);
    });

    test('môn trong khung mà bảng điểm chưa liệt kê cũng được tính', () {
      final plan = planner.plan(
        entries,
        target: 8.0,
        curriculumSubjects: const [
          PlannedSubject(code: 'SWP391', credits: 3),
          // Tiền tố môn điều kiện: không vào GPA.
          PlannedSubject(code: 'OTP101', credits: 3),
          // Đã có dòng trong bảng điểm: không đếm lần hai.
          PlannedSubject(code: 'PRO192', credits: 3),
        ],
      );
      expect(plan.remainingCredits, 15);
      expect(plan.remaining.map((r) => r.code), contains('SWP391'));
      expect(plan.remaining.map((r) => r.code), isNot(contains('OTP101')));
    });
  });

  group('học cải thiện', () {
    final entries = [
      entry('PRF192', grade: 6.0),
      entry('MAE101', grade: 7.0),
      entry('SSL101C', grade: 7.8, credits: 2),
      entry('CEA201', grade: 9.0),
      entry('PRO192', status: SubjectStatus.notStarted),
    ];
    final graph = GraphData(
      subjects: [
        subject(1, 'PRF192'),
        subject(2, 'PRO192'),
        subject(3, 'LAB211'),
        subject(4, 'MAE101'),
      ],
      edges: const [
        Prerequisite(subjectId: 2, prerequisiteId: 1),
        Prerequisite(subjectId: 3, prerequisiteId: 1),
      ],
    );

    test('chỉ gợi ý môn dưới mục tiêu, xếp theo GPA được thêm', () {
      final plan = planner.plan(entries, target: 8.0, graph: graph);
      expect(plan.retakes.map((r) => r.code), ['PRF192', 'MAE101', 'SSL101C']);
      final prf = plan.retakes.first;
      expect(prf.assumedGrade, 8.5);
      // (8.5 − 6.0) × 3 / 11 tín chỉ hiện tại
      expect(prf.gainNow, closeTo(7.5 / 11, 1e-9));
      expect(
        prf.reasons,
        containsAll(['môn lập trình', 'nền của 2 môn phía sau']),
      );
    });

    test('dự kiến GPA cộng đúng phần học lại', () {
      final plan = planner.plan(entries, target: 8.0, graph: graph);
      final base = plan.projectedGpa(remainingAverage: 8.0);
      final withRetake = plan.projectedGpa(
        remainingAverage: 8.0,
        retakeCodes: {'PRF192'},
      );
      // Mẫu số gồm cả 3 tín chỉ còn lại: 14.
      expect(withRetake - base, closeTo(7.5 / 14, 1e-9));
    });

    test('số môn cải thiện tối thiểu để chạm mục tiêu', () {
      final plan = planner.plan(entries, target: 8.0, graph: graph);
      final minimal = plan.minimalRetakes(remainingAverage: 8.0);
      expect(minimal.map((r) => r.code), ['PRF192']);
      expect(
        plan.projectedGpa(
          remainingAverage: 8.0,
          retakeCodes: {for (final r in minimal) r.code},
        ),
        greaterThanOrEqualTo(8.0),
      );
    });

    test('học lại nhiều lần chỉ tính lần qua mới nhất', () {
      final plan = planner.plan([
        entry('PRF192', grade: 5.0, semesterOrder: 20231),
        entry('PRF192', grade: 8.0, semesterOrder: 20241),
      ], target: 8.0);
      expect(plan.currentGpa, 8.0);
      expect(plan.retakes, isEmpty);
    });
  });

  test('ngữ cảnh gửi AI có đủ mục tiêu, TB cần đạt và môn nên cải thiện', () {
    final plan = planner.plan([
      entry('PRF192', grade: 6.0),
      entry('PRO192', status: SubjectStatus.notStarted),
    ], target: 8.0);
    final text = plan.renderForPrompt();
    expect(text, contains('Mục tiêu GPA tốt nghiệp: 8.0'));
    expect(text, contains('cần trung bình 10.00'));
    expect(text, contains('PRF192'));
  });
}
