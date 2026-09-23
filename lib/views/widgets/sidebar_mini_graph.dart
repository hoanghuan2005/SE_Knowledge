import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/subject.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';

/// Mini Graph View hiển thị trực tiếp trên thanh Sidebar (phong cách Obsidian Mini Graph).
class SidebarMiniGraph extends StatefulWidget {
  final VoidCallback? onOpenSettings;
  final ValueChanged<Subject>? onSelectSubject;

  const SidebarMiniGraph({
    super.key,
    this.onOpenSettings,
    this.onSelectSubject,
  });

  @override
  State<SidebarMiniGraph> createState() => _SidebarMiniGraphState();
}

class _SidebarMiniGraphState extends State<SidebarMiniGraph>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final TransformationController _transformController = TransformationController();

  final List<_MiniNodeSim> _nodes = [];
  final List<_MiniEdgeSim> _edges = [];

  _MiniNodeSim? _hoveredNode;
  _MiniNodeSim? _draggedNode;
  Offset? _mousePos;

  static const double _canvasSize = 1200.0;
  static const double _centerX = 600.0;
  static const double _centerY = 600.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _syncGraph(reset: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerView());
  }

  void _centerView() {
    if (!mounted) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? const Size(260, 400);
    final dx = size.width / 2 - _centerX;
    final dy = size.height / 2 - _centerY;
    _transformController.value = Matrix4.identity()..setTranslationRaw(dx, dy, 0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _syncGraph({bool reset = false}) {
    final state = AppState.instance;
    final data = state.currentGraph;
    final subjects = data.subjects;

    if (subjects.isEmpty) {
      _nodes.clear();
      _edges.clear();
      if (_ticker.isActive) _ticker.stop();
      setState(() {});
      return;
    }

    final oldMap = {for (final n in _nodes) n.subject.id!: n};
    final newNodes = <_MiniNodeSim>[];
    final nodeById = <int, _MiniNodeSim>{};

    final rng = math.Random(42);
    final count = subjects.length;
    final radius = math.min(180.0, 50.0 + count * 2.5);

    for (int i = 0; i < count; i++) {
      final s = subjects[i];
      final old = oldMap[s.id];
      if (old != null && !reset) {
        nodeById[s.id!] = old;
        newNodes.add(old);
      } else {
        final angle = (2 * math.pi * i) / math.max(1, count) + (rng.nextDouble() - 0.5) * 0.2;
        final r = radius * (0.4 + 0.6 * rng.nextDouble());
        final sim = _MiniNodeSim(
          subject: s,
          x: _centerX + r * math.cos(angle),
          y: _centerY + r * math.sin(angle),
        );
        nodeById[s.id!] = sim;
        newNodes.add(sim);
      }
    }

    final newEdges = <_MiniEdgeSim>[];
    for (final e in data.edges) {
      final u = nodeById[e.prerequisiteId];
      final v = nodeById[e.subjectId];
      if (u != null && v != null) {
        newEdges.add(_MiniEdgeSim(from: u, to: v, isHard: e.isHardPrerequisite));
      }
    }

    _nodes
      ..clear()
      ..addAll(newNodes);
    _edges
      ..clear()
      ..addAll(newEdges);

    if (!_ticker.isActive) {
      _ticker.start();
    }
    setState(() {});
  }

  void _resimulate() {
    final rng = math.Random();
    for (final node in _nodes) {
      node.vx = (rng.nextDouble() - 0.5) * 12.0;
      node.vy = (rng.nextDouble() - 0.5) * 12.0;
    }
    if (!_ticker.isActive) {
      _ticker.start();
    }
    setState(() {});
  }

  void _onTick(Duration elapsed) {
    if (_nodes.isEmpty) return;

    double maxVelocity = 0.0;
    const double repulsion = 1200.0;
    const double springK = 0.035;
    const double desiredDistance = 55.0;
    const double centerPull = 0.003;
    const double damping = 0.88;

    // 1. Lực đẩy giữa các node
    for (int i = 0; i < _nodes.length; i++) {
      final a = _nodes[i];
      for (int j = i + 1; j < _nodes.length; j++) {
        final b = _nodes[j];
        double dx = b.x - a.x;
        double dy = b.y - a.y;
        double dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 1.0) dist = 1.0;
        if (dist < 180.0) {
          final force = repulsion / (dist * dist);
          final fx = (dx / dist) * force;
          final fy = (dy / dist) * force;
          if (!a.isDragging) {
            a.vx -= fx;
            a.vy -= fy;
          }
          if (!b.isDragging) {
            b.vx += fx;
            b.vy += fy;
          }
        }
      }
    }

    // 2. Lực hút theo cạnh tiên quyết
    for (final edge in _edges) {
      final a = edge.from;
      final b = edge.to;
      double dx = b.x - a.x;
      double dy = b.y - a.y;
      double dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 1.0) dist = 1.0;

      final displacement = dist - desiredDistance;
      final force = displacement * springK;
      final fx = (dx / dist) * force;
      final fy = (dy / dist) * force;

      if (!a.isDragging) {
        a.vx += fx;
        a.vy += fy;
      }
      if (!b.isDragging) {
        b.vx += fx;
        b.vy += fy;
      }
    }

    // 3. Lực kéo về tâm & cập nhật toạ độ
    for (final node in _nodes) {
      if (node.isDragging) continue;

      final dxCenter = _centerX - node.x;
      final dyCenter = _centerY - node.y;
      node.vx += dxCenter * centerPull;
      node.vy += dyCenter * centerPull;

      node.vx *= damping;
      node.vy *= damping;

      node.x += node.vx;
      node.y += node.vy;

      final v = math.sqrt(node.vx * node.vx + node.vy * node.vy);
      if (v > maxVelocity) maxVelocity = v;
    }

    if (maxVelocity < 0.05 && _draggedNode == null) {
      _ticker.stop();
    }
    setState(() {});
  }

  Offset _toCanvasCoords(Offset localPosition) {
    return _transformController.toScene(localPosition);
  }

  _MiniNodeSim? _hitTestNode(Offset canvasPos) {
    for (int i = _nodes.length - 1; i >= 0; i--) {
      final n = _nodes[i];
      final dx = n.x - canvasPos.dx;
      final dy = n.y - canvasPos.dy;
      if (dx * dx + dy * dy <= 14 * 14) {
        return n;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final selectedId = state.selectedSubjectId;

        return Column(
          children: [
            // Top Toolbar: Tiêu đề + Các icon tác vụ nhanh (Shuffle, Reset zoom, Settings)
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.obsidianBorder, width: 0.8),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'ĐỒ THỊ THU NHỎ',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidianTextMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  _MiniIconBtn(
                    icon: Icons.auto_awesome,
                    tooltip: 'Sắp xếp lại lực hấp dẫn (Physics)',
                    onTap: _resimulate,
                  ),
                  _MiniIconBtn(
                    icon: Icons.center_focus_strong_outlined,
                    tooltip: 'Căn giữa đồ thị',
                    onTap: _centerView,
                  ),
                  _MiniIconBtn(
                    icon: Icons.refresh,
                    tooltip: 'Đồng bộ lại',
                    onTap: () => _syncGraph(reset: true),
                  ),
                ],
              ),
            ),

            // Canvas chính tương tác Mini Graph
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: AppColors.isDark ? const Color(0xFF141419) : const Color(0xFFF5F4F8),
                      child: InteractiveViewer(
                        transformationController: _transformController,
                        boundaryMargin: const EdgeInsets.all(500),
                        minScale: 0.3,
                        maxScale: 3.5,
                        child: MouseRegion(
                          onHover: (e) {
                            final canvasPos = _toCanvasCoords(e.localPosition);
                            final hit = _hitTestNode(canvasPos);
                            if (hit != _hoveredNode) {
                              setState(() {
                                _hoveredNode = hit;
                                _mousePos = e.localPosition;
                              });
                            } else if (hit != null) {
                              setState(() => _mousePos = e.localPosition);
                            }
                          },
                          onExit: (_) => setState(() => _hoveredNode = null),
                          child: GestureDetector(
                            onPanStart: (details) {
                              final canvasPos = _toCanvasCoords(details.localPosition);
                              final hit = _hitTestNode(canvasPos);
                              if (hit != null) {
                                _draggedNode = hit;
                                hit.isDragging = true;
                                if (!_ticker.isActive) _ticker.start();
                              }
                            },
                            onPanUpdate: (details) {
                              if (_draggedNode != null) {
                                final canvasPos = _toCanvasCoords(details.localPosition);
                                _draggedNode!.x = canvasPos.dx;
                                _draggedNode!.y = canvasPos.dy;
                                _draggedNode!.vx = 0;
                                _draggedNode!.vy = 0;
                                setState(() {});
                              }
                            },
                            onPanEnd: (_) {
                              if (_draggedNode != null) {
                                _draggedNode!.isDragging = false;
                                _draggedNode = null;
                              }
                            },
                            onTapUp: (details) {
                              final canvasPos = _toCanvasCoords(details.localPosition);
                              final hit = _hitTestNode(canvasPos);
                              if (hit != null) {
                                state.select(hit.subject.id);
                                widget.onSelectSubject?.call(hit.subject);
                              }
                            },
                            child: CustomPaint(
                              size: const Size(_canvasSize, _canvasSize),
                              painter: _MiniGraphPainter(
                                nodes: _nodes,
                                edges: _edges,
                                selectedId: selectedId,
                                hoveredNode: _hoveredNode,
                                isDark: AppColors.isDark,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Floating Tooltip khi rê chuột vào node
                  if (_hoveredNode != null && _mousePos != null)
                    Positioned(
                      left: math.min(
                        _mousePos!.dx + 12,
                        (context.size?.width ?? 260) - 140,
                      ),
                      top: math.max(6.0, _mousePos!.dy - 34),
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.isDark
                                ? const Color(0xFF1E1E28).withValues(alpha: 0.95)
                                : const Color(0xFFFFFFFF).withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.5),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _hoveredNode!.subject.code,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                              Text(
                                _hoveredNode!.subject.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: AppColors.obsidianTextMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Footer phong cách Obsidian (SE_knowledge / Vault name + stats)
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.obsidianRibbon,
                border: Border(
                  top: BorderSide(color: AppColors.obsidianBorder, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.activeCurriculumCode ?? 'SE_knowledge',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.obsidianText,
                      ),
                    ),
                  ),
                  Text(
                    '${_nodes.length} nodes',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.obsidianTextMuted,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.help_outline,
                    size: 14,
                    color: AppColors.obsidianTextMuted,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MiniNodeSim {
  final Subject subject;
  double x;
  double y;
  double vx = 0;
  double vy = 0;
  bool isDragging = false;

  _MiniNodeSim({
    required this.subject,
    required this.x,
    required this.y,
  });
}

class _MiniEdgeSim {
  final _MiniNodeSim from;
  final _MiniNodeSim to;
  final bool isHard;

  _MiniEdgeSim({
    required this.from,
    required this.to,
    required this.isHard,
  });
}

class _MiniGraphPainter extends CustomPainter {
  final List<_MiniNodeSim> nodes;
  final List<_MiniEdgeSim> edges;
  final int? selectedId;
  final _MiniNodeSim? hoveredNode;
  final bool isDark;

  _MiniGraphPainter({
    required this.nodes,
    required this.edges,
    required this.selectedId,
    required this.hoveredNode,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Vẽ các cạnh kết nối
    final normalEdgePaint = Paint()
      ..color = isDark
          ? const Color(0xFF555566).withValues(alpha: 0.4)
          : const Color(0xFFBBBBCC).withValues(alpha: 0.6)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final activeEdgePaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.8)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      final isConnectedToSelected = selectedId != null &&
          (edge.from.subject.id == selectedId || edge.to.subject.id == selectedId);
      final isConnectedToHovered = hoveredNode != null &&
          (edge.from == hoveredNode || edge.to == hoveredNode);

      final paint = (isConnectedToSelected || isConnectedToHovered)
          ? activeEdgePaint
          : normalEdgePaint;

      canvas.drawLine(
        Offset(edge.from.x, edge.from.y),
        Offset(edge.to.x, edge.to.y),
        paint,
      );
    }

    // 2. Vẽ các nút (Nodes)
    for (final node in nodes) {
      final isSelected = node.subject.id == selectedId;
      final isHovered = node == hoveredNode;

      double nodeRadius = 5.0;
      Color nodeColor = isDark ? const Color(0xFFC0C0D0) : const Color(0xFF505068);

      if (isSelected) {
        nodeRadius = 8.0;
        nodeColor = AppColors.primary;
      } else if (isHovered) {
        nodeRadius = 7.0;
        nodeColor = AppColors.primaryLight;
      }

      // Vòng hào quang phát sáng khi selected/hovered
      if (isSelected || isHovered) {
        final glowPaint = Paint()
          ..color = AppColors.primary.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(node.x, node.y), nodeRadius + 4.0, glowPaint);
      }

      final nodePaint = Paint()
        ..color = nodeColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(node.x, node.y), nodeRadius, nodePaint);

      // Viền nhẹ cho node
      final borderPaint = Paint()
        ..color = isDark ? Colors.black38 : Colors.white70
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(node.x, node.y), nodeRadius, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniGraphPainter oldDelegate) {
    return true;
  }
}

class _MiniIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MiniIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: AppColors.obsidianTextMuted),
        ),
      ),
    );
  }
}
