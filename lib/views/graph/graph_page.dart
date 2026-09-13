import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/graph_data.dart';
import '../../models/subject.dart';
import '../../models/curriculum.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';
import '../subjects/subject_form_dialog.dart';

/// Màn hình trực quan hoá bản đồ tri thức.
class GraphPage extends StatefulWidget {
  const GraphPage({super.key});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  final TransformationController _viewer = TransformationController();

  bool _showRelated = true;
  int? _semesterFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resetZoom());
  }

  @override
  void dispose() {
    _viewer.dispose();
    super.dispose();
  }

  void _resetZoom() {
    if (!mounted) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? const Size(900, 600);
    final dx = size.width / 2 - 1000.0;
    final dy = size.height / 2 - 1000.0;
    _viewer.value = Matrix4.identity()..setTranslationRaw(dx, dy, 0);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final currentGraph = state.currentGraph;
        final activeGroup = state.curriculumGroups.cast<CurriculumGroup?>().firstWhere(
              (g) => g?.code == state.activeCurriculumCode,
              orElse: () => null,
            );
        final semesters =
            currentGraph.subjects.map((s) => s.semester).toSet().toList()
              ..sort();

        return Column(
          children: [
            PageHeader(
              title: activeGroup != null
                  ? 'Bản đồ: ${activeGroup.code}'
                  : 'Bản đồ tri thức',
              subtitle: activeGroup != null
                  ? '${currentGraph.subjects.length} môn · ${currentGraph.edges.length} liên kết'
                  : '${state.stats['subjects'] ?? 0} môn học · ${state.stats['edges'] ?? 0} liên kết tiên quyết',
              actions: [
                if (state.curriculumGroups.isNotEmpty) ...[
                  _CurriculumFilter(
                    groups: state.curriculumGroups,
                    value: state.activeCurriculumCode,
                    onChanged: (v) => state.setActiveCurriculum(v),
                  ),
                  const SizedBox(width: 14),
                ],
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
                    size: 16,
                  ),
                  color: AppColors.textSecondary,
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => setState(() => _showRelated = !_showRelated),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Về mức zoom mặc định',
                  icon: const Icon(Icons.center_focus_strong_outlined, size: 16),
                  color: AppColors.textSecondary,
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: _resetZoom,
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Tải lại từ SQLite',
                  icon: const Icon(Icons.refresh, size: 16),
                  color: AppColors.textSecondary,
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: state.refresh,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 28,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text(
                      'Thêm môn',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
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
            Expanded(
              child: state.loading && currentGraph.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : currentGraph.isEmpty
                  ? _emptyGraph(context)
                  : _ObsidianGraphCanvas(
                      data: currentGraph,
                      showRelated: _showRelated,
                      semesterFilter: _semesterFilter,
                      curriculumCode: state.activeCurriculumCode,
                      viewer: _viewer,
                    ),
            ),
            _Legend(isDark: state.isDark),
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
}

// ============================================================================
// OBSIDIAN PHYSICS & DRAG-AND-DROP GRAPH ENGINE
// ============================================================================

class _NodeSim {
  final Subject subject;
  double x;
  double y;
  double vx = 0;
  double vy = 0;
  bool isDragging = false;

  _NodeSim({required this.subject, required this.x, required this.y});
}

class _EdgeSim {
  final _NodeSim from;
  final _NodeSim to;
  final bool isHard;

  _EdgeSim({required this.from, required this.to, required this.isHard});
}

class _ObsidianGraphCanvas extends StatefulWidget {
  final GraphData data;
  final bool showRelated;
  final int? semesterFilter;
  final String? curriculumCode;
  final TransformationController viewer;

  const _ObsidianGraphCanvas({
    required this.data,
    required this.showRelated,
    required this.semesterFilter,
    this.curriculumCode,
    required this.viewer,
  });

  @override
  State<_ObsidianGraphCanvas> createState() => _ObsidianGraphCanvasState();
}

class _ObsidianGraphCanvasState extends State<_ObsidianGraphCanvas>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<_NodeSim> _nodes = [];
  final List<_EdgeSim> _edges = [];
  bool _isDraggingAny = false;

  static const double canvasSize = 2000.0;
  static const double centerX = 1000.0;
  static const double centerY = 1000.0;
  static const double nodeWidth = 110.0;
  static const double nodeHeight = 32.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _syncGraph(resetPositions: true);
  }

  @override
  void didUpdateWidget(covariant _ObsidianGraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final filterChanged = widget.semesterFilter != oldWidget.semesterFilter;
    final relatedChanged = widget.showRelated != oldWidget.showRelated;
    final dataChanged = widget.data != oldWidget.data;
    final curriculumChanged = widget.curriculumCode != oldWidget.curriculumCode;

    if (filterChanged || relatedChanged || dataChanged || curriculumChanged) {
      _syncGraph(resetPositions: filterChanged || curriculumChanged);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _wakeSimulation() {
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _syncGraph({bool resetPositions = false}) {
    final visible = widget.semesterFilter == null
        ? widget.data.subjects
        : widget.data.subjects.where((s) => s.semester == widget.semesterFilter).toList();

    if (visible.isEmpty) {
      _nodes.clear();
      _edges.clear();
      if (_ticker.isActive) _ticker.stop();
      setState(() {});
      return;
    }

    final oldMap = {for (final n in _nodes) n.subject.id!: n};
    final newNodes = <_NodeSim>[];
    final nodeById = <int, _NodeSim>{};

    // Bố cục lực đẩy (Force / Cụm Obsidian)
    final count = visible.length;
    for (int i = 0; i < count; i++) {
      final s = visible[i];
      final existing = oldMap[s.id];
      if (existing != null && !resetPositions) {
        newNodes.add(existing);
        nodeById[s.id!] = existing;
      } else {
        final angle = i * (2 * math.pi / count);
        final radius = 180.0 + (i % 3) * 45.0;
        final node = _NodeSim(
          subject: s,
          x: centerX + radius * math.cos(angle),
          y: centerY + radius * math.sin(angle),
        );
        newNodes.add(node);
        nodeById[s.id!] = node;
      }
    }

    _nodes
      ..clear()
      ..addAll(newNodes);

    // Cập nhật các cạnh liên kết
    final newEdges = <_EdgeSim>[];
    for (final e in widget.data.edges) {
      if (!widget.showRelated && !e.isHardPrerequisite) continue;
      final from = nodeById[e.prerequisiteId];
      final to = nodeById[e.subjectId];
      if (from != null && to != null) {
        newEdges.add(_EdgeSim(from: from, to: to, isHard: e.isHardPrerequisite));
      }
    }

    _edges
      ..clear()
      ..addAll(newEdges);

    _wakeSimulation();
    setState(() {});
  }

  void _onTick(Duration elapsed) {
    if (_nodes.isEmpty) return;

    double maxVelocity = 0.0;

    // 1. Lực đẩy giữa các node (Repulsion Coulomb)
    for (int i = 0; i < _nodes.length; i++) {
      final n1 = _nodes[i];
      for (int j = i + 1; j < _nodes.length; j++) {
        final n2 = _nodes[j];
        final dx = n2.x - n1.x;
        final dy = n2.y - n1.y;
        final distSq = dx * dx + dy * dy + 400.0;
        final dist = math.sqrt(distSq);
        if (dist < 420.0) {
          final force = 24000.0 / distSq;
          final fx = (dx / dist) * force;
          final fy = (dy / dist) * force;
          if (!n1.isDragging) {
            n1.vx -= fx;
            n1.vy -= fy;
          }
          if (!n2.isDragging) {
            n2.vx += fx;
            n2.vy += fy;
          }
        }
      }
    }

    // 2. Lực lò xo đàn hồi dọc theo liên kết (Spring Hooke)
    for (final e in _edges) {
      final dx = e.to.x - e.from.x;
      final dy = e.to.y - e.from.y;
      final dist = math.sqrt(dx * dx + dy * dy) + 0.1;
      const desiredDist = 130.0;
      final delta = dist - desiredDist;
      final force = delta * 0.045;
      final fx = (dx / dist) * force;
      final fy = (dy / dist) * force;

      if (!e.from.isDragging) {
        e.from.vx += fx;
        e.from.vy += fy;
      }
      if (!e.to.isDragging) {
        e.to.vx -= fx;
        e.to.vy -= fy;
      }
    }

    // 3. Trọng lực hướng tâm & Giảm chấn (Damping Friction)
    for (final n in _nodes) {
      if (!n.isDragging) {
        n.vx += (centerX - n.x) * 0.005;
        n.vy += (centerY - n.y) * 0.005;

        n.vx *= 0.86;
        n.vy *= 0.86;

        n.x += n.vx;
        n.y += n.vy;

        final v = n.vx.abs() + n.vy.abs();
        if (v > maxVelocity) maxVelocity = v;
      }
    }

    setState(() {});

    // Tự động ngủ khi đồ thị cân bằng để tiết kiệm 100% CPU
    if (!_isDraggingAny && maxVelocity < 0.06) {
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_nodes.isEmpty) {
      return const EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: 'Không có môn nào ở kỳ này',
        message: 'Đổi bộ lọc kỳ học ở thanh trên để xem các môn khác.',
      );
    }

    final isDark = AppColors.isDark;
    final selectedId = AppState.instance.selectedSubjectId;

    return Container(
      color: AppColors.background,
      child: InteractiveViewer(
        transformationController: widget.viewer,
        constrained: false,
        panEnabled: !_isDraggingAny,
        boundaryMargin: const EdgeInsets.all(600),
        minScale: 0.15,
        maxScale: 3.0,
        child: SizedBox(
          width: canvasSize,
          height: canvasSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. Vẽ các đường mũi tên liên kết giữa các node
              Positioned.fill(
                child: CustomPaint(
                  painter: _GraphEdgesPainter(
                    edges: _edges,
                    isDark: isDark,
                  ),
                ),
              ),

              // 2. Các thẻ node môn học nhỏ gọn (có thể kéo thả)
              for (final node in _nodes)
                Positioned(
                  left: node.x - (nodeWidth / 2),
                  top: node.y - (nodeHeight / 2),
                  child: _DraggableNodeItem(
                    node: node,
                    data: widget.data,
                    isSelected: selectedId == node.subject.id,
                    viewer: widget.viewer,
                    onDragStart: () {
                      setState(() {
                        node.isDragging = true;
                        _isDraggingAny = true;
                      });
                      _wakeSimulation();
                    },
                    onDragUpdate: (delta) {
                      final scale = widget.viewer.value.getMaxScaleOnAxis();
                      node.x += delta.dx / scale;
                      node.y += delta.dy / scale;
                      node.vx = delta.dx / scale;
                      node.vy = delta.dy / scale;
                      _wakeSimulation();
                    },
                    onDragEnd: (wasTap) {
                      setState(() {
                        node.isDragging = false;
                        _isDraggingAny = false;
                      });
                      if (wasTap) {
                        AppState.instance.select(node.subject.id);
                      }
                      _wakeSimulation();
                    },
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
// THẺ MÔN HỌC COMPACT (BỎ DESCRIPTION) & KÉO THẢ
// ============================================================================

class _DraggableNodeItem extends StatefulWidget {
  final _NodeSim node;
  final GraphData data;
  final bool isSelected;
  final TransformationController viewer;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final ValueChanged<bool> onDragEnd;

  const _DraggableNodeItem({
    required this.node,
    required this.data,
    required this.isSelected,
    required this.viewer,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  State<_DraggableNodeItem> createState() => _DraggableNodeItemState();
}

class _DraggableNodeItemState extends State<_DraggableNodeItem> {
  Offset _startPos = Offset.zero;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Widget build(BuildContext context) {
    final s = widget.node.subject;
    final color = AppColors.forSemester(s.semester);
    final inDeg = widget.data.inDegree(s.id!);
    final outDeg = widget.data.outDegree(s.id!);

    return Listener(
      onPointerDown: (e) {
        _startPos = e.position;
        widget.onDragStart();
      },
      onPointerMove: (e) {
        widget.onDragUpdate(e.delta);
      },
      onPointerUp: (e) {
        final dist = (e.position - _startPos).distance;
        final wasTap = dist < 5.0;
        widget.onDragEnd(wasTap);
        if (wasTap) {
          final now = DateTime.now();
          if (now.difference(_lastTapTime).inMilliseconds < 350) {
            // Nhấp đúp: mở ngay tab ghi chú Obsidian ở thanh trên
            AppState.instance.openNoteTab(s);
          }
          _lastTapTime = now;
        }
      },
      child: MouseRegion(
        cursor: widget.node.isDragging
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.grab,
        child: Tooltip(
          message:
              '${s.code} — ${s.name}\n'
              'Học kỳ ${s.semester} • ${s.credits} tín chỉ\n'
              '$inDeg môn tiên quyết • mở ra $outDeg môn\n'
              '(Nhấp để chọn • Nhấp đúp mở ghi chú .md)',
          waitDuration: const Duration(milliseconds: 350),
          child: Container(
            width: 110,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: widget.isSelected ? color : AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.isSelected
                    ? color
                    : (widget.node.isDragging ? AppColors.primary : AppColors.border),
                width: widget.isSelected || widget.node.isDragging ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: widget.node.isDragging
                        ? 0.28
                        : (widget.isSelected ? 0.22 : 0.07),
                  ),
                  blurRadius: widget.node.isDragging ? 14 : (widget.isSelected ? 8 : 4),
                  offset: Offset(0, widget.node.isDragging ? 4 : 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 7.5,
                  height: 7.5,
                  decoration: BoxDecoration(
                    color: widget.isSelected ? Colors.white : color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: widget.isSelected ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  'K${s.semester}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: widget.isSelected ? Colors.white70 : AppColors.textSecondary,
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

// ============================================================================
// VẼ ĐƯỜNG MŨI TÊN LIÊN KẾT GIỮA CÁC THẺ
// ============================================================================

class _GraphEdgesPainter extends CustomPainter {
  final List<_EdgeSim> edges;
  final bool isDark;

  _GraphEdgesPainter({required this.edges, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    const nodeW = 110.0;
    const nodeH = 32.0;

    for (final e in edges) {
      final fromX = e.from.x;
      final fromY = e.from.y;
      final toX = e.to.x;
      final toY = e.to.y;

      final dx = toX - fromX;
      final dy = toY - fromY;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 20.0) continue;

      final ux = dx / dist;
      final uy = dy / dist;

      final borderFrom = _distToRectBorder(ux, uy, nodeW, nodeH);
      final startX = fromX + ux * (borderFrom + 2);
      final startY = fromY + uy * (borderFrom + 2);

      final borderTo = _distToRectBorder(ux, uy, nodeW, nodeH);
      final endX = toX - ux * (borderTo + 5);
      final endY = toY - uy * (borderTo + 5);

      if ((endX - startX) * ux + (endY - startY) * uy <= 0) continue;

      final paint = Paint()
        ..color = e.isHard
            ? AppColors.edgePrerequisite
            : (isDark ? const Color(0xFF5A5A6E) : const Color(0xFFA6A2B8))
        ..strokeWidth = e.isHard ? 1.8 : 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);

      _drawArrowHead(canvas, endX, endY, ux, uy, paint.color, e.isHard ? 7.0 : 6.0);
    }
  }

  double _distToRectBorder(double ux, double uy, double w, double h) {
    final absUx = ux.abs();
    final absUy = uy.abs();
    if (absUx < 0.0001) return h / 2;
    if (absUy < 0.0001) return w / 2;
    final distX = (w / 2) / absUx;
    final distY = (h / 2) / absUy;
    return math.min(distX, distY);
  }

  void _drawArrowHead(Canvas canvas, double x, double y, double ux, double uy, Color color, double arrowSize) {
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final nx = -uy;
    final ny = ux;

    final path = Path();
    path.moveTo(x + ux * 2, y + uy * 2);
    path.lineTo(x - ux * arrowSize + nx * (arrowSize * 0.55), y - uy * arrowSize + ny * (arrowSize * 0.55));
    path.lineTo(x - ux * (arrowSize * 0.65), y - uy * (arrowSize * 0.65));
    path.lineTo(x - ux * arrowSize - nx * (arrowSize * 0.55), y - uy * arrowSize - ny * (arrowSize * 0.55));
    path.close();

    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _GraphEdgesPainter oldDelegate) => true;
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
    return Container(
      height: 28,
      width: 98,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: value,
          isDense: true,
          isExpanded: true,
          icon: Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: AppColors.textSecondary,
          ),
          style: TextStyle(
            fontSize: 11.5,
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
                  fontSize: 11.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            for (final s in semesters)
              DropdownMenuItem<int?>(
                value: s,
                child: Text(
                  'Kỳ $s',
                  style: TextStyle(
                    fontSize: 11.5,
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
    return Container(
      height: 28,
      constraints: const BoxConstraints(minWidth: 100, maxWidth: 145),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: value != null ? AppColors.primary : AppColors.border,
          width: value != null ? 1.5 : 1.0,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isDense: true,
          isExpanded: true,
          icon: Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: AppColors.textSecondary,
          ),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: value != null ? AppColors.primary : AppColors.textPrimary,
          ),
          dropdownColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                'Tất cả khung',
                style: TextStyle(
                  fontSize: 11.5,
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
                    fontSize: 11.5,
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

class _Legend extends StatelessWidget {
  final bool isDark;
  const _Legend({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          _LegendLine(
            color: AppColors.edgePrerequisite,
            label: 'Tiên quyết bắt buộc',
            isDark: isDark,
          ),
          const SizedBox(width: 20),
          _LegendLine(
            color: AppColors.edgeRelated,
            label: 'Liên quan / tham khảo',
            isDark: isDark,
          ),
          const Spacer(),
          Text(
            'Cuộn để zoom · kéo để di chuyển · bấm node để xem chi tiết',
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? const Color(0xFF8A8A93) : const Color(0xFF6B6B80),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendLine extends StatelessWidget {
  final Color color;
  final String label;
  final bool isDark;

  const _LegendLine({
    required this.color,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 22, height: 2.5, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: isDark ? const Color(0xFFDCDDDE) : const Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }
}
