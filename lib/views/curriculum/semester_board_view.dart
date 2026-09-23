import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/curriculum.dart';
import '../../models/graph_data.dart';
import '../../models/subject.dart';
import '../../models/transcript_entry.dart';
import '../../services/academic_analytics_service.dart';
import '../../services/kanban_board_builder.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';
import 'grade_status.dart';

/// Cách tô màu thẻ môn trên bảng học kỳ.
enum BoardColorMode {
  /// Viền theo học kỳ, giống màu node trên sơ đồ.
  semester,

  /// Thang điểm 5 mức của app (Xuất sắc → Chưa qua).
  grade,

  /// Xanh/đỏ so với GPA mục tiêu — trả lời "môn nào nên học cải thiện".
  target,

  /// Theo nhóm kiến thức (tiền tố mã môn).
  domain,
}

/// Góc nhìn thứ hai của một khung: **bảng học kỳ** HK0/HK1 → HK9 xếp ngang,
/// mỗi môn là một thẻ có mã môn, tên môn, tín chỉ và điểm.
///
/// Khác sơ đồ tiên quyết ở chỗ nó đọc được theo trình tự thời gian như một
/// tấm bảng kế hoạch: cột nào cũng thu gọn được để nhìn nhiều kỳ một lúc, và
/// bấm một môn thì các môn nó cần học trước / mở ra được đánh dấu ngay trên
/// bảng thay vì phải nhìn mũi tên chằng chịt.
class SemesterBoardView extends StatefulWidget {
  final GraphData data;

  const SemesterBoardView({super.key, required this.data});

  @override
  State<SemesterBoardView> createState() => _SemesterBoardViewState();
}

class _SemesterBoardViewState extends State<SemesterBoardView> {
  /// Giữ trạng thái thu gọn theo từng khung qua các lần đổi góc nhìn: đổi
  /// sang sơ đồ rồi quay lại mà các cột mở bung hết thì rất khó chịu.
  static final Map<String, Set<int>> _collapsedByCurriculum = {};
  static BoardColorMode? _lastMode;

  final ScrollController _hScroll = ScrollController();
  final TextEditingController _search = TextEditingController();

  BoardColorMode _mode = BoardColorMode.semester;
  bool _onlyProgramming = false;

  String get _scopeKey => AppState.instance.activeCurriculumCode ?? '*';
  Set<int> get _collapsed =>
      _collapsedByCurriculum.putIfAbsent(_scopeKey, () => <int>{});

