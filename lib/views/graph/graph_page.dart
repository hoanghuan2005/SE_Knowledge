import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/graph_data.dart';
import '../../models/subject.dart';
import '../../models/curriculum.dart';
import '../../services/db_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';
import '../subjects/subject_form_dialog.dart';

/// Màn hình trực quan hoá bản đồ tri thức, dựng lại theo đúng Graph View của
/// Obsidian: node hình tròn to nhỏ theo số liên kết, nhãn nằm dưới và mờ dần
/// khi thu nhỏ, cạnh mảnh màu xám, rê chuột làm nổi node + hàng xóm và làm mờ
/// phần còn lại, mô phỏng lực d3-force có panel chỉnh Forces.
class GraphPage extends StatefulWidget {
  const GraphPage({super.key});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  final GlobalKey<_ObsidianGraphCanvasState> _canvasKey = GlobalKey();

  bool _showRelated = true;
  int? _semesterFilter;
  Subject? _hovered;

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
                  tooltip: 'Canh khung vừa màn hình',
                  icon: const Icon(Icons.center_focus_strong_outlined, size: 16),
                  color: AppColors.textSecondary,
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => _canvasKey.currentState?.resetView(),
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
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_download_outlined, size: 14),
                    label: const Text(
                      'Nhập từ fap_inbox',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => _batchImportInbox(context),
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
              child: state.loading && currentGraph.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : currentGraph.isEmpty
                  ? _emptyGraph(context)
                  : _ObsidianGraphCanvas(
                      key: _canvasKey,
                      data: currentGraph,
                      showRelated: _showRelated,
                      semesterFilter: _semesterFilter,
                      curriculumCode: state.activeCurriculumCode,
                      onHover: (s) {
                        if (_hovered?.id != s?.id) {
                          setState(() => _hovered = s);
                        }
                      },
                    ),
            ),
            _Legend(isDark: state.isDark, hint: _hintText(currentGraph)),
          ],
        );
      },
    );
  }

  /// Dòng trạng thái dưới đáy: mặc định là hướng dẫn thao tác, khi rê chuột lên
  /// một node thì đổi thành thông tin chi tiết của môn đó (thay cho tooltip,
  /// giữ canvas sạch đúng kiểu Obsidian).
  String _hintText(GraphData graph) {
    final s = _hovered;
    if (s == null || s.id == null) {
      return 'Cuộn để phóng to · kéo nền để di chuyển · kéo node để sắp xếp · '
          'nhấp đúp để mở ghi chú .md';
    }
    final inDeg = graph.inDegree(s.id!);
    final outDeg = graph.outDegree(s.id!);
    return '${s.code} — ${s.name} · Kỳ ${s.semester} · ${s.credits} tín chỉ · '
        '$inDeg môn tiên quyết · mở ra $outDeg môn';
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
}

// ============================================================================
// ENGINE ĐỒ THỊ KIỂU OBSIDIAN
// Toàn bộ node / cạnh / nhãn vẽ trên MỘT canvas duy nhất (thay vì mỗi node là
// một Widget) nên vẫn mượt với hàng nghìn node, và mô phỏng lực chạy theo đúng
// mô hình d3-force mà Obsidian dùng: repel + link + center + alpha nguội dần.
// ============================================================================

class _GNode {
  final Subject subject;
  double x;
  double y;
  double vx = 0;
  double vy = 0;
  int degree = 0;
  bool fixed = false;

  _GNode({required this.subject, required this.x, required this.y});
}

class _GEdge {
  final int a;
  final int b;
  final bool hard;

  const _GEdge(this.a, this.b, this.hard);
}

/// Giá trị mặc định của các thanh trượt, dùng lại cho nút "Khôi phục mặc định".
class _Forces {
  static const double center = 0.35;
  static const double repel = 10.0;
  static const double link = 1.0;
  static const double distance = 140.0;
  static const double nodeScale = 1.0;
  static const double linkThickness = 1.0;
  static const double textFade = 0.45;
}

class _ObsidianGraphCanvas extends StatefulWidget {
  final GraphData data;
  final bool showRelated;
  final int? semesterFilter;
  final String? curriculumCode;
  final ValueChanged<Subject?> onHover;

