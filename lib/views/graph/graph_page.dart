import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';

import '../../models/graph_data.dart';
import '../../models/subject.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';
import '../subjects/subject_form_dialog.dart';
import '../widgets/subject_detail_panel.dart';

/// Hai kiểu bố cục đồ thị.
enum GraphLayout {
  /// Phân tầng theo thứ tự tiên quyết (Sugiyama) — đọc lộ trình học từ trên xuống.
  layered,

  /// Lực đẩy — cụm nơ-ron kiểu Obsidian Graph View.
  force,
}

/// Màn hình trực quan hoá bản đồ tri thức.
class GraphPage extends StatefulWidget {
  const GraphPage({super.key});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  final TransformationController _viewer = TransformationController();

  GraphLayout _layout = GraphLayout.layered;
  bool _showRelated = true;
  int? _semesterFilter;

  @override
  void dispose() {
    _viewer.dispose();
    super.dispose();
  }

  void _resetZoom() => _viewer.value = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final semesters =
            state.graph.subjects.map((s) => s.semester).toSet().toList()
              ..sort();

        return Column(
          children: [
            PageHeader(
              title: 'Bản đồ tri thức',
              subtitle:
                  '${state.stats['subjects'] ?? 0} môn học · '
                  '${state.stats['edges'] ?? 0} liên kết tiên quyết',
              actions: [
                _LayoutToggle(
                  layout: _layout,
                  onChanged: (v) => setState(() => _layout = v),
                ),
                const SizedBox(width: 12),
                _SemesterFilter(
                  semesters: semesters,
                  value: _semesterFilter,
                  onChanged: (v) => setState(() => _semesterFilter = v),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: _showRelated
                      ? 'Đang hiện quan hệ tham khảo'
                      : 'Đang ẩn quan hệ tham khảo',
                  icon: Icon(
                    _showRelated ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _showRelated = !_showRelated),
                ),
                IconButton(
                  tooltip: 'Về mức zoom mặc định',
                  icon: const Icon(Icons.center_focus_strong_outlined),
                  onPressed: _resetZoom,
                ),
                IconButton(
                  tooltip: 'Tải lại từ SQLite',
                  icon: const Icon(Icons.refresh),
                  onPressed: state.refresh,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Thêm môn'),
                  onPressed: () => SubjectFormDialog.show(context),
                ),
              ],
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: state.loading && state.graph.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : state.graph.isEmpty
                        ? _emptyGraph(context)
                        : _canvas(state.graph),
                  ),
                  const SubjectDetailPanel(),
                ],
              ),
            ),
            const _Legend(),
          ],
        );
      },
    );
  }

  Widget _emptyGraph(BuildContext context) {
    return EmptyState(
      icon: Icons.hub_outlined,
      title: 'Đồ thị đang trống',
      message:
          'Thêm môn học đầu tiên, hoặc vào tab Vault để nạp sẵn các ghi chú '
          '.md có cú pháp [[...]] từ Obsidian.',
      action: ElevatedButton.icon(
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Thêm môn học'),
        onPressed: () => SubjectFormDialog.show(context),
      ),
    );
  }

  /// Dựng đối tượng [Graph] của package graphview từ dữ liệu SQLite.
  Widget _canvas(GraphData data) {
    final visible = _semesterFilter == null
        ? data.subjects
        : data.subjects.where((s) => s.semester == _semesterFilter).toList();
    final visibleIds = visible.map((s) => s.id).whereType<int>().toSet();

    if (visible.isEmpty) {
      return const EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: 'Không có môn nào ở kỳ này',
        message: 'Đổi bộ lọc kỳ học ở thanh trên để xem các môn khác.',
      );
    }

    final graph = Graph();
    final nodes = <int, Node>{};
    for (final s in visible) {
      final node = Node.Id(s.id!);
      nodes[s.id!] = node;
      graph.addNode(node);
    }

    var edgeCount = 0;
    for (final e in data.edges) {
      if (!visibleIds.contains(e.subjectId) ||
          !visibleIds.contains(e.prerequisiteId)) {
        continue;
      }
      if (!_showRelated && !e.isHardPrerequisite) continue;

      // Mũi nhọn đi từ môn tiên quyết -> môn học sau, đúng chiều lộ trình học.
      graph.addEdge(
        nodes[e.prerequisiteId]!,
        nodes[e.subjectId]!,
        paint: Paint()
          ..color = e.isHardPrerequisite
              ? AppColors.edgePrerequisite
              : AppColors.edgeRelated
          ..strokeWidth = e.isHardPrerequisite ? 1.6 : 1.2
          ..style = PaintingStyle.stroke,
      );
      edgeCount++;
    }

    final byId = {
      for (final s in visible)
        if (s.id != null) s.id!: s,
    };

    return Container(
      color: AppColors.background,
      child: InteractiveViewer(
        transformationController: _viewer,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(400),
        minScale: 0.15,
        maxScale: 3.0,
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: GraphView(
            graph: graph,
            algorithm: _algorithm(edgeCount),
            paint: Paint()
              ..color = AppColors.edgePrerequisite
              ..strokeWidth = 1.6
              ..style = PaintingStyle.stroke,
            builder: (Node node) {
              final id = node.key!.value as int;
              final subject = byId[id];
              if (subject == null) return const SizedBox.shrink();
              return _SubjectNode(subject: subject, data: data);
            },
          ),
        ),
      ),
    );
  }

  Algorithm _algorithm(int edgeCount) {
    // Không có cạnh nào thì Sugiyama không có gì để phân tầng -> dùng lực đẩy.
    if (_layout == GraphLayout.force || edgeCount == 0) {
      return FruchtermanReingoldAlgorithm(
        FruchtermanReingoldConfiguration(
          iterations: 600,
          repulsionRate: 0.5,
          attractionRate: 0.15,
        ),
      );
    }
    final config = SugiyamaConfiguration()
      ..nodeSeparation = 36
      ..levelSeparation = 72
      ..orientation = SugiyamaConfiguration.ORIENTATION_TOP_BOTTOM;
    return SugiyamaAlgorithm(config);
  }
}

