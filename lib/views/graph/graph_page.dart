import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/graph_data.dart';
import '../../models/subject.dart';
import '../../models/transcript_entry.dart';
import '../../models/curriculum.dart';
import '../../models/graph_settings.dart';
import '../../services/db_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';
import '../subjects/roadmap_dialog.dart';
import '../subjects/subject_form_dialog.dart';
import 'graph_settings_panel.dart';

/// Màn hình trực quan hoá bản đồ tri thức.
class GraphPage extends StatefulWidget {
  const GraphPage({super.key});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  final TransformationController _viewer = TransformationController();
  final GlobalKey<_ObsidianGraphCanvasState> _canvasKey = GlobalKey<_ObsidianGraphCanvasState>();

  bool _showRelated = true;
  bool _showSettings = false;
  int? _semesterFilter;

  Future<void> _batchImportInbox(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 16),
                Text('Đang quét và tự động nạp fap_inbox...', style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final res = await DbService.instance.batchImportFromInbox();
      await AppState.instance.refresh();
      if (!context.mounted) return;
      Navigator.pop(context);
      Ui.success(
        context,
        'Đã nạp ${res['totalFiles']} files '
        '(${res['curricula']} khung CTĐT, ${res['syllabi']} syllabus, '
        '${res['edges']} cạnh tiên quyết).',
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      Ui.error(context, e);
    }
  }

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
                const SizedBox(width: 4),
                IconButton(
                  tooltip: _showSettings
                      ? 'Đóng cài đặt đồ thị'
                      : 'Tùy chỉnh đồ thị (Khoảng cách, độ to, lực đẩy...)',
                  icon: Icon(
                    _showSettings ? Icons.tune : Icons.tune_outlined,
                    size: 16,
                  ),
                  color: _showSettings ? AppColors.primary : AppColors.textSecondary,
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => setState(() => _showSettings = !_showSettings),
                ),
                const SizedBox(width: 8),
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
              child: Stack(
                children: [
                  Positioned.fill(
                    child: state.loading && currentGraph.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : currentGraph.isEmpty
                        ? _emptyGraph(context)
                        : _ObsidianGraphCanvas(
                            key: _canvasKey,
                            data: currentGraph,
                            settings: state.graphSettings,
                            showRelated: _showRelated,
                            semesterFilter: _semesterFilter,
                            curriculumCode: state.activeCurriculumCode,
                            viewer: _viewer,
                          ),
                  ),
                  if (state.graphSettings.colorMode == 'grade')
                    const Positioned(
                      left: 12,
                      bottom: 12,
                      child: _GradeLegend(),
                    ),
                  if (_showSettings)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: GraphSettingsPanel(
                        settings: state.graphSettings,
                        onChanged: (newSettings) => state.updateGraphSettings(newSettings),
                        onClose: () => setState(() => _showSettings = false),
                        onResimulate: () => _canvasKey.currentState?.resimulate(),
                        onResetZoom: _resetZoom,
                        onResetDefaults: () => state.resetGraphSettings(),
                      ),
                    ),
                ],
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
          'Thêm môn học đầu tiên, hoặc bấm "Nhập từ fap_inbox" để tự động '
          'nạp toàn bộ file Markdown đã tải từ FAP/FLM vào đồ thị.',
      action: Wrap(
        spacing: 12,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.cloud_download_outlined, size: 18),
            label: const Text('Nhập từ fap_inbox'),
            onPressed: () => _batchImportInbox(context),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Thêm môn học'),
            onPressed: () => SubjectFormDialog.show(context),
          ),
        ],
      ),
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
  final GraphSettings settings;
  final bool showRelated;
  final int? semesterFilter;
  final String? curriculumCode;
  final TransformationController viewer;

  const _ObsidianGraphCanvas({
    super.key,
    required this.data,
    required this.settings,
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
  double get nodeWidth => 110.0 * widget.settings.nodeScale;
  double get nodeHeight => 32.0 * widget.settings.nodeScale;

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
    final settingsChanged = widget.settings != oldWidget.settings;

    if (filterChanged || relatedChanged || dataChanged || curriculumChanged) {
      _syncGraph(resetPositions: filterChanged || curriculumChanged);
    } else if (settingsChanged && widget.settings.enablePhysics) {
      _wakeSimulation();
    }
  }

  void resimulate({bool randomize = false}) {
    final rng = math.Random();
    for (final node in _nodes) {
      if (randomize) {
        node.x += (rng.nextDouble() - 0.5) * 80.0;
        node.y += (rng.nextDouble() - 0.5) * 80.0;
      }
      node.vx = (rng.nextDouble() - 0.5) * 16.0;
      node.vy = (rng.nextDouble() - 0.5) * 16.0;
    }
    _wakeSimulation();
    setState(() {});
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
    if (!widget.settings.enablePhysics) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }

    double maxVelocity = 0.0;
    final repulsionThreshold = math.max(380.0, widget.settings.linkDistance * 2.5);
    final repulsionStrength = widget.settings.repulsionForce;

    // 1. Lực đẩy giữa các node (Repulsion Coulomb)
    for (int i = 0; i < _nodes.length; i++) {
      final n1 = _nodes[i];
      for (int j = i + 1; j < _nodes.length; j++) {
        final n2 = _nodes[j];
        final dx = n2.x - n1.x;
        final dy = n2.y - n1.y;
        final distSq = dx * dx + dy * dy + 400.0;
        final dist = math.sqrt(distSq);
        if (dist < repulsionThreshold) {
          final force = repulsionStrength / distSq;
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
    final desiredDist = widget.settings.linkDistance;
    for (final e in _edges) {
      final dx = e.to.x - e.from.x;
      final dy = e.to.y - e.from.y;
      final dist = math.sqrt(dx * dx + dy * dy) + 0.1;
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
    final grav = widget.settings.centerGravity;
    for (final n in _nodes) {
      if (!n.isDragging) {
        n.vx += (centerX - n.x) * grav;
        n.vy += (centerY - n.y) * grav;

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
                    nodeWidth: nodeWidth,
                    nodeHeight: nodeHeight,
                    edgeWidth: widget.settings.edgeWidth,
                    showArrows: widget.settings.showArrows,
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
                    settings: widget.settings,
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
  final GraphSettings settings;
  final bool isSelected;
  final TransformationController viewer;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final ValueChanged<bool> onDragEnd;

  const _DraggableNodeItem({
    required this.node,
    required this.data,
    required this.settings,
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
    final inDeg = widget.data.inDegree(s.id!);
    final outDeg = widget.data.outDegree(s.id!);
    final totalDeg = inDeg + outDeg;

    // Điểm của môn này trong bảng điểm cá nhân, null nghĩa là chưa học.
    final gradeEntry = widget.settings.colorMode == 'grade'
        ? AppState.instance.gradeOf(s.code)
        : null;

    // Dòng điểm trong tooltip, rỗng khi môn chưa có trong bảng điểm.
    final gradeLine = gradeEntry == null
        ? ''
        : 'Điểm: ${gradeEntry.displayGrade} — ${gradeEntry.statusLabel}\n';

    final Color color;
    if (widget.settings.colorMode == 'grade') {
      color = AppColors.gradeColor(
        gradeEntry?.grade,
        gradeEntry?.status ?? SubjectStatus.notStarted,
      );
    } else if (widget.settings.colorMode == 'degree') {
      if (totalDeg >= 6) {
        color = const Color(0xFFEF4444);
      } else if (totalDeg >= 4) {
        color = const Color(0xFFF97316);
      } else if (totalDeg >= 2) {
        color = const Color(0xFF8B5CF6);
      } else if (totalDeg >= 1) {
        color = const Color(0xFF3B82F6);
      } else {
        color = const Color(0xFF64748B);
      }
    } else {
      color = AppColors.forSemester(s.semester);
    }

    final scale = widget.settings.nodeScale;
    final width = 110.0 * scale;
    final height = 32.0 * scale;
    final fontSize = (11.5 * scale).clamp(9.0, 16.0);
    final tagFontSize = (10.0 * scale).clamp(8.0, 14.0);
    final dotSize = (7.5 * scale).clamp(5.0, 12.0);

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
              '$gradeLine'
              '(Nhấp để chọn • Nhấp đúp mở ghi chú .md)',
          waitDuration: const Duration(milliseconds: 350),
          child: Container(
            width: width,
            height: height,
            padding: EdgeInsets.symmetric(horizontal: (8 * scale).clamp(4.0, 12.0), vertical: (4 * scale).clamp(2.0, 8.0)),
            decoration: BoxDecoration(
              color: widget.isSelected ? color : AppColors.surface,
              borderRadius: BorderRadius.circular(8 * scale.clamp(0.8, 1.4)),
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
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    color: widget.isSelected ? Colors.white : color,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: (6 * scale).clamp(3.0, 10.0)),
                Expanded(
                  child: Text(
                    s.code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w700,
                      color: widget.isSelected ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                ),
                // Chỉ dùng màu thì người mù màu không đọc được thang điểm,
                // nên ở chế độ này con số luôn được in thẳng lên thẻ.
                if (gradeEntry?.hasGrade == true) ...[
                  Text(
                    gradeEntry!.displayGrade,
                    style: TextStyle(
                      fontSize: tagFontSize,
                      fontWeight: FontWeight.w800,
                      color: widget.isSelected ? Colors.white : color,
                    ),
                  ),
                  SizedBox(width: 4 * scale),
                ],
                if (widget.settings.showCredits) ...[
                  Text(
                    '${s.credits}TC',
                    style: TextStyle(
                      fontSize: (tagFontSize - 0.5).clamp(7.5, 12.0),
                      fontWeight: FontWeight.w600,
                      color: widget.isSelected ? Colors.white70 : AppColors.primary,
                    ),
                  ),
                  if (widget.settings.showSemesterBadge) SizedBox(width: 4 * scale),
                ],
                if (widget.settings.showSemesterBadge)
                  Text(
                    'K${s.semester}',
                    style: TextStyle(
                      fontSize: tagFontSize,
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
  final double nodeWidth;
  final double nodeHeight;
  final double edgeWidth;
  final bool showArrows;

  _GraphEdgesPainter({
    required this.edges,
    required this.isDark,
    required this.nodeWidth,
    required this.nodeHeight,
    required this.edgeWidth,
    required this.showArrows,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nodeW = nodeWidth;
    final nodeH = nodeHeight;

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

      final arrowGap = showArrows ? 5.0 : 2.0;
      final borderTo = _distToRectBorder(ux, uy, nodeW, nodeH);
      final endX = toX - ux * (borderTo + arrowGap);
      final endY = toY - uy * (borderTo + arrowGap);

      if ((endX - startX) * ux + (endY - startY) * uy <= 0) continue;

      final stroke = (e.isHard ? 1.8 : 1.2) * (edgeWidth / 1.5);
      final paint = Paint()
        ..color = e.isHard
            ? AppColors.edgePrerequisite
            : (isDark ? const Color(0xFF5A5A6E) : const Color(0xFFA6A2B8))
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);

      if (showArrows) {
        final arrowSize = (e.isHard ? 7.0 : 6.0) * (edgeWidth / 1.5).clamp(0.7, 2.0);
        _drawArrowHead(canvas, endX, endY, ux, uy, paint.color, arrowSize);
      }
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

/// Chú giải thang màu theo điểm, hiện ở góc canvas khi đang tô màu theo điểm.
///
/// Mỗi mức có cả ô màu lẫn khoảng điểm bằng chữ, để đọc được mà không cần
/// phân biệt được màu.
class _GradeLegend extends StatelessWidget {
  const _GradeLegend();

  static const List<(String, double?, SubjectStatus)> _levels = [
    ('≥ 9.0 Xuất sắc', 9.5, SubjectStatus.passed),
    ('8.0 – 8.9 Giỏi', 8.5, SubjectStatus.passed),
    ('7.0 – 7.9 Khá', 7.5, SubjectStatus.passed),
    ('< 7.0 Cần cải thiện', 6.0, SubjectStatus.passed),
    ('Chưa qua', null, SubjectStatus.notPassed),
    ('Đang học', null, SubjectStatus.studying),
    ('Chưa học', null, SubjectStatus.notStarted),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Màu theo điểm',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          for (final (label, grade, status) in _levels)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: AppColors.gradeColor(grade, status),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
        ],
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
