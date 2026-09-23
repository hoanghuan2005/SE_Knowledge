import 'package:flutter/material.dart';

import '../../models/curriculum.dart';
import '../../models/graph_data.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';
import '../subjects/roadmap_dialog.dart';
import '../subjects/subject_form_dialog.dart';
import '../subjects/subjects_page.dart';
import 'semester_board_view.dart';

enum _DetailViewMode { board, subjects }

/// **Trang A** — Màn hình chi tiết của một khung chương trình:
/// - Mặc định mở **Bảng học kỳ** (`SemesterBoardView`).
/// - Có nút chuyển sang xem **Danh sách môn** của khung này.
/// - Có nút **Sơ đồ** để nhảy sang trang Graph view (`GraphPage`) của khung đó.
/// - Có nút quay lại (`← Tất cả khung`) để về danh sách tổng quan các khung.
class CurriculumDetailPage extends StatefulWidget {
  final CurriculumGroup group;
  final VoidCallback onBack;
  final VoidCallback onOpenGraph;

  const CurriculumDetailPage({
    super.key,
    required this.group,
    required this.onBack,
    required this.onOpenGraph,
  });

  @override
  State<CurriculumDetailPage> createState() => _CurriculumDetailPageState();
}

class _CurriculumDetailPageState extends State<CurriculumDetailPage> {
  _DetailViewMode _viewMode = _DetailViewMode.board;

  String _cleanDisplayName(CurriculumGroup g) {
    if (g.isUnassigned) {
      return 'Các môn chưa gắn vào khung chương trình nào';
    }
    final raw = g.name.trim();
    if (raw.contains('@') ||
        raw.toLowerCase().contains("user's role") ||
        raw.toLowerCase().contains('student education')) {
      if (g.major.isNotEmpty && !g.major.contains('@')) {
        return g.major;
      }
      return 'Chương trình đào tạo ${g.code}';
    }
    return raw.isNotEmpty ? raw : (g.major.isNotEmpty ? g.major : 'Khung chương trình');
  }

  Future<void> _showLearningOrder(BuildContext context, GraphData graph) async {
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
      curriculumCode: widget.group.code,
      graphData: graph,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final currentGraph = state.currentGraph;
        final subjects = currentGraph.subjects;
        final totalCredits = subjects.fold<int>(0, (sum, s) => sum + s.credits);

        return Column(
          children: [
            // Header của Trang A
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                children: [
                  // Nút quay lại danh sách tất cả khung (icon chevron_left)
                  Tooltip(
                    message: 'Quay lại danh sách khung',
                    child: InkWell(
                      onTap: widget.onBack,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Icon(
                          Icons.chevron_left,
                          size: 20,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Tên & thông tin khung
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.group.isUnassigned ? 'Môn ngoài khung' : widget.group.code,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${subjects.length} môn · $totalCredits TC',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _cleanDisplayName(widget.group),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Cụm chuyển đổi góc nhìn: Bảng học kỳ / Danh sách môn
                  Container(
                    height: 32,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ViewOption(
                          icon: Icons.view_week_outlined,
                          label: 'Bảng học kỳ',
                          selected: _viewMode == _DetailViewMode.board,
                          onTap: () => setState(() => _viewMode = _DetailViewMode.board),
                        ),
                        _ViewOption(
                          icon: Icons.article_outlined,
                          label: 'Danh sách môn',
                          selected: _viewMode == _DetailViewMode.subjects,
                          onTap: () => setState(() => _viewMode = _DetailViewMode.subjects),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Nút chuyển sang xem Sơ đồ (Graph view - icon)
                  Tooltip(
                    message: 'Xem sơ đồ môn học',
                    child: InkWell(
                      onTap: () {
                        state.setActiveCurriculum(widget.group.code);
                        widget.onOpenGraph();
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Icon(
                          Icons.hub_outlined,
                          size: 16,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Nút Gợi ý lộ trình
                  SizedBox(
                    height: 32,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.route_outlined, size: 15),
                      label: const Text(
                        'Lộ trình',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: AppColors.border.withValues(alpha: 0.8),
                          width: 1.0,
                        ),
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: () => _showLearningOrder(context, currentGraph),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Nút Thêm môn học
                  SizedBox(
                    height: 32,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add, size: 15),
                      label: const Text(
                        'Thêm môn',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: () => SubjectFormDialog.show(context),
                    ),
                  ),
                ],
              ),
            ),

            // Thân trang: Bảng học kỳ hoặc Danh sách môn
            Expanded(
              child: _viewMode == _DetailViewMode.board
                  ? SemesterBoardView(
                      data: currentGraph,
                    )
                  : const SubjectsPage(
                      showHeader: false,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ViewOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ViewOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