  @override
  void initState() {
    super.initState();
    _mode =
        _lastMode ??
        (AppState.instance.hasTranscript
            ? BoardColorMode.target
            : BoardColorMode.semester);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Tri thức cho biết môn nào có nội dung lập trình dù không mang mã PRx
      // — dựng sẵn để bộ lọc "Môn lập trình" đọc được cả syllabus.
      if (mounted) AppState.instance.ensureKnowledge();
    });
  }

  @override
  void dispose() {
    _hScroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _setMode(BoardColorMode mode) {
    setState(() => _mode = mode);
    _lastMode = mode;
  }

  Map<int, List<Subject>> _bySemester() {
    final map = <int, List<Subject>>{};
    for (final s in widget.data.subjects) {
      map.putIfAbsent(s.semester, () => []).add(s);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.code.compareTo(b.code));
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final bySemester = _bySemester();
        final terms = bySemester.keys.toList()..sort();
        final query = _search.text.trim().toLowerCase();
        final programming = state.programmingCodes;

        final selectedId = state.selectedSubjectId;
        final prereqIds = <int>{};
        final dependentIds = <int>{};
        if (selectedId != null) {
          for (final e in widget.data.edges) {
            if (e.subjectId == selectedId) prereqIds.add(e.prerequisiteId);
            if (e.prerequisiteId == selectedId) dependentIds.add(e.subjectId);
          }
        }

        return Column(
          children: [
            _Toolbar(
              mode: _mode,
              hasTranscript: state.hasTranscript,
              onlyProgramming: _onlyProgramming,
              programmingCount: widget.data.subjects
                  .where((s) => programming.contains(s.code.toUpperCase()))
                  .length,
              search: _search,
              allCollapsed: terms.isNotEmpty && terms.every(_collapsed.contains),
              onModeChanged: _setMode,
              onToggleProgramming: () =>
                  setState(() => _onlyProgramming = !_onlyProgramming),
              onSearchChanged: () => setState(() {}),
              onToggleCollapseAll: () {
                setState(() {
                  final allCollapsed = terms.isNotEmpty && terms.every(_collapsed.contains);
                  if (allCollapsed) {
                    _collapsed.clear();
                  } else {
                    _collapsed.addAll(terms);
                  }
                });
              },
              onExport: () => _export(bySemester),
            ),
            if (state.hasTranscript)
              const _GoalStrip(),
            Expanded(
              child: terms.isEmpty
                  ? const EmptyState(
                      icon: Icons.view_week_outlined,
                      title: 'Khung này chưa có môn nào',
                      message:
                          'Nạp khung chương trình từ fap_inbox hoặc thêm môn '
                          'để xem bảng học kỳ.',
                    )
                  : LayoutBuilder(
                      builder: (context, c) => Scrollbar(
                        controller: _hScroll,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _hScroll,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                          child: SizedBox(
                            height: c.maxHeight - 26,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final term in terms)
                                  _collapsed.contains(term)
                                      ? _CollapsedColumn(
                                          term: term,
                                          subjects: bySemester[term]!,
                                          onExpand: () => setState(
                                            () => _collapsed.remove(term),
                                          ),
                                        )
                                      : _SemesterColumn(
                                          term: term,
                                          subjects: bySemester[term]!,
                                          mode: _mode,
                                          query: query,
                                          onlyProgramming: _onlyProgramming,
                                          programming: programming,
                                          selectedId: selectedId,
                                          prereqIds: prereqIds,
                                          dependentIds: dependentIds,
                                          onCollapse: () => setState(
                                            () => _collapsed.add(term),
                                          ),
                                        ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            _BoardLegend(
              mode: _mode,
              hasSelection:
                  selectedId != null &&
                  (prereqIds.isNotEmpty || dependentIds.isNotEmpty),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // XUẤT BOARD .MD
  // ------------------------------------------------------------------

  Future<void> _export(Map<int, List<Subject>> bySemester) async {
    final state = AppState.instance;
    final group =
        state.activeCurriculumGroup ??
        CurriculumGroup(
          code: 'TOAN_BO',
          name: 'Toàn bộ môn trong CSDL',
          major: '',
          semesters: bySemester,
          totalSubjects: widget.data.subjects.length,
        );
    final collapsed = {..._collapsed};
    final markdown = state.buildBoardMarkdown(
      group,
      collapsedSemesters: collapsed,
    );
    final fileName = KanbanBoardBuilder.fileNameFor(
      group.isUnassigned ? 'NGOAI_KHUNG' : group.code,
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bảng học kỳ dạng Markdown'),
        content: SizedBox(
          width: 680,
          height: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'File "$fileName" theo định dạng board của plugin Obsidian '
                'Kanban: mỗi học kỳ là một cột, mỗi môn là một thẻ, môn đã qua '
                'được tích sẵn, thẻ tô màu theo mục tiêu GPA. Không cài plugin '
                'thì nó vẫn là một danh sách Markdown có link [[MÃ MÔN]].',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      markdown,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 12,
                        height: 1.45,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Chép Markdown'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: markdown));
              if (ctx.mounted) Ui.success(ctx, 'Đã chép nội dung board.');
            },
          ),
          Tooltip(
            message: state.hasVault
                ? 'Ghi vào Vault, cạnh các file môn học'
                : 'Chọn Obsidian Vault ở tab Vault trước',
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save_alt, size: 16),
              label: const Text('Ghi ra Vault'),
              onPressed: !state.hasVault
                  ? null
                  : () async {
                      try {
                        final path = await state.exportBoardToVault(
                          group,
                          collapsedSemesters: collapsed,
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (mounted) Ui.success(context, 'Đã ghi $path');
                      } catch (e) {
                        if (ctx.mounted) Ui.error(ctx, e);
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// THANH CÔNG CỤ
// ============================================================================

class _Toolbar extends StatelessWidget {
  final BoardColorMode mode;
  final bool hasTranscript;
  final bool onlyProgramming;
  final int programmingCount;
  final TextEditingController search;
  final bool allCollapsed;
  final ValueChanged<BoardColorMode> onModeChanged;
  final VoidCallback onToggleProgramming;
  final VoidCallback onSearchChanged;
  final VoidCallback onToggleCollapseAll;
  final VoidCallback onExport;

  const _Toolbar({
    required this.mode,
    required this.hasTranscript,
    required this.onlyProgramming,
    required this.programmingCount,
    required this.search,
    required this.allCollapsed,
    required this.onModeChanged,
    required this.onToggleProgramming,
    required this.onSearchChanged,
    required this.onToggleCollapseAll,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tô màu:',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 8),
              for (final (value, label, tip) in [
                (BoardColorMode.semester, 'Học kỳ', 'Vạch màu theo học kỳ'),
                (
                  BoardColorMode.target,
                  'Mục tiêu',
                  hasTranscript
                      ? 'Xanh: đạt GPA mục tiêu · Cam: nên cải thiện · Đỏ: chưa qua'
                      : 'Nhập bảng điểm ở tab Học lực để dùng',
                ),
                (
                  BoardColorMode.grade,
                  'Điểm',
                  hasTranscript
                      ? 'Thang 5 mức: Xuất sắc → Chưa qua'
                      : 'Nhập bảng điểm ở tab Học lực để dùng',
                ),
                (
                  BoardColorMode.domain,
                  'Nhóm KT',
                  'Nhóm kiến thức theo tiền tố mã môn',
                ),
              ])
                _ModePill(
                  label: label,
                  tooltip: tip,
                  selected: mode == value,
                  enabled:
                      hasTranscript ||
                      value == BoardColorMode.semester ||
                      value == BoardColorMode.domain,
                  onTap: () => onModeChanged(value),
                ),
              const SizedBox(width: 10),
              FilterChip(
                avatar: const Icon(Icons.code, size: 15),
                label: Text('Lập trình ($programmingCount)'),
                labelStyle: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(fontSize: 11.5),
                visualDensity: VisualDensity.compact,
                selected: onlyProgramming,
                showCheckmark: false,
                tooltip:
                    'Làm nổi các môn liên quan tới lập trình — theo mã môn và theo '
                    'nội dung syllabus (IoT, Hệ điều hành cũng có lập trình).',
                onSelected: (_) => onToggleProgramming(),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 170,
                height: 32,
                child: TextField(
                  controller: search,
                  onChanged: (_) => onSearchChanged(),
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Tìm mã hoặc tên môn...',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: AppColors.textHint,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 32,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.view_kanban_outlined, size: 15),
                  label: const Text(
                    'Xuất .md dạng board',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      width: 0.8,
                    ),
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: onExport,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Nút chọn cách tô màu — gọn hơn `SegmentedButton` để thanh công cụ vừa
/// một hàng ở màn hình laptop.
class _ModePill extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ModePill({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: !enabled
                    ? AppColors.textHint
                    : selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dải tóm tắt tiến trình học tập so với mục tiêu, ngay trên bảng.
class _GoalStrip extends StatelessWidget {
  const _GoalStrip();

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final plan = state.goalPlan;
    final required = plan.requiredAverage;
    final ratio = plan.totalCredits == 0
        ? 0.0
        : plan.countedCredits / plan.totalCredits;
    final statusColor = plan.isEmpty
        ? AppColors.textHint
        : goalStatusColor(plan.status);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_outlined, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            'Mục tiêu',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<double>(
            tooltip: 'Đổi GPA mục tiêu',
            initialValue: state.targetGpa,
            onSelected: state.setTargetGpa,
            itemBuilder: (_) => [
              for (final v in const [7.0, 7.5, 8.0, 8.5, 9.0])
                PopupMenuItem(value: v, child: Text(v.toStringAsFixed(1))),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.targetGpa.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'GPA ${plan.currentGpa.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${plan.countedCredits}/${plan.totalCredits} TC tính GPA',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 16),
          Icon(Icons.circle, size: 9, color: statusColor),
          const SizedBox(width: 6),
          Flexible(
            child: Tooltip(
              message: plan.statusLabel,
              child: Text(
                required == null
                    ? plan.shortStatusLabel
                    : '${plan.shortStatusLabel} · cần TB '
                          '${required > 10 ? '> 10' : required.toStringAsFixed(2)} '
                          'cho ${plan.remainingCredits} TC còn lại',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CỘT HỌC KỲ
// ============================================================================

class _SemesterColumn extends StatelessWidget {
  final int term;
  final List<Subject> subjects;
  final BoardColorMode mode;
  final String query;
  final bool onlyProgramming;
  final Set<String> programming;
  final int? selectedId;
  final Set<int> prereqIds;
  final Set<int> dependentIds;
  final VoidCallback onCollapse;

  const _SemesterColumn({
    required this.term,
    required this.subjects,
    required this.mode,
    required this.query,
    required this.onlyProgramming,
    required this.programming,
    required this.selectedId,
    required this.prereqIds,
    required this.dependentIds,
    required this.onCollapse,
  });

  static const double width = 226;

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final target = state.targetGpa;
    final credits = subjects.fold<int>(0, (s, x) => s + x.credits);

    var points = 0.0;
    var gpaCredits = 0;
    final counts = <TargetStatus, int>{};
    for (final s in subjects) {
      final entry = state.gradeOf(s.code);
      final st = targetStatusOf(entry, target);
      counts[st] = (counts[st] ?? 0) + 1;
      final g = entry?.grade;
      if (entry != null &&
          g != null &&
          entry.status == SubjectStatus.passed &&
          entry.countsTowardGpa) {
        points += g * entry.credits;
        gpaCredits += entry.credits;
      }
    }
    final average = gpaCredits == 0 ? null : points / gpaCredits;

    // Viền bo góc phải cùng một màu, nên vạch màu học kỳ ở đỉnh cột là một
    // viền trên của phần tiêu đề, và cột cắt theo góc bo để vạch đó cũng bo.
    return Container(
      width: width,
      margin: const EdgeInsets.only(right: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.obsidianSidebar,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.forSemester(term), width: 3),
                bottom: BorderSide(color: AppColors.divider),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      term <= 0 ? 'HK0' : 'HK$term',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (term <= 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        'dự bị',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (average != null)
                      Tooltip(
                        message: 'Trung bình các môn đã có điểm của kỳ này',
                        child: Text(
                          'TB ${average.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Thu gọn cột',
                      icon: const Icon(Icons.chevron_left, size: 18),
                      color: AppColors.textSecondary,
                      visualDensity: VisualDensity.compact,
                      splashRadius: 14,
                      onPressed: onCollapse,
                    ),
                  ],
                ),
                Text(
                  '${subjects.length} môn · $credits tín chỉ',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (state.hasTranscript) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final st in TargetStatus.values)
                        if ((counts[st] ?? 0) > 0)
                          TargetStatusChip(
                            status: st,
                            text: '${counts[st]}',
                            compact: true,
                          ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                for (final s in subjects)
                  _SubjectCard(
                    subject: s,
                    mode: mode,
                    dimmed:
                        (query.isNotEmpty &&
                            !s.code.toLowerCase().contains(query) &&
                            !s.name.toLowerCase().contains(query)) ||
                        (onlyProgramming &&
                            !programming.contains(s.code.toUpperCase())),
                    isProgramming: programming.contains(s.code.toUpperCase()),
                    isSelected: s.id == selectedId,
                    relation: prereqIds.contains(s.id)
                        ? _Relation.prerequisite
                        : dependentIds.contains(s.id)
                        ? _Relation.dependent
                        : _Relation.none,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedColumn extends StatelessWidget {
  final int term;
  final List<Subject> subjects;
  final VoidCallback onExpand;

  const _CollapsedColumn({
    required this.term,
    required this.subjects,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final credits = subjects.fold<int>(0, (s, x) => s + x.credits);
    return Tooltip(
      message: 'HK$term · ${subjects.length} môn · $credits TC — bấm để mở',
      child: InkWell(
        onTap: onExpand,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 44,
          margin: const EdgeInsets.only(right: 10),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.obsidianSidebar,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Container(height: 3, color: AppColors.forSemester(term)),
              const SizedBox(height: 8),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 8),
              RotatedBox(
                quarterTurns: 3,
                child: Text(
                  'HK$term · ${subjects.length} môn · $credits TC',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// THẺ MÔN
// ============================================================================

enum _Relation { none, prerequisite, dependent }

class _SubjectCard extends StatefulWidget {
  final Subject subject;
  final BoardColorMode mode;
  final bool dimmed;
  final bool isProgramming;
  final bool isSelected;
  final _Relation relation;

  const _SubjectCard({
    required this.subject,
    required this.mode,
    required this.dimmed,
    required this.isProgramming,
    required this.isSelected,
    required this.relation,
  });

  @override
  State<_SubjectCard> createState() => _SubjectCardState();
}

class _SubjectCardState extends State<_SubjectCard> {
  bool _hovered = false;

  static Color get _prereqColor => AppColors.info;
  static const Color _dependentColor = AppColors.accent;

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final s = widget.subject;
    final entry = state.gradeOf(s.code);
    final target = state.targetGpa;
    final status = targetStatusOf(entry, target);

    final knowledge = state.knowledge?.subjects[s.code.toUpperCase()];
    final topConcepts = knowledge == null
        ? const <String>[]
        : [
            for (final c in knowledge.concepts.take(4))
              state.knowledge!.concepts[c.conceptId]?.label ?? c.conceptId,
          ];

    final borderColor = widget.isSelected
        ? AppColors.primary
        : switch (widget.relation) {
            _Relation.prerequisite => _prereqColor,
            _Relation.dependent => _dependentColor,
            _Relation.none =>
              _hovered
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : AppColors.border,
          };
    final emphasized = widget.isSelected || widget.relation != _Relation.none;

    final tooltip = StringBuffer('${s.code} — ${s.name}\n${s.credits} tín chỉ');
    if (entry != null) {
      tooltip.write(
        '\n${entry.statusLabel}${entry.hasGrade ? ' · điểm ${entry.displayGrade}' : ''}'
        '${entry.displaySemester == '—' ? '' : ' · ${entry.displaySemester}'}',
      );
    }
    if (topConcepts.isNotEmpty) {
      tooltip.write('\nTri thức: ${topConcepts.join(', ')}');
    }
    tooltip.write('\n(Bấm để xem chi tiết · bấm đúp mở ghi chú)');

    return Opacity(
      opacity: widget.dimmed ? 0.3 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Tooltip(
          message: tooltip.toString(),
          waitDuration: const Duration(milliseconds: 500),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: InkWell(
              onTap: () => state.select(widget.isSelected ? null : s.id),
              onDoubleTap: () => state.openNoteTab(s),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: borderColor,
                    width: emphasized ? 1.8 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.code,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (widget.isProgramming) ...[
                          const SizedBox(width: 5),
                          Tooltip(
                            message: 'Có kiến thức lập trình',
                            child: Icon(
                              Icons.code,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          '${s.credits} TC',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.name.replaceAll('_', ' — '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        ..._chips(entry, status),
                        if (widget.relation == _Relation.prerequisite)
                          _RelationTag(
                            icon: Icons.subdirectory_arrow_right,
                            text: 'Cần học trước',
                            color: _prereqColor,
                          ),
                        if (widget.relation == _Relation.dependent)
                          const _RelationTag(
                            icon: Icons.lock_open,
                            text: 'Được mở ra',
                            color: _dependentColor,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _chips(TranscriptEntry? entry, TargetStatus status) {
    switch (widget.mode) {
      case BoardColorMode.target:
        return [
          TargetStatusChip(
            status: status,
            text: entry?.hasGrade == true
                ? '${entry!.displayGrade} · ${targetStatusStyle(status).shortLabel}'
                : null,
          ),
        ];
      case BoardColorMode.grade:
        if (entry == null) return const [];
        final color = AppColors.gradeColor(entry.grade, entry.status);
        return [
          _MiniChip(
            color: color,
            text: entry.hasGrade
                ? '${entry.displayGrade} · ${AppColors.gradeRankLabel(entry.grade, entry.status)}'
                : AppColors.gradeRankLabel(entry.grade, entry.status),
          ),
        ];
      case BoardColorMode.domain:
        final domain = AcademicAnalyticsService.instance.domainOf(
          widget.subject.code,
        );
        return [_MiniChip(color: AppColors.domainColor(domain), text: domain)];
      case BoardColorMode.semester:
        if (entry?.hasGrade != true) return const [];
        return [
          _MiniChip(
            color: AppColors.gradeColor(entry!.grade, entry.status),
            text: 'Điểm ${entry.displayGrade}',
          ),
        ];
    }
  }
}

class _MiniChip extends StatelessWidget {
  final Color color;
  final String text;

  const _MiniChip({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RelationTag extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _RelationTag({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CHÚ GIẢI
// ============================================================================

class _BoardLegend extends StatelessWidget {
  final BoardColorMode mode;
  final bool hasSelection;

  const _BoardLegend({required this.mode, required this.hasSelection});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    switch (mode) {
      case BoardColorMode.target:
        for (final st in TargetStatus.values) {
          final style = targetStatusStyle(st);
          items.add(_legendItem(style.icon, style.color, style.label));
        }
      case BoardColorMode.grade:
        for (final (label, grade, status) in const [
          ('≥ 9.0 Xuất sắc', 9.5, SubjectStatus.passed),
          ('8.0 – 8.9 Giỏi', 8.5, SubjectStatus.passed),
          ('7.0 – 7.9 Khá', 7.5, SubjectStatus.passed),
          ('< 7.0 Cần cải thiện', 6.0, SubjectStatus.passed),
          ('Chưa qua', null, SubjectStatus.notPassed),
          ('Đang học', null, SubjectStatus.studying),
          ('Chưa học', null, SubjectStatus.notStarted),
        ]) {
          items.add(
            _legendItem(
              Icons.circle,
              AppColors.gradeColor(grade, status),
              label,
            ),
          );
        }
      case BoardColorMode.domain:
        for (final d in [...AppColors.domainOrder, 'Khác']) {
          items.add(
            _legendItem(Icons.square_rounded, AppColors.domainColor(d), d),
          );
        }
      case BoardColorMode.semester:
        items.add(
          Text(
            'Vạch màu bên trái thẻ = học kỳ (cùng màu với node trên sơ đồ)',
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
        );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(child: Wrap(spacing: 14, runSpacing: 4, children: items)),
          if (hasSelection) ...[
            _legendItem(
              Icons.subdirectory_arrow_right,
              AppColors.info,
              'Viền xanh: cần học trước',
            ),
            const SizedBox(width: 14),
            _legendItem(
              Icons.lock_open,
              AppColors.accent,
              'Viền cam: được mở ra',
            ),
          ] else
            Text(
              'Bấm một môn để thấy môn cần học trước / được mở ra',
              style: TextStyle(fontSize: 11.5, color: AppColors.textHint),
            ),
        ],
      ),
    );
  }

  Widget _legendItem(IconData icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: AppColors.textPrimary),
        ),
      ],
    );
  }
}
