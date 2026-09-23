import 'package:flutter/material.dart';

import '../../models/curriculum.dart';
import '../../models/subject.dart';
import '../../models/transcript_entry.dart';
import '../../services/academic_analytics_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';
import 'curriculum_form_dialog.dart';
import 'fap_inbox_import.dart';
import 'grade_status.dart';

/// Màn hình "đầu" của mọi khung chương trình: liệt kê tất cả các khung dưới
/// dạng **danh sách** hoặc **biểu đồ**, bấm vào một khung thì mở màn hình của
/// khung đó (sơ đồ môn / bảng học kỳ / mạng tri thức).
///
/// Đứng ngoài cùng vì nó trả lời câu hỏi ở tầng trên cả môn học: "trong CSDL
/// đang có những chương trình nào, mỗi chương trình nặng về mảng gì, và mình
/// đã đi được bao xa trong chương trình của mình".
class CurriculaOverviewPage extends StatefulWidget {
  /// Chuyển sang màn hình khung (tab Bản đồ) sau khi đã chọn khung và góc
  /// nhìn.
  final VoidCallback onOpenCurriculum;

  const CurriculaOverviewPage({super.key, required this.onOpenCurriculum});

  @override
  State<CurriculaOverviewPage> createState() => _CurriculaOverviewPageState();
}

class _CurriculaOverviewPageState extends State<CurriculaOverviewPage> {
  bool _chart = false;

  void _open(CurriculumGroup group, CurriculumView view) {
    AppState.instance.openCurriculum(group.code, view: view);
    widget.onOpenCurriculum();
  }

