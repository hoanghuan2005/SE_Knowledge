import 'package:flutter/material.dart';

import '../../models/graph_data.dart';
import '../../models/subject.dart';
import '../../utils/app_colors.dart';

/// Hộp thoại trực quan hoá Lộ trình học đề xuất (Topological Sort / Kahn)
/// được tính toán trên Khung chương trình đang chọn.
class RoadmapDialog extends StatefulWidget {
  final List<Subject> order;
  final String? curriculumCode;
  final GraphData graphData;

  const RoadmapDialog({
    super.key,
    required this.order,
    this.curriculumCode,
    required this.graphData,
  });

  static Future<void> show(
    BuildContext context, {
    required List<Subject> order,
    String? curriculumCode,
    required GraphData graphData,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => RoadmapDialog(
        order: order,
        curriculumCode: curriculumCode,
        graphData: graphData,
      ),
    );
  }

  @override
  State<RoadmapDialog> createState() => _RoadmapDialogState();
}

class _RoadmapDialogState extends State<RoadmapDialog> {
  int? _selectedSemesterFilter;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.75).clamp(620.0, 960.0);
    final dialogHeight = (screenSize.height * 0.85).clamp(520.0, 800.0);

    final totalCredits = widget.order.fold<int>(0, (sum, s) => sum + s.credits);

    // Gom nhóm môn theo học kỳ
    final grouped = <int, List<Subject>>{};
    for (final s in widget.order) {
      grouped.putIfAbsent(s.semester, () => []).add(s);
    }
    final semesters = grouped.keys.toList()..sort();

    final visibleSemesters = _selectedSemesterFilter == null
        ? semesters
        : semesters.where((s) => s == _selectedSemesterFilter).toList();

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF18181E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.obsidianBorder),
      ),
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // --- Header ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF22222B) : const Color(0xFFF3F2F8),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                border: Border(bottom: BorderSide(color: AppColors.obsidianBorder)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: isDark ? 0.25 : 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.route_outlined, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Lộ trình học đề xuất',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.obsidianText,
                              ),
                            ),
                            if (widget.curriculumCode != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  widget.curriculumCode!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? AppColors.primaryLight : AppColors.primaryDark,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${widget.order.length} môn học · $totalCredits tín chỉ · Sắp xếp Topo (Kahn) chuẩn tiên quyết',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.obsidianTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Dropdown lọc nhanh kỳ
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.obsidianCard,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.obsidianBorder),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: _selectedSemesterFilter,
                        isDense: true,
                        dropdownColor: AppColors.obsidianCard,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.obsidianText,
                        ),
                        items: [
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              'Tất cả các kỳ (${semesters.length})',
                              style: TextStyle(color: AppColors.obsidianText),
                            ),
                          ),
                          for (final s in semesters)
                            DropdownMenuItem<int?>(
                              value: s,
                              child: Text(
                                'Kỳ $s (${grouped[s]?.length ?? 0} môn)',
                                style: TextStyle(color: AppColors.obsidianText),
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _selectedSemesterFilter = v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: AppColors.obsidianTextMuted),
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // --- Body: Timeline / Grouped by Semester ---
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                itemCount: visibleSemesters.length,
                itemBuilder: (context, idx) {
                  final sem = visibleSemesters[idx];
                  final semSubjects = grouped[sem] ?? [];
                  final semCredits = semSubjects.fold<int>(0, (sum, s) => sum + s.credits);
                  final semColor = AppColors.forSemester(sem);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: AppColors.obsidianCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF2C2C38) : const Color(0xFFE2E0EE),
                      ),
                      boxShadow: [
                        if (!isDark)
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Semester Header Bar
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: semColor.withValues(alpha: isDark ? 0.15 : 0.08),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                            border: Border(
                              bottom: BorderSide(
                                color: semColor.withValues(alpha: isDark ? 0.35 : 0.2),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: semColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                sem == 0 ? 'Kỳ dự bị (Kỳ 0)' : 'HỌC KỲ $sem',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: semColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${semSubjects.length} môn  ·  $semCredits tín chỉ',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.obsidianTextMuted,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Subjects inside semester
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          itemCount: semSubjects.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: isDark ? const Color(0xFF262632) : const Color(0xFFEEEEF5),
                          ),
                          itemBuilder: (context, sIdx) {
                            final s = semSubjects[sIdx];
                            final overallIndex = widget.order.indexOf(s) + 1;

                            // Tìm danh sách mã môn tiên quyết
                            final prereqs = widget.graphData.edges
                                .where((e) => e.subjectId == s.id)
                                .map((e) => widget.graphData.byId[e.prerequisiteId]?.code)
                                .whereType<String>()
                                .toList();

                            // Tìm các môn mà môn này mở ra
                            final dependents = widget.graphData.edges
                                .where((e) => e.prerequisiteId == s.id)
                                .map((e) => widget.graphData.byId[e.subjectId]?.code)
                                .whereType<String>()
                                .toList();

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Thứ tự bước Topo
                                  Container(
                                    width: 32,
                                    height: 32,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF262634) : const Color(0xFFF0EEF8),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isDark ? const Color(0xFF383848) : const Color(0xFFDCDAE8),
                                      ),
                                    ),
                                    child: Text(
                                      '#$overallIndex',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white70 : AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Mã và tên môn học
                                  Expanded(
                                    flex: 4,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              s.code,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.obsidianText,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '${s.credits} TC',
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          s.name,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.obsidianTextMuted,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  // Mối quan hệ tiên quyết & mở ra
                                  Expanded(
                                    flex: 5,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (prereqs.isNotEmpty)
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Cần học trước: ',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isDark ? Colors.orangeAccent : const Color(0xFFC2410C),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  prereqs.join(', '),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: isDark ? Colors.orangeAccent : const Color(0xFFC2410C),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          )
                                        else
                                          Text(
                                            '✓ Môn nền tảng (không cần tiên quyết)',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? Colors.greenAccent : const Color(0xFF15803D),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        if (dependents.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Mở ra: ',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.obsidianTextMuted,
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  dependents.join(', '),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors.obsidianTextMuted,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // --- Footer ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF22222B) : const Color(0xFFF3F2F8),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                border: Border(top: BorderSide(color: AppColors.obsidianBorder)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 15, color: AppColors.obsidianTextMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Thứ tự các môn được sắp xếp bảo đảm 100% môn tiên quyết đều được học trước môn phụ thuộc.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.obsidianTextMuted,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Đã hiểu'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
