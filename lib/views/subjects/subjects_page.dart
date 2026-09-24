import 'package:flutter/material.dart';

import '../../models/curriculum.dart';
import '../../models/subject.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';
import '../academic/transcript_import_dialog.dart';
import '../curriculum/syllabus_detail_dialog.dart';
import '../widgets/subject_detail_panel.dart';
import 'roadmap_dialog.dart';
import 'subject_form_dialog.dart';

/// Bảng dữ liệu môn học — hiển thị danh sách môn theo Khung chương trình (Curriculum)
/// và gom nhóm trực quan theo Học kỳ.
class SubjectsPage extends StatefulWidget {
  final bool showHeader;
  final bool showDetailPanel;

  const SubjectsPage({
    super.key,
    this.showHeader = true,
    this.showDetailPanel = true,
  });

  @override
  State<SubjectsPage> createState() => _SubjectsPageState();
}

class _SubjectsPageState extends State<SubjectsPage> {
  final TextEditingController _search = TextEditingController();
  String _keyword = '';
  int? _semesterFilter;
  bool _showSidebar = true;
  int? _lastSelectedId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Subject> _filter(List<Subject> all) {
    var result = all;
    if (_semesterFilter != null) {
      result = result.where((s) => s.semester == _semesterFilter).toList();
    }
    final kw = _keyword.trim().toLowerCase();
    if (kw.isNotEmpty) {
      result = result
          .where(
            (s) =>
                s.code.toLowerCase().contains(kw) ||
                s.name.toLowerCase().contains(kw),
          )
          .toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final currentGraph = state.currentGraph;
        final rows = _filter(currentGraph.subjects);

        if (state.selectedSubjectId != null && state.selectedSubjectId != _lastSelectedId) {
          _lastSelectedId = state.selectedSubjectId;
          _showSidebar = true;
        }

        // Gom các kỳ có trong curriculum hiện tại để đưa vào filter
        final availableSemesters = currentGraph.subjects
            .map((s) => s.semester)
            .toSet()
            .toList()
          ..sort();

        final totalCredits = rows.fold<int>(0, (sum, s) => sum + s.credits);

        if (!widget.showHeader) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border(bottom: BorderSide(color: AppColors.divider)),
                      ),
                      child: Row(
                        children: [
                          _SemesterFilter(
                            semesters: availableSemesters,
                            value: _semesterFilter,
                            onChanged: (sem) => setState(() => _semesterFilter = sem),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 260,
                            height: 32,
                            child: TextField(
                              controller: _search,
                              style: const TextStyle(fontSize: 12.5),
                              decoration: InputDecoration(
                                hintText: 'Tìm mã hoặc tên môn...',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary.withValues(alpha: 0.7),
                                ),
                                prefixIcon: Icon(
                                  Icons.search,
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 0,
                                ),
                                isDense: true,
                                filled: true,
                                fillColor: AppColors.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                    color: AppColors.border.withValues(alpha: 0.5),
                                    width: 0.8,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                    color: AppColors.border.withValues(alpha: 0.5),
                                    width: 0.8,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: AppColors.primary, width: 1.2),
                                ),
                              ),
                              onChanged: (v) => setState(() => _keyword = v),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${rows.length} môn · $totalCredits tín chỉ',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: rows.isEmpty
                          ? EmptyState(
                              icon: Icons.inbox_outlined,
                              title: currentGraph.isEmpty
                                  ? 'Chưa có môn học nào trong khung này'
                                  : 'Không tìm thấy môn khớp bộ lọc',
                              message: currentGraph.isEmpty
                                  ? 'Chọn khung chương trình khác hoặc thêm môn mới.'
                                  : 'Thử xoá bộ lọc hoặc nhập từ khoá khác.',
                            )
                          : _Table(rows: rows),
                    ),
                  ],
                ),
              ),
              if (widget.showDetailPanel && _showSidebar)
                SubjectDetailPanel(
                  onClose: () => setState(() => _showSidebar = false),
                ),
            ],
          );
        }

        return Column(
          children: [
            PageHeader(
              title: 'Danh sách môn học',
              subtitle: state.activeCurriculumCode != null
                  ? 'Khung ${state.activeCurriculumCode} — ${rows.length} môn · $totalCredits tín chỉ'
                  : 'Tất cả môn — ${rows.length} môn · $totalCredits tín chỉ',
              actions: [
                // Filter Khung chương trình (cao 32px đồng bộ, border mềm mại)
                _CurriculumFilter(
                  groups: state.curriculumGroups,
                  value: state.activeCurriculumCode,
                  onChanged: (code) {
                    setState(() {
                      _semesterFilter = null; // Reset filter kỳ khi đổi khung
                    });
                    state.setActiveCurriculum(code);
                  },
                ),
                const SizedBox(width: 8),

                // Filter Học kỳ (cao 32px đồng bộ, border mềm mại)
                _SemesterFilter(
                  semesters: availableSemesters,
                  value: _semesterFilter,
                  onChanged: (sem) => setState(() => _semesterFilter = sem),
                ),
                const SizedBox(width: 12),

                // Ô tìm kiếm với chiều cao chuẩn 32px và border thanh mảnh
                SizedBox(
                  width: 250,
                  height: 32,
                  child: TextField(
                    controller: _search,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: 'Tìm mã hoặc tên môn...',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 0,
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: AppColors.border.withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: AppColors.border.withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: AppColors.primary, width: 1.2),
                      ),
                    ),
                    onChanged: (v) => setState(() => _keyword = v),
                  ),
                ),
                const SizedBox(width: 12),

                // Nút Gợi ý lộ trình với viền mềm mại, tinh tế
                SizedBox(
                  height: 32,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.route_outlined, size: 16),
                    label: const Text(
                      'Gợi ý lộ trình',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppColors.border.withValues(alpha: 0.7),
                        width: 0.8,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => _showLearningOrder(context),
                  ),
                ),
                const SizedBox(width: 8),

                // Nút Nhập điểm chuyển từ FAB nổi lên thanh công cụ
                SizedBox(
                  height: 32,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file_outlined, size: 16),
                    label: const Text(
                      'Nhập điểm',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.5),
                      ),
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => TranscriptImportDialog.pickAndShow(context),
                  ),
                ),
                const SizedBox(width: 8),

                // Nút Thêm môn học
                SizedBox(
                  height: 32,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text(
                      'Thêm môn',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => SubjectFormDialog.show(context),
                  ),
                ),
                if (widget.showDetailPanel) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: _showSidebar ? 'Thu gọn bảng chi tiết' : 'Mở bảng chi tiết môn học',
                    child: InkWell(
                      onTap: () => setState(() => _showSidebar = !_showSidebar),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _showSidebar
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _showSidebar
                                ? AppColors.primary.withValues(alpha: 0.5)
                                : AppColors.border,
                          ),
                        ),
                        child: Icon(
                          Icons.vertical_split_outlined,
                          size: 16,
                          color: _showSidebar ? AppColors.primary : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: rows.isEmpty
                        ? EmptyState(
                            icon: Icons.inbox_outlined,
                            title: currentGraph.isEmpty
                                ? 'Chưa có môn học nào trong khung này'
                                : 'Không tìm thấy môn khớp bộ lọc',
                            message: currentGraph.isEmpty
                                ? 'Chọn khung chương trình khác hoặc thêm môn mới.'
                                : 'Thử xoá bộ lọc hoặc nhập từ khoá khác.',
                          )
                        : _Table(rows: rows),
                  ),
                  if (widget.showDetailPanel && _showSidebar)
                    SubjectDetailPanel(
                      onClose: () => setState(() => _showSidebar = false),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLearningOrder(BuildContext context) async {
    final state = AppState.instance;
    final order = await state.suggestLearningOrder();
    if (!context.mounted) return;

    if (order == null) {
      Ui.error(
        context,
        'Đồ thị đang có chu trình tiên quyết nên không sắp xếp được lộ trình.',
      );
      return;
    }
    if (order.isEmpty) {
      Ui.toast(context, 'Chưa có môn nào trong khung hiện tại để sắp xếp.');
      return;
    }

    RoadmapDialog.show(
      context,
      order: order,
      curriculumCode: state.activeCurriculumCode,
      graphData: state.currentGraph,
    );
  }
}