  const _ObsidianGraphCanvas({
    super.key,
    required this.data,
    required this.showRelated,
    required this.semesterFilter,
    required this.onHover,
    this.curriculumCode,
  });

  @override
  State<_ObsidianGraphCanvas> createState() => _ObsidianGraphCanvasState();
}

class _ObsidianGraphCanvasState extends State<_ObsidianGraphCanvas>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  final List<_GNode> _nodes = [];
  final List<_GEdge> _edges = [];
  final List<List<int>> _adjacency = [];
  final Map<String, TextPainter> _labelCache = {};

  String _signature = '';

  // Mô phỏng lực: alpha giảm dần về 0 rồi ticker tự ngủ (giống d3 alphaDecay).
  double _alpha = 1.0;
  double _alphaTarget = 0.0;
  static const double _alphaDecay = 0.0228;
  static const double _alphaMin = 0.004;
  static const double _velocityDecay = 0.72;

  // Khung nhìn tự quản (thay cho InteractiveViewer) để zoom bám theo con trỏ
  // và để nhãn không bị kéo giãn méo khi phóng to.
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  Size _viewport = Size.zero;
  bool _userMovedView = false;

  int? _hover;
  int? _drag;
  bool _panning = false;
  Offset _lastPointer = Offset.zero;
  Offset _pointerDown = Offset.zero;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  // Thiết lập hiển thị / lực, mở bằng nút bánh xe ở góc trên trái như Obsidian.
  bool _panelOpen = false;
  double _centerForce = _Forces.center;
  double _repelForce = _Forces.repel;
  double _linkForce = _Forces.link;
  double _linkDistance = _Forces.distance;
  double _nodeScale = _Forces.nodeScale;
  double _linkThickness = _Forces.linkThickness;
  double _textFade = _Forces.textFade;
  bool _arrows = false;
  bool _colorBySemester = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _syncGraph(resetPositions: true);
  }

  @override
  void didUpdateWidget(covariant _ObsidianGraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);

    // GraphData được tạo mới mỗi lần rebuild khi đang lọc theo khung CTĐT, nên
    // so sánh bằng chữ ký nội dung thay vì so sánh tham chiếu — tránh việc chỉ
    // rê chuột cũng làm cả đồ thị nhảy loạn.
    final sig = _signatureOf(widget.data);
    final filterChanged = widget.semesterFilter != oldWidget.semesterFilter;
    final curriculumChanged = widget.curriculumCode != oldWidget.curriculumCode;
    final relatedChanged = widget.showRelated != oldWidget.showRelated;

    if (sig != _signature || filterChanged || curriculumChanged || relatedChanged) {
      _syncGraph(resetPositions: filterChanged || curriculumChanged);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  String _signatureOf(GraphData data) {
    final b = StringBuffer()
      ..write(data.subjects.length)
      ..write('/')
      ..write(data.edges.length)
      ..write(':');
    for (final s in data.subjects) {
      b
        ..write(s.id)
        ..write(',');
    }
    return b.toString();
  }

  // --------------------------------------------------------------------------
  // Dựng lại node / cạnh / danh sách kề
  // --------------------------------------------------------------------------

  void _syncGraph({bool resetPositions = false}) {
    _signature = _signatureOf(widget.data);
    _labelCache.clear();

    final visible = widget.semesterFilter == null
        ? widget.data.subjects
        : widget.data.subjects
              .where((s) => s.semester == widget.semesterFilter)
              .toList();

    final previous = {
      for (final n in _nodes)
        if (n.subject.id != null) n.subject.id!: n,
    };

    _nodes.clear();
    _edges.clear();
    _adjacency.clear();
    _hover = null;
    _drag = null;

    if (visible.isEmpty) {
      if (_ticker.isActive) _ticker.stop();
      setState(() {});
      return;
    }

    final indexById = <int, int>{};
    for (int i = 0; i < visible.length; i++) {
      final s = visible[i];
      if (s.id == null) continue;
      final kept = resetPositions ? null : previous[s.id];
      if (kept != null) {
        kept.degree = 0;
        kept.fixed = false;
        _nodes.add(kept);
      } else {
        // Phyllotaxis (góc vàng) cho vị trí khởi tạo trải đều quanh tâm, thay
        // vì vòng tròn đều — đồ thị nở ra tự nhiên hơn.
        final i2 = _nodes.length;
        final r = 24.0 * math.sqrt(i2 + 0.5);
        final theta = i2 * 2.39996323;
        _nodes.add(
          _GNode(subject: s, x: r * math.cos(theta), y: r * math.sin(theta)),
        );
      }
      indexById[s.id!] = _nodes.length - 1;
    }

    _adjacency.addAll(List.generate(_nodes.length, (_) => <int>[]));

    final seen = <int>{};
    for (final e in widget.data.edges) {
      if (!widget.showRelated && !e.isHardPrerequisite) continue;
      final a = indexById[e.prerequisiteId];
      final b = indexById[e.subjectId];
      if (a == null || b == null || a == b) continue;

      final key = a < b ? a * 100003 + b : b * 100003 + a;
      if (!seen.add(key)) continue;

      _edges.add(_GEdge(a, b, e.isHardPrerequisite));
      _nodes[a].degree++;
      _nodes[b].degree++;
      _adjacency[a].add(b);
      _adjacency[b].add(a);
    }

    _alpha = 1.0;
    _alphaTarget = 0.0;
    _userMovedView = false;
    _wake();
    setState(() {});
  }

  void _wake() {
    if (!_ticker.isActive) _ticker.start();
  }

  // --------------------------------------------------------------------------
  // Mô phỏng lực
  // --------------------------------------------------------------------------

  void _onTick(Duration _) {
    if (_nodes.isEmpty) {
      _ticker.stop();
      return;
    }

    _alpha += (_alphaTarget - _alpha) * _alphaDecay;

    if (_alpha < _alphaMin && _drag == null) {
      _alpha = 0;
      _ticker.stop();
      if (!_userMovedView) _fitToContent();
      setState(() {});
      return;
    }

    _simulate();
    // Lúc đồ thị còn đang nở ra thì camera bám theo, tránh node bay ra ngoài
    // màn hình rồi mới giật về khi cân bằng.
    if (!_userMovedView && _drag == null) _fitToContent();
    setState(() {});
  }

  void _simulate() {
    final a = _alpha;

    // 1. Lực đẩy giữa mọi cặp node (many-body). Chia lưới ô vuông theo bán kính
    //    cắt để không phải duyệt O(n²) — vẫn mượt khi đồ thị vài nghìn môn.
    final cutoff = math.max(420.0, _linkDistance * 3.0);
    final cell = cutoff;
    final buckets = <int, List<int>>{};
    for (int i = 0; i < _nodes.length; i++) {
      (buckets[_cellKey(_nodes[i].x, _nodes[i].y, cell)] ??= <int>[]).add(i);
    }

    final repelK = _repelForce * 15.0 * a;
    final cutoffSq = cutoff * cutoff;

    for (final entry in buckets.entries) {
      final gx = entry.key ~/ 65536 - 32768;
      final gy = entry.key % 65536 - 32768;

      for (int ox = -1; ox <= 1; ox++) {
        for (int oy = -1; oy <= 1; oy++) {
          final other = buckets[(gx + ox + 32768) * 65536 + (gy + oy + 32768)];
          if (other == null) continue;

          for (final i in entry.value) {
            final n1 = _nodes[i];
            for (final j in other) {
              if (j <= i) continue; // mỗi cặp chỉ xử lý một lần
              final n2 = _nodes[j];
              var dx = n2.x - n1.x;
              var dy = n2.y - n1.y;
              var distSq = dx * dx + dy * dy;
              if (distSq > cutoffSq) continue;
              if (distSq < 1e-3) {
                // Hai node chồng khít nhau: đẩy lệch nhẹ theo chỉ số cho ổn định.
                dx = (i.isEven ? 1 : -1) * 0.5;
                dy = (j.isEven ? 1 : -1) * 0.5;
                distSq = dx * dx + dy * dy;
              }
              final w = repelK / distSq;
              if (!n1.fixed) {
                n1.vx -= dx * w;
                n1.vy -= dy * w;
              }
              if (!n2.fixed) {
                n2.vx += dx * w;
                n2.vy += dy * w;
              }
            }
          }
        }
      }
    }

    // 2. Lực lò xo trên từng liên kết, node nhiều liên kết thì "nặng" hơn nên
    //    dịch ít hơn (bias theo bậc, giống d3 forceLink) → hub nằm giữa cụm.
    for (final e in _edges) {
      final n1 = _nodes[e.a];
      final n2 = _nodes[e.b];
      final dx = n2.x - n1.x;
      final dy = n2.y - n1.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 0.01) continue;

      final f = (dist - _linkDistance) / dist * _linkForce * 0.3 * a;
      final total = n1.degree + n2.degree;
      final bias = total == 0 ? 0.5 : n1.degree / total;

      if (!n1.fixed) {
        n1.vx += dx * f * (1 - bias);
        n1.vy += dy * f * (1 - bias);
      }
      if (!n2.fixed) {
        n2.vx -= dx * f * bias;
        n2.vy -= dy * f * bias;
      }
    }

    // 3. Lực hướng tâm + giảm chấn.
    final centerK = _centerForce * 0.018 * a;
    for (final n in _nodes) {
      if (n.fixed) {
        n.vx = 0;
        n.vy = 0;
        continue;
      }
      n.vx -= n.x * centerK;
      n.vy -= n.y * centerK;
      n.vx *= _velocityDecay;
      n.vy *= _velocityDecay;
      n.x += n.vx;
      n.y += n.vy;
    }
  }

  int _cellKey(double x, double y, double cell) {
    final gx = (x / cell).floor() + 32768;
    final gy = (y / cell).floor() + 32768;
    return gx * 65536 + gy;
  }

  // --------------------------------------------------------------------------
  // Khung nhìn
  // --------------------------------------------------------------------------

  double _radiusOf(_GNode n) =>
      (4.0 + 2.4 * math.sqrt(n.degree.toDouble())) * _nodeScale;

  Offset _toWorld(Offset local) => (local - _offset) / _scale;

  void _zoomAt(Offset focal, double target) {
    final next = target.clamp(0.05, 8.0);
    final world = (focal - _offset) / _scale;
    setState(() {
      _scale = next;
      _offset = focal - world * next;
      _userMovedView = true;
    });
  }

  void _fitToContent() {
    if (_nodes.isEmpty || _viewport.isEmpty) return;

    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final n in _nodes) {
      final r = _radiusOf(n) + 14;
      minX = math.min(minX, n.x - r);
      maxX = math.max(maxX, n.x + r);
      minY = math.min(minY, n.y - r);
      maxY = math.max(maxY, n.y + r);
    }

    final w = math.max(maxX - minX, 1.0);
    final h = math.max(maxY - minY, 1.0);
    final s = math.min(
      (_viewport.width - 80) / w,
      (_viewport.height - 80) / h,
    ).clamp(0.05, 1.8);

    _scale = s;
    _offset = Offset(
      _viewport.width / 2 - (minX + maxX) / 2 * s,
      _viewport.height / 2 - (minY + maxY) / 2 * s,
    );
    _userMovedView = false;
  }

  /// Canh lại khung nhìn cho vừa toàn bộ đồ thị (nút ở thanh tiêu đề).
  void resetView() {
    setState(_fitToContent);
  }

  void _restoreDefaults() {
    setState(() {
      _centerForce = _Forces.center;
      _repelForce = _Forces.repel;
      _linkForce = _Forces.link;
      _linkDistance = _Forces.distance;
      _nodeScale = _Forces.nodeScale;
      _linkThickness = _Forces.linkThickness;
      _textFade = _Forces.textFade;
      _arrows = false;
      _colorBySemester = false;
      _labelCache.clear();
    });
    _reheat();
  }

  void _reheat() {
    _alpha = math.max(_alpha, 0.45);
    _wake();
  }

  // --------------------------------------------------------------------------
  // Tương tác chuột
  // --------------------------------------------------------------------------

  int? _hitTest(Offset world) {
    for (int i = _nodes.length - 1; i >= 0; i--) {
      final n = _nodes[i];
      final r = _radiusOf(n) + 6 / _scale;
      final dx = world.dx - n.x;
      final dy = world.dy - n.y;
      if (dx * dx + dy * dy <= r * r) return i;
    }
    return null;
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointerDown = e.localPosition;
    _lastPointer = e.localPosition;
    final hit = _hitTest(_toWorld(e.localPosition));

    if (hit != null) {
      setState(() {
        _drag = hit;
        _nodes[hit].fixed = true;
      });
      _alphaTarget = 0.3;
      _alpha = math.max(_alpha, 0.3);
      _wake();
    } else {
      _panning = true;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    final delta = e.localPosition - _lastPointer;
    _lastPointer = e.localPosition;

    if (_drag != null) {
      final n = _nodes[_drag!];
      n.x += delta.dx / _scale;
      n.y += delta.dy / _scale;
      _wake();
    } else if (_panning) {
      setState(() {
        _offset += delta;
        _userMovedView = true;
      });
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    final moved = (e.localPosition - _pointerDown).distance;
    final dragged = _drag;

    if (dragged != null) {
      setState(() {
        _nodes[dragged].fixed = false;
        _drag = null;
      });
      _alphaTarget = 0.0;
      _alpha = math.max(_alpha, 0.25);
      _wake();

      if (moved < 4) {
        final subject = _nodes[dragged].subject;
        final now = DateTime.now();
        if (now.difference(_lastTap).inMilliseconds < 350) {
          AppState.instance.openNoteTab(subject);
        } else {
          AppState.instance.select(subject.id);
        }
        _lastTap = now;
      }
    }
    _panning = false;
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_drag != null) {
      setState(() {
        _nodes[_drag!].fixed = false;
        _drag = null;
      });
      _alphaTarget = 0.0;
    }
    _panning = false;
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      _zoomAt(e.localPosition, _scale * math.exp(-e.scrollDelta.dy * 0.0016));
    } else if (e is PointerScaleEvent) {
      _zoomAt(e.localPosition, _scale * e.scale);
    }
  }

  void _onHover(PointerHoverEvent e) {
    if (_drag != null) return;
    final hit = _hitTest(_toWorld(e.localPosition));
    if (hit == _hover) return;
    setState(() => _hover = hit);
    widget.onHover(hit == null ? null : _nodes[hit].subject);
  }

  // --------------------------------------------------------------------------
  // Dựng giao diện
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_nodes.isEmpty) {
      return const EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: 'Không có môn nào ở kỳ này',
        message: 'Đổi bộ lọc kỳ học ở thanh trên để xem các môn khác.',
      );
    }

    // Nhãn mờ dần rồi tắt hẳn khi thu nhỏ, đúng như "Text fade threshold".
    final fadeStart = 0.18 + _textFade * 0.7;
    final labelAlpha = ((_scale - fadeStart) / 0.28).clamp(0.0, 1.0);

    final highlighted = <int>{};
    if (_hover != null) {
      highlighted.add(_hover!);
      highlighted.addAll(_adjacency[_hover!]);
    }

    final selectedId = AppState.instance.selectedSubjectId;
    int? selectedIndex;
    if (selectedId != null) {
      for (int i = 0; i < _nodes.length; i++) {
        if (_nodes[i].subject.id == selectedId) {
          selectedIndex = i;
          break;
        }
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size != _viewport) {
          _viewport = size;
          if (!_userMovedView) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_userMovedView) setState(_fitToContent);
            });
          }
        }

        return Container(
          color: AppColors.background,
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  onPointerSignal: _onPointerSignal,
                  child: MouseRegion(
                    cursor: _drag != null
                        ? SystemMouseCursors.grabbing
                        : (_hover != null
                              ? SystemMouseCursors.click
                              : SystemMouseCursors.grab),
                    onHover: _onHover,
                    onExit: (_) {
                      if (_hover != null) {
                        setState(() => _hover = null);
                        widget.onHover(null);
                      }
                    },
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _ObsidianGraphPainter(
                          nodes: _nodes,
                          edges: _edges,
                          scale: _scale,
                          offset: _offset,
                          hover: _hover,
                          selected: selectedIndex,
                          highlighted: highlighted,
                          labelAlpha: labelAlpha,
                          nodeScale: _nodeScale,
                          linkThickness: _linkThickness,
                          arrows: _arrows,
                          colorBySemester: _colorBySemester,
                          isDark: AppColors.isDark,
                          cache: _labelCache,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: _GraphControls(
                  open: _panelOpen,
                  onToggle: () => setState(() => _panelOpen = !_panelOpen),
                  arrows: _arrows,
                  onArrows: (v) => setState(() => _arrows = v),
                  colorBySemester: _colorBySemester,
                  onColorBySemester: (v) => setState(() {
                    _colorBySemester = v;
                    _labelCache.clear();
                  }),
                  nodeScale: _nodeScale,
                  onNodeScale: (v) => setState(() => _nodeScale = v),
                  linkThickness: _linkThickness,
                  onLinkThickness: (v) => setState(() => _linkThickness = v),
                  textFade: _textFade,
                  onTextFade: (v) => setState(() => _textFade = v),
                  centerForce: _centerForce,
                  onCenterForce: (v) {
                    setState(() => _centerForce = v);
                    _reheat();
                  },
                  repelForce: _repelForce,
                  onRepelForce: (v) {
                    setState(() => _repelForce = v);
                    _reheat();
                  },
                  linkForce: _linkForce,
                  onLinkForce: (v) {
                    setState(() => _linkForce = v);
                    _reheat();
                  },
                  linkDistance: _linkDistance,
                  onLinkDistance: (v) {
                    setState(() => _linkDistance = v);
                    _reheat();
                  },
                  onRestoreDefaults: _restoreDefaults,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// PAINTER: vẽ cạnh → node → nhãn, có cắt bớt phần ngoài khung nhìn
// ============================================================================

class _ObsidianGraphPainter extends CustomPainter {
  final List<_GNode> nodes;
  final List<_GEdge> edges;
  final double scale;
  final Offset offset;
  final int? hover;
  final int? selected;
  final Set<int> highlighted;
  final double labelAlpha;
  final double nodeScale;
  final double linkThickness;
  final bool arrows;
  final bool colorBySemester;
  final bool isDark;
  final Map<String, TextPainter> cache;

  _ObsidianGraphPainter({
    required this.nodes,
    required this.edges,
    required this.scale,
    required this.offset,
    required this.hover,
    required this.selected,
    required this.highlighted,
    required this.labelAlpha,
    required this.nodeScale,
    required this.linkThickness,
    required this.arrows,
    required this.colorBySemester,
    required this.isDark,
    required this.cache,
  });

  Color get _nodeBase =>
      isDark ? const Color(0xFFCACAD4) : const Color(0xFF7A7A8C);
  Color get _edgeBase =>
      isDark ? const Color(0xFF3F3F4A) : const Color(0xFFC8C6D4);
  Color get _edgeHard => colorBySemester
      ? AppColors.edgePrerequisite
      : (isDark ? const Color(0xFF5C5C6B) : const Color(0xFFA9A6BA));
  Color get _accent => AppColors.primary;

  double _radiusOf(_GNode n) =>
      (4.0 + 2.4 * math.sqrt(n.degree.toDouble())) * nodeScale;

  @override
  void paint(Canvas canvas, Size size) {
    final view = Rect.fromLTWH(
      -offset.dx / scale,
      -offset.dy / scale,
      size.width / scale,
      size.height / scale,
    ).inflate(120 / scale);

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    _paintEdges(canvas, view);
    _paintNodes(canvas, view);
    if (labelAlpha > 0.02 || hover != null) _paintLabels(canvas, view);

    canvas.restore();
  }

  void _paintEdges(Canvas canvas, Rect view) {
    final dimming = hover != null;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final e in edges) {
      final n1 = nodes[e.a];
      final n2 = nodes[e.b];

      final bounds = Rect.fromPoints(Offset(n1.x, n1.y), Offset(n2.x, n2.y));
      if (!bounds.inflate(4).overlaps(view)) continue;

      final touchesHover = dimming && (e.a == hover || e.b == hover);
      final opacity = !dimming ? 1.0 : (touchesHover ? 1.0 : 0.12);

      var color = touchesHover ? _accent : (e.hard ? _edgeHard : _edgeBase);
      color = color.withValues(alpha: color.a * opacity);

      final base = (e.hard ? 1.25 : 0.85) * linkThickness;
      paint
        ..color = color
        ..strokeWidth = math.max(base, 0.55 / scale);

      final dx = n2.x - n1.x;
      final dy = n2.y - n1.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 1e-3) continue;
      final ux = dx / dist;
      final uy = dy / dist;

      final r1 = _radiusOf(n1) + 1.0;
      final arrowLen = arrows ? 5.0 * linkThickness + 2.0 : 1.0;
      final r2 = _radiusOf(n2) + arrowLen;
      if (r1 + r2 >= dist) continue;

      final start = Offset(n1.x + ux * r1, n1.y + uy * r1);
      final endPoint = Offset(n2.x - ux * r2, n2.y - uy * r2);
      canvas.drawLine(start, endPoint, paint);

      if (arrows) {
        _paintArrow(canvas, endPoint, ux, uy, color, 5.0 * linkThickness + 1.5);
      }
    }
  }

  void _paintArrow(
    Canvas canvas,
    Offset tip,
    double ux,
    double uy,
    Color color,
    double len,
  ) {
    final nx = -uy;
    final ny = ux;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - ux * len + nx * len * 0.5,
        tip.dy - uy * len + ny * len * 0.5,
      )
      ..lineTo(
        tip.dx - ux * len - nx * len * 0.5,
        tip.dy - uy * len - ny * len * 0.5,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _paintNodes(Canvas canvas, Rect view) {
    final dimming = hover != null;
    final fill = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      final r = _radiusOf(n);
      if (!view.contains(Offset(n.x, n.y)) &&
          !Rect.fromCircle(center: Offset(n.x, n.y), radius: r).overlaps(view)) {
        continue;
      }

      final isHover = i == hover;
      final near = !dimming || highlighted.contains(i);
      final opacity = near ? 1.0 : 0.22;

      var color = isHover
          ? _accent
          : (colorBySemester
                ? AppColors.forSemester(n.subject.semester)
                : _nodeBase);
      color = color.withValues(alpha: color.a * opacity);

      fill.color = color;
      canvas.drawCircle(Offset(n.x, n.y), r, fill);

      if (i == selected) {
        canvas.drawCircle(
          Offset(n.x, n.y),
          r + math.max(2.0, 3.0 / scale),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.4, 1.8 / scale)
            ..color = _accent.withValues(alpha: opacity),
        );
      }
    }
  }

  void _paintLabels(Canvas canvas, Rect view) {
    final dimming = hover != null;
    const fontSize = 11.0;

    for (int i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      if (!view.contains(Offset(n.x, n.y))) continue;

      final near = !dimming || highlighted.contains(i);
      // Node đang rê chuột và hàng xóm luôn hiện nhãn dù đang thu nhỏ.
      final alpha = dimming && near
          ? 1.0
          : (near ? labelAlpha : labelAlpha * 0.2);
      if (alpha < 0.03) continue;

      final bucket = (alpha * 5).round() / 5;
      if (bucket <= 0) continue;

      final color = (i == hover ? _accent : AppColors.obsidianText)
          .withValues(alpha: bucket.clamp(0.0, 1.0));
      final key = '${n.subject.code}|${color.toARGB32()}';

      final tp = cache.putIfAbsent(key, () {
        final painter = TextPainter(
          text: TextSpan(
            text: n.subject.code,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        return painter;
      });

      tp.paint(
        canvas,
        Offset(n.x - tp.width / 2, n.y + _radiusOf(n) + 3),
      );
    }

    // Không để cache phình vô hạn khi người dùng zoom qua lại nhiều mức alpha.
    if (cache.length > 1500) cache.clear();
  }

  @override
  bool shouldRepaint(covariant _ObsidianGraphPainter oldDelegate) => true;
}

// ============================================================================
// PANEL THIẾT LẬP (Display / Forces) — mô phỏng bảng điều khiển của Obsidian
// ============================================================================

class _GraphControls extends StatelessWidget {
  final bool open;
  final VoidCallback onToggle;

  final bool arrows;
  final ValueChanged<bool> onArrows;
  final bool colorBySemester;
  final ValueChanged<bool> onColorBySemester;
  final double nodeScale;
  final ValueChanged<double> onNodeScale;
  final double linkThickness;
  final ValueChanged<double> onLinkThickness;
  final double textFade;
  final ValueChanged<double> onTextFade;

  final double centerForce;
  final ValueChanged<double> onCenterForce;
  final double repelForce;
  final ValueChanged<double> onRepelForce;
  final double linkForce;
  final ValueChanged<double> onLinkForce;
  final double linkDistance;
  final ValueChanged<double> onLinkDistance;

  final VoidCallback onRestoreDefaults;

  const _GraphControls({
    required this.open,
    required this.onToggle,
    required this.arrows,
    required this.onArrows,
    required this.colorBySemester,
    required this.onColorBySemester,
    required this.nodeScale,
    required this.onNodeScale,
    required this.linkThickness,
    required this.onLinkThickness,
    required this.textFade,
    required this.onTextFade,
    required this.centerForce,
    required this.onCenterForce,
    required this.repelForce,
    required this.onRepelForce,
    required this.linkForce,
    required this.onLinkForce,
    required this.linkDistance,
    required this.onLinkDistance,
    required this.onRestoreDefaults,
  });

  @override
  Widget build(BuildContext context) {
    if (!open) {
      return _panelBox(
        child: IconButton(
          tooltip: 'Thiết lập đồ thị',
          icon: const Icon(Icons.tune, size: 16),
          color: AppColors.textSecondary,
          splashRadius: 14,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          onPressed: onToggle,
        ),
        padding: EdgeInsets.zero,
      );
    }

    return _panelBox(
      child: SizedBox(
        width: 228,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.tune, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  'Thiết lập đồ thị',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  color: AppColors.textSecondary,
                  splashRadius: 12,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                  onPressed: onToggle,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _section('Hiển thị'),
                    _switchRow('Mũi tên chỉ hướng', arrows, onArrows),
                    _switchRow('Màu theo kỳ học', colorBySemester, onColorBySemester),
                    _slider('Cỡ node', nodeScale, 0.4, 2.2, onNodeScale),
                    _slider('Độ dày liên kết', linkThickness, 0.4, 2.5, onLinkThickness),
                    _slider('Ngưỡng hiện chữ', textFade, 0.0, 1.0, onTextFade),
                    const SizedBox(height: 6),
                    _section('Lực'),
                    _slider('Lực hướng tâm', centerForce, 0.0, 1.0, onCenterForce),
                    _slider('Lực đẩy', repelForce, 0.0, 25.0, onRepelForce),
                    _slider('Lực liên kết', linkForce, 0.0, 1.0, onLinkForce),
                    _slider('Độ dài liên kết', linkDistance, 30.0, 500.0, onLinkDistance),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 26,
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: onRestoreDefaults,
                        child: const Text(
                          'Khôi phục mặc định',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelBox({required Widget child, EdgeInsetsGeometry? padding}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 440),
      child: Container(
        padding: padding ?? const EdgeInsets.fromLTRB(12, 8, 10, 10),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textHint,
        ),
      ),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
          Transform.scale(
            scale: 0.68,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
        SizedBox(
          height: 20,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
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
    // DropdownButton khẳng định phải có ĐÚNG MỘT item khớp `value`. Khung đang
    // lọc có thể vừa bị đổi mã/xoá ở thanh bên, nên phải tự hạ về "Tất cả
    // khung" thay vì để cả trang thành ô báo lỗi đỏ.
    final safe = groups.any((g) => g.code == value) ? value : null;
    return Container(
      height: 28,
      constraints: const BoxConstraints(minWidth: 100, maxWidth: 145),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: safe != null ? AppColors.primary : AppColors.border,
          width: safe != null ? 1.5 : 1.0,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: safe,
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
            color: safe != null ? AppColors.primary : AppColors.textPrimary,
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
  final String hint;

  const _Legend({required this.isDark, required this.hint});

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
            color: isDark ? const Color(0xFF5C5C6B) : const Color(0xFFA9A6BA),
            label: 'Tiên quyết bắt buộc',
            isDark: isDark,
            thickness: 2.5,
          ),
          const SizedBox(width: 20),
          _LegendLine(
            color: isDark ? const Color(0xFF3F3F4A) : const Color(0xFFC8C6D4),
            label: 'Liên quan / tham khảo',
            isDark: isDark,
            thickness: 1.5,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              hint,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? const Color(0xFF8A8A93) : const Color(0xFF6B6B80),
              ),
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
  final double thickness;

  const _LegendLine({
    required this.color,
    required this.label,
    required this.isDark,
    this.thickness = 2.5,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 22, height: thickness, color: color),
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