/// Một node trên đồ thị: thẻ môn học bấm được.
class _SubjectNode extends StatelessWidget {
  final Subject subject;
  final GraphData data;

  const _SubjectNode({required this.subject, required this.data});

  @override
  Widget build(BuildContext context) {
    final selected = AppState.instance.selectedSubjectId == subject.id;
    final color = AppColors.forSemester(subject.semester);
    final inDeg = data.inDegree(subject.id!);
    final outDeg = data.outDegree(subject.id!);

    return Tooltip(
      message:
          '${subject.code} — ${subject.name}\n'
          'Kỳ ${subject.semester} · ${subject.credits} tín chỉ\n'
          '$inDeg môn tiên quyết · mở ra $outDeg môn',
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => AppState.instance.select(subject.id),
          child: Container(
            width: 176,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? color : AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? color : AppColors.border,
                width: selected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: selected ? 0.16 : 0.05),
                  blurRadius: selected ? 14 : 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      subject.code,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'K${subject.semester}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.white70
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subject.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LayoutToggle extends StatelessWidget {
  final GraphLayout layout;
  final ValueChanged<GraphLayout> onChanged;

  const _LayoutToggle({required this.layout, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<GraphLayout>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(
          value: GraphLayout.layered,
          icon: Icon(Icons.account_tree_outlined, size: 16),
          label: Text('Phân tầng'),
        ),
        ButtonSegment(
          value: GraphLayout.force,
          icon: Icon(Icons.bubble_chart_outlined, size: 16),
          label: Text('Lực đẩy'),
        ),
      ],
      selected: {layout},
      onSelectionChanged: (s) => onChanged(s.first),
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
    return SizedBox(
      width: 140,
      child: DropdownButtonFormField<int?>(
        initialValue: value,
        isDense: true,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('Tất cả kỳ')),
          for (final s in semesters)
            DropdownMenuItem<int?>(value: s, child: Text('Kỳ $s')),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          const _LegendLine(
            color: AppColors.edgePrerequisite,
            label: 'Tiên quyết bắt buộc',
          ),
          const SizedBox(width: 20),
          const _LegendLine(
            color: AppColors.edgeRelated,
            label: 'Liên quan / tham khảo',
          ),
          const Spacer(),
          const Text(
            'Cuộn để zoom · kéo để di chuyển · bấm node để xem chi tiết',
            style: TextStyle(fontSize: 11.5, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}

class _LegendLine extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendLine({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 22, height: 2.5, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