class _Table extends StatelessWidget {
  final List<Subject> rows;

  const _Table({required this.rows});

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;

    // Gom nhóm các môn theo học kỳ
    final grouped = <int, List<Subject>>{};
    for (final s in rows) {
      grouped.putIfAbsent(s.semester, () => []).add(s);
    }
    final semesters = grouped.keys.toList()..sort();

    return Column(
      children: [
        // Bảng Header với khoảng cách cân đối và căn giữa các cột số liệu
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: const Row(
            children: [
              SizedBox(width: 100, child: _Th('MÃ MÔN')),
              Expanded(child: _Th('TÊN MÔN')),
              SizedBox(width: 80, child: _Th('KỲ', textAlign: TextAlign.center)),
              SizedBox(width: 90, child: _Th('TÍN CHỈ', textAlign: TextAlign.center)),
              SizedBox(width: 100, child: _Th('TIÊN QUYẾT', textAlign: TextAlign.center)),
              SizedBox(width: 90, child: _Th('MỞ RA', textAlign: TextAlign.center)),
              SizedBox(width: 65, child: _Th('ĐIỂM', textAlign: TextAlign.center)),
              SizedBox(width: 48),
            ],
          ),
        ),
        // Danh sách môn gom theo từng học kỳ
        Expanded(
          child: ListView.builder(
            itemCount: semesters.length,
            itemBuilder: (context, semIndex) {
              final sem = semesters[semIndex];
              final semSubjects = grouped[sem]!;
              final semCredits = semSubjects.fold<int>(0, (sum, s) => sum + s.credits);
              final semColor = AppColors.forSemester(sem);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Semester Group Header Row
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.isDark
                          ? const Color(0xFF1B1B22)
                          : const Color(0xFFF1F0F7),
                      border: Border(
                        top: BorderSide(
                          color: AppColors.divider.withValues(alpha: 0.6),
                        ),
                        bottom: BorderSide(
                          color: AppColors.divider.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: semColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: semColor.withValues(alpha: 0.4),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: semColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                sem == 0 ? 'Kỳ 0' : 'Học kỳ $sem',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: semColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${semSubjects.length} môn · $semCredits tín chỉ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Các dòng môn học trong học kỳ này
                  ...semSubjects.map((s) {
                    final selected = state.selectedSubjectId == s.id;
                    final inDeg = state.graph.inDegree(s.id!);
                    final outDeg = state.graph.outDegree(s.id!);
                    final gradeEntry = state.gradeOf(s.code);

                    return Material(
                      key: ValueKey(s.id),
                      color: selected
                          ? AppColors.primary.withValues(
                              alpha: AppColors.isDark ? 0.22 : 0.12,
                            )
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () => state.select(selected ? null : s.id),
                        onDoubleTap: () =>
                            SubjectFormDialog.show(context, subject: s),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: AppColors.divider.withValues(alpha: 0.5),
                                width: 0.5,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              // Mã môn
                              SizedBox(
                                width: 100,
                                child: Text(
                                  s.code,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              // Tên môn
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 16),
                                  child: Text(
                                    s.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              // Badge Kỳ (Căn giữa)
                              SizedBox(
                                width: 80,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.forSemester(s.semester)
                                          .withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      s.semester == 0 ? 'Kỳ 0' : 'Kỳ ${s.semester}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.forSemester(s.semester),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Tín chỉ (Căn giữa)
                              SizedBox(
                                width: 90,
                                child: _Td('${s.credits} TC', textAlign: TextAlign.center),
                              ),
                              // Tiên quyết (Căn giữa)
                              SizedBox(
                                width: 100,
                                child: Center(
                                  child: inDeg > 0
                                      ? Text(
                                          '$inDeg môn',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.edgePrerequisite,
                                          ),
                                        )
                                      : _Td('—', textAlign: TextAlign.center),
                                ),
                              ),
                              // Mở ra (Căn giữa)
                              SizedBox(
                                width: 90,
                                child: Center(
                                  child: outDeg > 0
                                      ? Text(
                                          '$outDeg môn',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primary,
                                          ),
                                        )
                                      : _Td('—', textAlign: TextAlign.center),
                                ),
                              ),
                              // Điểm (Căn giữa)
                              SizedBox(
                                width: 65,
                                child: Center(
                                  child: gradeEntry != null && gradeEntry.hasGrade
                                      ? Text(
                                          gradeEntry.displayGrade,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.gradeColor(
                                              gradeEntry.grade,
                                              gradeEntry.status,
                                            ),
                                          ),
                                        )
                                      : _Td('—', textAlign: TextAlign.center),
                                ),
                              ),
                              // Hành động
                              SizedBox(
                                width: 48,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      tooltip: 'Xem Syllabus FLM',
                                      icon: const Icon(
                                        Icons.auto_stories_outlined,
                                        size: 18,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      onPressed: () => SyllabusDetailDialog.show(
                                        context,
                                        subjectCode: s.code,
                                        subjectId: s.id,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SemesterFilter extends StatelessWidget {
  final List<int> semesters;
  final int? value;
  final ValueChanged<int?> onChanged;

  const _SemesterFilter({
    required this.semesters,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final validValue = (value == null || semesters.contains(value)) ? value : null;
    return Container(
      height: 32,
      width: 105,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.border.withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: validValue,
          isDense: true,
          isExpanded: true,
          icon: Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: AppColors.textSecondary,
          ),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
          dropdownColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          items: [
            DropdownMenuItem<int?>(
              value: null,
              child: Text(
                'Tất cả kỳ',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            for (final s in semesters)
              DropdownMenuItem<int?>(
                value: s,
                child: Text(
                  s == 0 ? 'Kỳ 0' : 'Kỳ $s',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _CurriculumFilter extends StatelessWidget {
  final List<CurriculumGroup> groups;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _CurriculumFilter({
    required this.groups,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final validValue = (value == null || groups.any((g) => g.code == value)) ? value : null;
    return Container(
      height: 32,
      constraints: const BoxConstraints(minWidth: 110, maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: validValue != null
              ? AppColors.primary.withValues(alpha: 0.8)
              : AppColors.border.withValues(alpha: 0.5),
          width: validValue != null ? 1.2 : 0.8,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: validValue,
          isDense: true,
          isExpanded: true,
          icon: Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: AppColors.textSecondary,
          ),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: validValue != null ? AppColors.primary : AppColors.textPrimary,
          ),
          dropdownColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                'Tất cả khung',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            for (final g in groups)
              DropdownMenuItem<String?>(
                value: g.code,
                child: Text(
                  g.isUnassigned ? 'Ngoài khung' : g.code,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _Th extends StatelessWidget {
  final String text;
  final TextAlign? textAlign;
  const _Th(this.text, {this.textAlign});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _Td extends StatelessWidget {
  final String text;
  final TextAlign? textAlign;
  const _Td(this.text, {this.textAlign});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
    );
  }
}