  Future<void> _createCurriculum() async {
    final data = await CurriculumFormDialog.show(context);
    if (data == null || !mounted) return;
    try {
      await AppState.instance.addCurriculum(
        code: data['code']?.toString() ?? '',
        name: data['name']?.toString() ?? '',
        major: data['major']?.toString() ?? '',
        totalCredits:
            int.tryParse(data['total_credits']?.toString() ?? '') ?? 0,
        decisionNo: data['decision_no']?.toString() ?? '',
        description: data['description']?.toString() ?? '',
      );
      if (mounted) Ui.success(context, 'Đã tạo khung chương trình mới.');
    } catch (e) {
      if (mounted) Ui.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final summaries = [
          for (final g in state.curriculumGroups) _Summary.of(g, state),
        ];
        final real = summaries.where((s) => !s.group.isUnassigned).length;
        final syllabi = summaries.fold<int>(0, (s, x) => s + x.syllabusCount);

        return Column(
          children: [
            PageHeader(
              title: 'Khung chương trình',
              subtitle:
                  '$real khung · ${state.stats['subjects'] ?? 0} môn trong CSDL '
                  '· $syllabi môn đã có syllabus',
              actions: [
                _ModeToggle(
                  chart: _chart,
                  onChanged: (v) => setState(() => _chart = v),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 30,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_download_outlined, size: 15),
                    label: const Text('Nhập từ fap_inbox'),
                    onPressed: () => FapInboxImport.run(context),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 30,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('Tạo khung'),
                    onPressed: _createCurriculum,
                  ),
                ),
              ],
            ),
            Expanded(
              child: summaries.isEmpty
                  ? EmptyState(
                      icon: Icons.dashboard_outlined,
                      title: 'Chưa có khung chương trình nào',
                      message:
                          'Tải trang "Curriculum Details" trên FLM bằng extension '
                          'rồi bấm "Nhập từ fap_inbox", hoặc tạo một khung trống.',
                      action: OutlinedButton.icon(
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('Nhập từ fap_inbox'),
                        onPressed: () => FapInboxImport.run(context),
                      ),
                    )
                  : _chart
                  ? _ChartView(summaries: summaries, onOpen: _open)
                  : _ListView(summaries: summaries, onOpen: _open),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// SỐ LIỆU CỦA MỘT KHUNG
// ============================================================================

class _Summary {
  final CurriculumGroup group;
  final List<Subject> subjects;
  final List<int> terms;
  final Map<int, int> creditsByTerm;
  final Map<int, int> passedCreditsByTerm;
  final Map<int, int> countByTerm;
  final Map<String, int> creditsByDomain;
  final Map<String, int> countByDomain;
  final int credits;
  final int syllabusCount;
  final int programmingCount;

  final bool hasGrades;
  final int passedCredits;
  final int passedCount;
  final int reachedCount;
  final int belowTargetCount;
  final int failedCount;
  final int studyingCount;
  final double? gpa;

  const _Summary({
    required this.group,
    required this.subjects,
    required this.terms,
    required this.creditsByTerm,
    required this.passedCreditsByTerm,
    required this.countByTerm,
    required this.creditsByDomain,
    required this.countByDomain,
    required this.credits,
    required this.syllabusCount,
    required this.programmingCount,
    required this.hasGrades,
    required this.passedCredits,
    required this.passedCount,
    required this.reachedCount,
    required this.belowTargetCount,
    required this.failedCount,
    required this.studyingCount,
    required this.gpa,
  });

  factory _Summary.of(CurriculumGroup group, AppState state) {
    final analytics = AcademicAnalyticsService.instance;
    final programming = state.programmingCodes;
    final target = state.targetGpa;

    final subjects = [
      for (final entry in group.semesters.entries) ...entry.value,
    ];
    final creditsByTerm = <int, int>{};
    final passedByTerm = <int, int>{};
    final countByTerm = <int, int>{};
    final creditsByDomain = <String, int>{};
    final countByDomain = <String, int>{};
    var credits = 0, syllabi = 0, prog = 0;
    var passedCredits = 0, passed = 0, reached = 0, below = 0;
    var failed = 0, studying = 0;
    var points = 0.0;
    var gpaCredits = 0;

    for (final entry in group.semesters.entries) {
      final term = entry.key;
      for (final s in entry.value) {
        credits += s.credits;
        creditsByTerm[term] = (creditsByTerm[term] ?? 0) + s.credits;
        countByTerm[term] = (countByTerm[term] ?? 0) + 1;
        final domain = analytics.domainOf(s.code);
        creditsByDomain[domain] = (creditsByDomain[domain] ?? 0) + s.credits;
        countByDomain[domain] = (countByDomain[domain] ?? 0) + 1;
        if (state.hasSyllabusFor(s.id)) syllabi++;
        if (programming.contains(s.code.toUpperCase())) prog++;

        final grade = state.gradeOf(s.code);
        switch (targetStatusOf(grade, target)) {
          case TargetStatus.reached:
            reached++;
          case TargetStatus.belowTarget:
            below++;
          case TargetStatus.failed:
            failed++;
          case TargetStatus.studying:
            studying++;
          case TargetStatus.passedNoGrade:
          case TargetStatus.notStarted:
            break;
        }
        if (grade?.status == SubjectStatus.passed) {
          passed++;
          passedCredits += s.credits;
          passedByTerm[term] = (passedByTerm[term] ?? 0) + s.credits;
          final g = grade!.grade;
          if (g != null && grade.countsTowardGpa && grade.credits > 0) {
            points += g * grade.credits;
            gpaCredits += grade.credits;
          }
        }
      }
    }

    return _Summary(
      group: group,
      subjects: subjects,
      terms: creditsByTerm.keys.toList()..sort(),
      creditsByTerm: creditsByTerm,
      passedCreditsByTerm: passedByTerm,
      countByTerm: countByTerm,
      creditsByDomain: creditsByDomain,
      countByDomain: countByDomain,
      credits: credits,
      syllabusCount: syllabi,
      programmingCount: prog,
      hasGrades: state.hasTranscript,
      passedCredits: passedCredits,
      passedCount: passed,
      reachedCount: reached,
      belowTargetCount: below,
      failedCount: failed,
      studyingCount: studying,
      gpa: gpaCredits == 0 ? null : points / gpaCredits,
    );
  }

  String get title => group.isUnassigned ? 'Môn ngoài khung' : group.code;

  String get termRange {
    if (terms.isEmpty) return 'chưa có kỳ';
    return terms.first == terms.last
        ? 'HK${terms.first}'
        : 'HK${terms.first}–HK${terms.last}';
  }

  /// Nhóm năng lực theo thứ tự cố định của bảng màu, "Khác" luôn cuối.
  List<String> get domains => [
    for (final d in AppColors.domainOrder)
      if (creditsByDomain.containsKey(d)) d,
    for (final d in creditsByDomain.keys)
      if (!AppColors.domainOrder.contains(d)) d,
  ];
}

// ============================================================================
// DANH SÁCH
// ============================================================================

class _ListView extends StatelessWidget {
  final List<_Summary> summaries;
  final void Function(CurriculumGroup, CurriculumView) onOpen;

  const _ListView({required this.summaries, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final domains = <String>{for (final s in summaries) ...s.domains};
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _DomainLegend(domains: domains),
        const SizedBox(height: 12),
        for (final s in summaries) ...[
          _CurriculumCard(summary: s, onOpen: onOpen),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CurriculumCard extends StatefulWidget {
  final _Summary summary;
  final void Function(CurriculumGroup, CurriculumView) onOpen;

  const _CurriculumCard({required this.summary, required this.onOpen});

  @override
  State<_CurriculumCard> createState() => _CurriculumCardState();
}

class _CurriculumCardState extends State<_CurriculumCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final g = s.group;
    final name = g.isUnassigned
        ? 'Các môn chưa gắn vào khung chương trình nào'
        : (g.name.isNotEmpty ? g.name : g.major);

    final facts = <String>[
      '${s.subjects.length} môn',
      '${s.credits} TC'
          '${g.totalCredits > 0 && g.totalCredits != s.credits ? ' (khung ghi ${g.totalCredits})' : ''}',
      s.termRange,
      'syllabus ${s.syllabusCount}/${s.subjects.length}',
      if (s.programmingCount > 0) '${s.programmingCount} môn có lập trình',
    ];

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: () => widget.onOpen(g, CurriculumView.board),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered
                  ? AppColors.primary.withValues(alpha: 0.6)
                  : AppColors.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      (g.isUnassigned ? AppColors.textHint : AppColors.primary)
                          .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  g.isUnassigned
                      ? Icons.folder_special_outlined
                      : Icons.school_outlined,
                  size: 20,
                  color: g.isUnassigned
                      ? AppColors.textHint
                      : AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (s.gpa != null) ...[
                          const SizedBox(width: 10),
                          _Pill(
                            text: 'GPA ${s.gpa!.toStringAsFixed(2)}',
                            color: AppColors.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      facts.join('  ·  '),
                      style: TextStyle(fontSize: 12, color: AppColors.textHint),
                    ),
                    const SizedBox(height: 12),
                    _SemesterStrip(summary: s),
                    const SizedBox(height: 10),
                    _DomainBar(summary: s, height: 10),
                    if (s.hasGrades) ...[
                      const SizedBox(height: 12),
                      _ProgressLine(summary: s),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 32,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.view_week_outlined, size: 16),
                      label: const Text('Bảng học kỳ'),
                      onPressed: () => widget.onOpen(g, CurriculumView.board),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SmallAction(
                        icon: Icons.hub_outlined,
                        tooltip: 'Sơ đồ môn học (tiên quyết)',
                        onTap: () => widget.onOpen(g, CurriculumView.graph),
                      ),
                      _SmallAction(
                        icon: Icons.psychology_outlined,
                        tooltip: 'Mạng tri thức (khái niệm trích từ syllabus)',
                        onTap: () => widget.onOpen(g, CurriculumView.knowledge),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dải học kỳ: mỗi ô rộng theo số tín chỉ của kỳ; khi đã có bảng điểm, phần
/// tô đậm trong ô là tín chỉ đã qua — nhìn một lượt là thấy mình đang ở đâu.
class _SemesterStrip extends StatelessWidget {
  final _Summary summary;

  const _SemesterStrip({required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s.terms.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          for (var i = 0; i < s.terms.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              flex: (s.creditsByTerm[s.terms[i]] ?? 0).clamp(2, 60),
              child: _TermBlock(
                term: s.terms[i],
                credits: s.creditsByTerm[s.terms[i]] ?? 0,
                passed: s.passedCreditsByTerm[s.terms[i]] ?? 0,
                count: s.countByTerm[s.terms[i]] ?? 0,
                showProgress: s.hasGrades,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TermBlock extends StatelessWidget {
  final int term;
  final int credits;
  final int passed;
  final int count;
  final bool showProgress;

  const _TermBlock({
    required this.term,
    required this.credits,
    required this.passed,
    required this.count,
    required this.showProgress,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = credits == 0 ? 0.0 : (passed / credits).clamp(0.0, 1.0);
    final track = AppColors.primary.withValues(alpha: 0.12);
    final fill = AppColors.primary.withValues(alpha: 0.45);
    return Tooltip(
      message:
          'HK$term: $count môn, $credits tín chỉ'
          '${showProgress ? ' — đã qua $passed TC' : ''}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LayoutBuilder(
          builder: (context, c) {
            final label = 'HK$term';
            final fits = c.maxWidth >= 34;
            return Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: track)),
                if (showProgress && ratio > 0)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: c.maxWidth * ratio,
                    child: ColoredBox(color: fill),
                  ),
                if (fits)
                  Center(
                    child: Text(
                      c.maxWidth >= 58 ? '$label · $credits' : label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Cột chồng tín chỉ theo nhóm năng lực. Các đoạn cách nhau 2px màu nền
/// thay vì viền, và luôn xếp theo thứ tự cố định của bảng màu.
class _DomainBar extends StatelessWidget {
  final _Summary summary;
  final double height;

  const _DomainBar({required this.summary, this.height = 10});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final domains = s.domains;
    if (s.credits == 0) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < domains.length; i++) ...[
            if (i > 0)
              SizedBox(width: 2, child: ColoredBox(color: AppColors.surface)),
            Expanded(
              flex: (s.creditsByDomain[domains[i]] ?? 0).clamp(1, 1000),
              child: Tooltip(
                message:
                    '${domains[i]}: ${s.creditsByDomain[domains[i]]} TC '
                    '(${(100 * (s.creditsByDomain[domains[i]] ?? 0) / s.credits).round()}%) '
                    '· ${s.countByDomain[domains[i]]} môn',
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.domainColor(domains[i]),
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(i == 0 ? 4 : 0),
                      right: Radius.circular(i == domains.length - 1 ? 4 : 0),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  final _Summary summary;

  const _ProgressLine({required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final ratio = s.credits == 0 ? 0.0 : s.passedCredits / s.credits;
    final target = AppState.instance.targetGpa.toStringAsFixed(1);
    return Wrap(
      spacing: 0,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 190,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Đã qua ${s.passedCredits}/${s.credits} TC (${(ratio * 100).round()}%)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 14),
        if (s.reachedCount > 0)
          TargetStatusChip(
            status: TargetStatus.reached,
            text: '${s.reachedCount} môn ≥ $target',
          ),
        if (s.belowTargetCount > 0) ...[
          const SizedBox(width: 6),
          TargetStatusChip(
            status: TargetStatus.belowTarget,
            text: '${s.belowTargetCount} môn < $target',
          ),
        ],
        if (s.failedCount > 0) ...[
          const SizedBox(width: 6),
          TargetStatusChip(
            status: TargetStatus.failed,
            text: '${s.failedCount} chưa qua',
          ),
        ],
        if (s.studyingCount > 0) ...[
          const SizedBox(width: 6),
          TargetStatusChip(
            status: TargetStatus.studying,
            text: '${s.studyingCount} đang học',
          ),
        ],
      ],
    );
  }
}

class _DomainLegend extends StatelessWidget {
  final Set<String> domains;

  const _DomainLegend({required this.domains});

  @override
  Widget build(BuildContext context) {
    final ordered = [
      for (final d in AppColors.domainOrder)
        if (domains.contains(d)) d,
      for (final d in domains)
        if (!AppColors.domainOrder.contains(d)) d,
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Nhóm kiến thức (theo tín chỉ):',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        for (final d in ordered)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.domainColor(d),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                d,
                style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
              ),
            ],
          ),
      ],
    );
  }
}

// ============================================================================
// BIỂU ĐỒ
// ============================================================================

class _ChartView extends StatelessWidget {
  final List<_Summary> summaries;
  final void Function(CurriculumGroup, CurriculumView) onOpen;

  const _ChartView({required this.summaries, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final domains = <String>{for (final s in summaries) ...s.domains};
    final maxCredits = summaries.fold<int>(
      1,
      (m, s) => s.credits > m ? s.credits : m,
    );
    final maxTerm = summaries.fold<int>(1, (m, s) {
      for (final c in s.creditsByTerm.values) {
        if (c > m) m = c;
      }
      return m;
    });
    final hasGrades = summaries.any((s) => s.hasGrades);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _ChartCard(
          title: 'Cơ cấu tín chỉ theo nhóm kiến thức',
          subtitle:
              'Mỗi thanh là một khung, dài theo tổng tín chỉ. Rê chuột lên một '
              'đoạn để xem số tín chỉ và số môn; bấm vào tên khung để mở.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DomainLegend(domains: domains),
              const SizedBox(height: 14),
              for (final s in summaries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 150,
                        child: InkWell(
                          onTap: () => onOpen(s.group, CurriculumView.board),
                          child: Text(
                            s.title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final width =
                                (c.maxWidth - 70) * s.credits / maxCredits;
                            return Row(
                              children: [
                                SizedBox(
                                  width: width.clamp(4.0, c.maxWidth),
                                  child: _DomainBar(summary: s, height: 18),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${s.credits} TC',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ChartCard(
          title: 'Tín chỉ theo học kỳ',
          subtitle: hasGrades
              ? 'Cùng một thang cho mọi khung để so sánh được bằng mắt. Phần '
                    'đậm là tín chỉ đã qua, phần nhạt là tín chỉ còn lại.'
              : 'Cùng một thang cho mọi khung để so sánh được bằng mắt.',
          child: Wrap(
            spacing: 28,
            runSpacing: 20,
            children: [
              for (final s in summaries)
                _TermColumns(summary: s, maxCredits: maxTerm),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ChartCard(
          title: 'Bảng số liệu',
          subtitle:
              'Cùng số liệu với hai biểu đồ trên, đọc được không cần màu.',
          child: _DataTableView(summaries: summaries, domains: domains),
        ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// Biểu đồ cột nhỏ của một khung: mỗi cột một kỳ, cao theo tín chỉ. Cột
/// không dày quá 22px và bo 4px ở đầu cột, gốc vuông trên đường nền.
class _TermColumns extends StatelessWidget {
  final _Summary summary;
  final int maxCredits;

  const _TermColumns({required this.summary, required this.maxCredits});

  static const double plotHeight = 120;

  /// Phần đã qua (đậm) nằm dưới, phần còn lại (nhạt) nằm trên. Đoạn nào
  /// bằng 0 thì bỏ hẳn — `Expanded` không nhận hệ số 0.
  Widget _stack({
    required int remaining,
    required int passed,
    required Color track,
  }) {
    // Kéo giãn theo chiều ngang: ô màu không có con thì co về bề rộng 0.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (remaining > 0)
          Expanded(
            flex: remaining,
            child: ColoredBox(color: track),
          ),
        if (passed > 0)
          Expanded(
            flex: passed,
            child: const ColoredBox(color: AppColors.primary),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final peak = s.creditsByTerm.values.fold<int>(0, (m, c) => c > m ? c : m);
    final track = AppColors.primary.withValues(alpha: 0.28);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          s.title,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        // Chiều cao cố định cho mọi biểu đồ con: các khung dùng chung một
        // thang, nên đường nền cũng phải nằm cùng một độ cao.
        SizedBox(
          height: plotHeight + 42,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final term in s.terms)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Chỉ ghi số ở cột cao nhất; các cột khác đọc bằng trục
                      // chung, tooltip và bảng số liệu bên dưới.
                      SizedBox(
                        height: 16,
                        child: (s.creditsByTerm[term] ?? 0) == peak
                            ? Text(
                                '$peak',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: AppColors.textSecondary,
                                ),
                              )
                            : null,
                      ),
                      Tooltip(
                        message:
                            'HK$term: ${s.countByTerm[term]} môn, '
                            '${s.creditsByTerm[term]} TC'
                            '${s.hasGrades ? ' — đã qua ${s.passedCreditsByTerm[term] ?? 0} TC' : ''}',
                        child: SizedBox(
                          width: 22,
                          height:
                              plotHeight *
                              (s.creditsByTerm[term] ?? 0) /
                              maxCredits,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                            child: _stack(
                              remaining:
                                  (s.creditsByTerm[term] ?? 0) -
                                  (s.passedCreditsByTerm[term] ?? 0),
                              passed: s.passedCreditsByTerm[term] ?? 0,
                              track: track,
                            ),
                          ),
                        ),
                      ),
                      Container(height: 1, width: 30, color: AppColors.border),
                      const SizedBox(height: 4),
                      Text(
                        'HK$term',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DataTableView extends StatelessWidget {
  final List<_Summary> summaries;
  final Set<String> domains;

  const _DataTableView({required this.summaries, required this.domains});

  @override
  Widget build(BuildContext context) {
    final ordered = [
      for (final d in AppColors.domainOrder)
        if (domains.contains(d)) d,
      for (final d in domains)
        if (!AppColors.domainOrder.contains(d)) d,
    ];
    final hasGrades = summaries.any((s) => s.hasGrades);
    final header = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
    );
    final cell = TextStyle(fontSize: 12.5, color: AppColors.textPrimary);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 38,
        columnSpacing: 22,
        columns: [
          DataColumn(label: Text('Khung', style: header)),
          DataColumn(label: Text('Môn', style: header), numeric: true),
          DataColumn(label: Text('Tín chỉ', style: header), numeric: true),
          DataColumn(label: Text('Syllabus', style: header), numeric: true),
          for (final d in ordered)
            DataColumn(label: Text(d, style: header), numeric: true),
          if (hasGrades) ...[
            DataColumn(
              label: Text('Đã qua (TC)', style: header),
              numeric: true,
            ),
            DataColumn(label: Text('GPA', style: header), numeric: true),
          ],
        ],
        rows: [
          for (final s in summaries)
            DataRow(
              cells: [
                DataCell(
                  Text(
                    s.title,
                    style: cell.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                DataCell(Text('${s.subjects.length}', style: cell)),
                DataCell(Text('${s.credits}', style: cell)),
                DataCell(Text('${s.syllabusCount}', style: cell)),
                for (final d in ordered)
                  DataCell(Text('${s.creditsByDomain[d] ?? 0}', style: cell)),
                if (hasGrades) ...[
                  DataCell(Text('${s.passedCredits}', style: cell)),
                  DataCell(Text(s.gpa?.toStringAsFixed(2) ?? '—', style: cell)),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// NHỎ LẺ
// ============================================================================

class _ModeToggle extends StatelessWidget {
  final bool chart;
  final ValueChanged<bool> onChanged;

  const _ModeToggle({required this.chart, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget item(bool value, IconData icon, String label) {
      final selected = chart == value;
      return InkWell(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        item(false, Icons.view_agenda_outlined, 'Danh sách'),
        const SizedBox(width: 6),
        item(true, Icons.bar_chart, 'Biểu đồ'),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;

  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _SmallAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      color: AppColors.textSecondary,
      splashRadius: 16,
      onPressed: onTap,
    );
  }
}
