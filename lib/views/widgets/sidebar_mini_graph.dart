import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/subject.dart';
import '../../services/graph_layout_cache.dart';
import '../../services/mini_force_layout.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';

/// Mini Graph View hiển thị trực tiếp trên thanh Sidebar (phong cách Obsidian
/// Mini Graph).
///
/// Mỗi ô gắn với **một khung chương trình cụ thể** qua [curriculumCode] chứ
/// không đọc `currentGraph`, nhờ vậy cửa sổ thu nhỏ có nhiều trang (mỗi trang
/// một khung) và đổi khung trên Graph view lớn không kéo theo trang đang xem.
///
/// Ticker mô phỏng lực chỉ sống cùng State này. `MiniGraphPanel` chỉ dựng ô
/// của trang đang xem, trang khác bị gỡ hẳn khỏi cây widget, nên `dispose()`
/// dừng luôn ticker — không cần cờ tạm dừng riêng, và cũng không có trang
/// khuất nào còn ngốn CPU.
class SidebarMiniGraph extends StatefulWidget {
  /// Khung chương trình mà ô này vẽ. `null` = toàn bộ môn trong CSDL.
  final String? curriculumCode;

  final VoidCallback? onOpenSettings;
  final ValueChanged<Subject>? onSelectSubject;

  /// Mở khung này trên Graph view lớn.
  final VoidCallback? onOpenLarge;

  /// Gỡ ô khỏi thanh bên. `null` thì không hiện nút đóng — dùng cho ô xem tạm
  /// của khung đang chọn khi người dùng chưa ghim gì.
  final VoidCallback? onClose;

  /// Thu gọn ô. Có giá trị thì cả hàng tiêu đề bấm được (kiểu cây thư mục
  /// Obsidian) thay vì thêm một nút nữa vào hàng nút vốn đã chật.
  final VoidCallback? onToggleCollapse;

  /// `false` khi nơi chứa tự vẽ header riêng — cửa sổ nhiều trang của
  /// `MiniGraphPanel` giữ header đứng yên trong lúc lật trang, chỉ phần đồ
  /// thị bên dưới chuyển cảnh. Khi đó số môn và nút căn giữa nổi ở góc ô.
  final bool showHeader;

  const SidebarMiniGraph({
    super.key,
    this.curriculumCode,
    this.onOpenSettings,
    this.onSelectSubject,
    this.onOpenLarge,
    this.onClose,
    this.onToggleCollapse,
    this.showHeader = true,
  });

  @override
  State<SidebarMiniGraph> createState() => _SidebarMiniGraphState();
}

class _SidebarMiniGraphState extends State<SidebarMiniGraph>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final TransformationController _transformController =
      TransformationController();

  final List<_MiniNodeSim> _nodes = [];
  final List<_MiniEdgeSim> _edges = [];

  _MiniNodeSim? _hoveredNode;
  _MiniNodeSim? _draggedNode;

  /// Vị trí đặt tooltip, theo **toạ độ ô** (đã qua phép biến hình của
  /// InteractiveViewer) chứ không phải toạ độ canvas: tooltip nằm ngoài vùng
  /// phóng to nên không co giãn theo đồ thị.
  Offset? _tooltipAt;

  /// Điểm bấm chuột gần nhất, để phân biệt một cú chạm với một cú kéo.
  Offset _pointerDownAt = Offset.zero;

  /// Thời điểm chạm gần nhất. Tự nhận nhấp đúp thay vì mượn
  /// `GestureDetector.onDoubleTap`: thêm một recognizer nữa vào đấu trường cử
  /// chỉ là tranh mất thao tác kéo/phóng của InteractiveViewer.
  DateTime? _lastTapAt;

  /// Kích thước ô, ghi lại từ LayoutBuilder để các hàm ngoài `build` dùng được.
  Size? _viewportSize;

  /// Còn phải căn khung một lần nữa sau khi mô phỏng lực đứng yên hay không.
  bool _needsFit = true;

  static const double _canvasSize = 1200.0;
  static const double _centerX = 600.0;
  static const double _centerY = 600.0;

  /// Bán kính co bố cục lấy từ Graph view lớn về cho vừa ô nhỏ.
  static const double _fitRadius = 150.0;

  static const double _minScale = 0.15;
  static const double _maxScale = 3.5;

  /// Di chuyển dưới ngưỡng này thì tính là chạm chứ không phải kéo.
  static const double _tapSlop = 4.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    // `_syncGraph(reset: true)` tự hẹn căn khung sau khung hình đầu tiên,
    // lúc `_viewportSize` đã có giá trị thật.
    _syncGraph(reset: true);
  }

  @override
  void didUpdateWidget(covariant SidebarMiniGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cùng một ô được tái dùng cho khung khác (ví dụ sau khi đổi thứ tự các ô)
    // thì phải dựng lại từ đầu, không giữ vị trí node của khung cũ.
    if (widget.curriculumCode != oldWidget.curriculumCode) {
      _syncGraph(reset: true);
    }
  }

  /// Căn cả đồ thị vào giữa ô và co cho vừa.
  ///
  /// Bản cũ chỉ dời tâm canvas 1200×1200 về giữa ô và giữ nguyên tỉ lệ 1:1 — ô
  /// thanh bên rộng chừng 260px nên phần lớn đồ thị nằm ngoài mép, nhìn như một
  /// đám chấm rời rạc không đầu không cuối. Nay tính khung bao các node rồi co
  /// đúng bằng khoảng đó.
  void _centerView() {
    final size = _viewportSize;
    if (!mounted || size == null || size.isEmpty) return;

    if (_nodes.isEmpty) {
      _transformController.value = Matrix4.identity()
        ..setTranslationRaw(
          size.width / 2 - _centerX,
          size.height / 2 - _centerY,
          0,
        );
      return;
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;
    for (final n in _nodes) {
      if (n.x < minX) minX = n.x;
      if (n.x > maxX) maxX = n.x;
      if (n.y < minY) minY = n.y;
      if (n.y > maxY) maxY = n.y;
    }

    // Chừa lề cho nhãn môn và cho vòng hào quang của node đang chọn.
    const padding = 26.0;
    final spanX = math.max(1.0, maxX - minX) + padding * 2;
    final spanY = math.max(1.0, maxY - minY) + padding * 2;
    final scale = math
        .min(size.width / spanX, size.height / spanY)
        .clamp(_minScale, 1.5);

    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;

    // Dựng thẳng ma trận T·S thay vì `translate`/`scale`: hai hàm đó nhận tham
    // số động, gọi chuỗi vào dễ lệch thứ tự phép nhân.
    _transformController.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setTranslationRaw(
        size.width / 2 - cx * scale,
        size.height / 2 - cy * scale,
        0,
      );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _syncGraph({bool reset = false}) {
    final data = AppState.instance.graphFor(widget.curriculumCode);
    final subjects = data.subjects;

    if (subjects.isEmpty) {
      _nodes.clear();
      _edges.clear();
      if (_ticker.isActive) _ticker.stop();
      if (mounted) setState(() {});
      return;
    }

    final oldMap = {for (final n in _nodes) n.subject.id!: n};

    // Bố cục Graph view lớn đã mô phỏng xong, co lại cho vừa ô nhỏ. Nhờ vậy
    // kéo tab Graph view vào thanh bên thì hình giữ nguyên thay vì xáo lại từ
    // một vòng tròn ngẫu nhiên.
    final seeded = GraphLayoutCache.fit(
      saved: GraphLayoutCache.instance.read(widget.curriculumCode),
      subjectIds: subjects.map((s) => s.id).whereType<int>().toList(),
      center: const Offset(_centerX, _centerY),
      radius: _fitRadius,
    );

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
        continue;
      }

      final fromCache = seeded?[s.id];
      final Offset start;
      if (fromCache != null) {
        start = fromCache;
      } else {
        // Chưa có bố cục nào để mượn: bung ra vòng tròn như trước.
        final angle =
            (2 * math.pi * i) / math.max(1, count) +
            (rng.nextDouble() - 0.5) * 0.2;
        final r = radius * (0.4 + 0.6 * rng.nextDouble());
        start = Offset(
          _centerX + r * math.cos(angle),
          _centerY + r * math.sin(angle),
        );
      }

      final sim = _MiniNodeSim(subject: s, x: start.dx, y: start.dy);
      nodeById[s.id!] = sim;
      newNodes.add(sim);
    }

    final newEdges = <_MiniEdgeSim>[];
    for (final e in data.edges) {
      final u = nodeById[e.prerequisiteId];
      final v = nodeById[e.subjectId];
      if (u != null && v != null) {
        newEdges.add(
          _MiniEdgeSim(from: u, to: v, isHard: e.isHardPrerequisite),
        );
      }
    }

    _nodes
      ..clear()
      ..addAll(newNodes);
    _edges
      ..clear()
      ..addAll(newEdges);

    if (reset) {
      // Căn ngay một lần cho thấy hình, rồi căn lại lần nữa khi mô phỏng lực
      // đứng yên — lúc đó các node mới về đúng chỗ của chúng.
      _needsFit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerView());
    }

    if (!_ticker.isActive) {
      _ticker.start();
    }
    if (mounted) setState(() {});
  }

  void _onTick(Duration elapsed) {
    if (_nodes.isEmpty) return;

    final maxVelocity = MiniForceLayout.step(
      _nodes,
      _edges,
      centerX: _centerX,
      centerY: _centerY,
    );

    if (maxVelocity < MiniForceLayout.sleepVelocity && _draggedNode == null) {
      _ticker.stop();
      // Chỉ căn lại đúng một lần sau mỗi lần dựng lại đồ thị. Căn mỗi lần đứng
      // yên thì hình cứ nhảy một cái ngay sau khi người dùng vừa kéo xong.
      if (_needsFit) {
        _needsFit = false;
        _centerView();
      }
    }
    setState(() {});
  }

  double get _scale => _transformController.value.getMaxScaleOnAxis();

  /// Đổi toạ độ canvas sang toạ độ ô, để đặt tooltip nằm ngoài vùng phóng to.
  Offset _toViewportCoords(Offset canvasPos) =>
      MatrixUtils.transformPoint(_transformController.value, canvasPos);

  _MiniNodeSim? _hitTestNode(Offset canvasPos) {
    // Bán kính bắt tính theo pixel màn hình chứ không theo canvas: đang thu nhỏ
    // thì 14px canvas chỉ còn vài pixel thật, bấm trúng node thành chuyện may
    // rủi.
    final scale = _scale;
    final radius = (14.0 / (scale <= 0 ? 1.0 : scale)).clamp(10.0, 48.0);
    for (int i = _nodes.length - 1; i >= 0; i--) {
      final n = _nodes[i];
      final dx = n.x - canvasPos.dx;
      final dy = n.y - canvasPos.dy;
      if (dx * dx + dy * dy <= radius * radius) {
        return n;
      }
    }
    return null;
  }

  // Toạ độ trong các handler dưới đây **đã là** toạ độ canvas: con trỏ đi qua
  // phép biến hình của InteractiveViewer rồi mới tới widget con, nên đổi hệ
  // thêm một lần nữa (`toScene`) là sai gấp đôi — đó là lý do trước đây bấm hay
  // rê vào node đều không ăn.

  void _onHover(Offset canvasPos) {
    final hit = _hitTestNode(canvasPos);
    if (hit == null && _hoveredNode == null) return;
    setState(() {
      _hoveredNode = hit;
      _tooltipAt = hit == null ? null : _toViewportCoords(canvasPos);
    });
  }

  void _onPointerDown(Offset canvasPos) {
    _pointerDownAt = canvasPos;
    final hit = _hitTestNode(canvasPos);
    if (hit == null) return;
    hit.isDragging = true;
    // setState để InteractiveViewer nhận `panEnabled: false`, nếu không ô vừa
    // kéo node vừa trượt cả canvas.
    setState(() => _draggedNode = hit);
    if (!_ticker.isActive) _ticker.start();
  }

  void _onPointerMove(Offset canvasPos) {
    final node = _draggedNode;
    if (node == null) return;
    setState(() {
      node.x = canvasPos.dx;
      node.y = canvasPos.dy;
      node.vx = 0;
      node.vy = 0;
    });
  }

  void _onPointerUp(Offset canvasPos) {
    final node = _draggedNode;
    if (node != null) {
      node.isDragging = false;
      setState(() => _draggedNode = null);
      // Kéo xong thì để mô phỏng xếp lại các node xung quanh.
      if (!_ticker.isActive) _ticker.start();
    }

    if ((canvasPos - _pointerDownAt).distance > _tapSlop) return;

    final now = DateTime.now();
    final previous = _lastTapAt;
    _lastTapAt = now;

    if (node != null) {
      AppState.instance.select(node.subject.id);
      widget.onSelectSubject?.call(node.subject);
      return;
    }

    // Nhấp đúp vào **nền** = mở khung này ra Graph view lớn, đối xứng với thao
    // tác kéo tab Graph view vào thanh bên.
    final isDoubleTap =
        previous != null &&
        now.difference(previous) < const Duration(milliseconds: 320);
    if (isDoubleTap) widget.onOpenLarge?.call();
  }

  /// Nhãn hiển thị trên header: mã khung, hoặc "Toàn bộ môn" cho ô không lọc.
  String get _title => widget.curriculumCode ?? 'Toàn bộ môn';

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final selectedId = state.selectedSubjectId;

        return Column(
          children: [
            if (widget.showHeader) _header(),

            // Canvas chính tương tác Mini Graph
            Expanded(
              // Chiều rộng lấy từ LayoutBuilder chứ không từ `context.size`:
              // đọc kích thước ngay trong lúc build làm Flutter ném "Cannot get
              // size during build" — ở thời điểm đó cây render của khung hình
              // này còn chưa được bố trí xong nên chưa có kích thước nào để đọc.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Ghi lại để `_centerView()` biết ô rộng bao nhiêu mà co đồ
                  // thị cho vừa. Gán trong build nhưng không gọi setState nên
                  // không sinh vòng dựng lại.
                  _viewportSize = constraints.biggest;

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          color: AppColors.isDark
                              ? const Color(0xFF141419)
                              : const Color(0xFFF5F4F8),
                          child: InteractiveViewer(
                            transformationController: _transformController,
                            // Canvas giữ nguyên 1200×1200 thay vì bị ép bằng kích
                            // thước ô. Để mặc định `constrained: true` thì vùng
                            // nhận chuột co lại bằng đúng ô rồi bị phép tịnh tiến
                            // đẩy ra ngoài màn hình — chuột không tới được node
                            // nào, nên không kéo được node mà cũng không hiện
                            // tooltip.
                            constrained: false,
                            // Đang kéo node thì khoá pan, nếu không ô vừa kéo node
                            // vừa trượt cả canvas.
                            panEnabled: _draggedNode == null,
                            boundaryMargin: const EdgeInsets.all(400),
                            minScale: _minScale,
                            maxScale: _maxScale,
                            child: SizedBox(
                              width: _canvasSize,
                              height: _canvasSize,
                              child: MouseRegion(
                                onHover: (e) => _onHover(e.localPosition),
                                onExit: (_) => setState(() {
                                  _hoveredNode = null;
                                  _tooltipAt = null;
                                }),
                                // Listener chứ không phải GestureDetector: cử chỉ
                                // kéo của GestureDetector thắng đấu trường trước
                                // InteractiveViewer nên cả ô mất luôn khả năng
                                // kéo/phóng. Listener không tham gia đấu trường.
                                child: Listener(
                                  onPointerDown: (e) =>
                                      _onPointerDown(e.localPosition),
                                  onPointerMove: (e) =>
                                      _onPointerMove(e.localPosition),
                                  onPointerUp: (e) =>
                                      _onPointerUp(e.localPosition),
                                  child: CustomPaint(
                                    size: const Size(_canvasSize, _canvasSize),
                                    painter: _MiniGraphPainter(
                                      nodes: _nodes,
                                      edges: _edges,
                                      selectedId: selectedId,
                                      hoveredNode: _hoveredNode,
                                      isDark: AppColors.isDark,
                                      viewer: _transformController,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      if (!widget.showHeader)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: _cornerInfo(),
                        ),

                      // Floating Tooltip khi rê chuột vào node
                      if (_hoveredNode != null && _tooltipAt != null)
                        Positioned(
                          left: math.min(
                            _tooltipAt!.dx + 12,
                            math.max(0.0, constraints.maxWidth - 140),
                          ),
                          top: math.max(6.0, _tooltipAt!.dy - 34),
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.isDark
                                    ? const Color(0xFF1E1E28)
                                          .withValues(alpha: 0.95)
                                    : const Color(0xFFFFFFFF)
                                          .withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.5,
                                  ),
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
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// Số môn · số liên kết và nút căn giữa, nổi ở góc khi ô không có header.
  Widget _cornerInfo() {
    return Container(
      padding: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        color: AppColors.obsidianRibbon.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Số môn · số liên kết trong khung',
            child: Text(
              '${_nodes.length} · ${_edges.length}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.obsidianTextMuted,
              ),
            ),
          ),
          _MiniIconBtn(
            icon: Icons.center_focus_strong_outlined,
            tooltip: 'Căn giữa đồ thị',
            onTap: _centerView,
          ),
        ],
      ),
    );
  }

  /// Header của ô: mã khung, số node, và các nút tác vụ.
  Widget _header() {
    final collapse = widget.onToggleCollapse;

    Widget titleRow = Row(
      children: [
        Icon(
          collapse == null ? Icons.account_tree_outlined : Icons.expand_more,
          size: collapse == null ? 13 : 16,
          color: collapse == null
              ? AppColors.primary
              : AppColors.obsidianTextMuted,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.obsidianText,
            ),
          ),
        ),
      ],
    );
    if (collapse != null) {
      titleRow = InkWell(
        onTap: collapse,
        child: Tooltip(message: 'Thu gọn ô này', child: titleRow),
      );
    }

    return Container(
      height: 30,
      padding: EdgeInsets.only(left: collapse == null ? 10 : 4, right: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.obsidianBorder, width: 0.8),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: titleRow),
          // Hiện cả số liên kết: khung nào không có cạnh tiên quyết nào trong
          // CSDL sẽ ra "48 · 0", nhìn là biết ngay dữ liệu thiếu chứ không phải
          // ô vẽ hỏng.
          Tooltip(
            message: 'Số môn · số liên kết trong khung',
            child: Text(
              '${_nodes.length} · ${_edges.length}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.obsidianTextMuted,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _MiniIconBtn(
            icon: Icons.center_focus_strong_outlined,
            tooltip: 'Căn giữa đồ thị',
            onTap: _centerView,
          ),
          if (widget.onOpenLarge != null)
            _MiniIconBtn(
              icon: Icons.open_in_full,
              tooltip: 'Mở khung này trên Graph view lớn',
              onTap: widget.onOpenLarge!,
            ),
          if (widget.onClose != null)
            _MiniIconBtn(
              icon: Icons.close,
              tooltip: 'Gỡ ô này khỏi thanh bên',
              onTap: widget.onClose!,
            ),
        ],
      ),
    );
  }
}

class _MiniNodeSim extends ForceNode {
  final Subject subject;

  TextPainter? _label;
  String? _labelKey;

  _MiniNodeSim({required this.subject, required super.x, required super.y});

  /// Nhãn mã môn, dựng một lần rồi dùng lại: mô phỏng lực vẽ lại mỗi khung
  /// hình, bố trí chữ cho vài chục node ở mỗi khung hình là phí không cần thiết.
  TextPainter label({required bool isDark, required bool emphasis}) {
    final key = '$isDark|$emphasis';
    final cached = _label;
    if (cached != null && _labelKey == key) return cached;

    final code = subject.code;
    final painter = TextPainter(
      text: TextSpan(
        text: code.length > 14 ? '${code.substring(0, 13)}…' : code,
        style: TextStyle(
          fontSize: 11,
          fontWeight: emphasis ? FontWeight.w700 : FontWeight.w600,
          color: emphasis
              ? AppColors.primary
              : (isDark ? const Color(0xFFC3C3D4) : const Color(0xFF474759)),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    _label = painter;
    _labelKey = key;
    return painter;
  }
}

class _MiniEdgeSim implements ForceLink {
  final _MiniNodeSim from;
  final _MiniNodeSim to;
  final bool isHard;

  _MiniEdgeSim({required this.from, required this.to, required this.isHard});

  // Cài thẳng lên lớp cạnh sẵn có thay vì dựng danh sách riêng cho mô phỏng:
  // mỗi khung hình dựng lại vài chục đối tượng chỉ để rồi vứt đi là phí.
  @override
  ForceNode get source => from;

  @override
  ForceNode get target => to;
}

class _MiniGraphPainter extends CustomPainter {
  final List<_MiniNodeSim> nodes;
  final List<_MiniEdgeSim> edges;
  final int? selectedId;
  final _MiniNodeSim? hoveredNode;
  final bool isDark;

  /// Nghe thẳng bộ điều khiển phóng/kéo: widget con của InteractiveViewer không
  /// được dựng lại khi người dùng phóng to, nên không nghe ở đây thì nhãn môn
  /// sẽ không hiện ra đúng lúc.
  final TransformationController viewer;

  /// Dưới mức phóng này thì tên môn chồng lên nhau, không đọc được chữ nào.
  static const double labelMinScale = 0.75;

  _MiniGraphPainter({
    required this.nodes,
    required this.edges,
    required this.selectedId,
    required this.hoveredNode,
    required this.isDark,
    required this.viewer,
  }) : super(repaint: viewer);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Vẽ các cạnh kết nối.
    //
    // Hai loại cạnh phải phân biệt được, khớp đúng chú giải của Graph view lớn:
    // tiên quyết bắt buộc là nét tím đậm hơn, liên quan/tham khảo là nét xám
    // mảnh hơn. Màu xám cũ (0xFFBBBBCC alpha 0.6) gần như tàng hình trên nền
    // sáng 0xFFF5F4F8, nên bản sáng dùng tông đậm hẳn chứ không chỉ đổi alpha.
    final hardEdgePaint = Paint()
      ..color = AppColors.edgePrerequisite.withValues(
        alpha: isDark ? 0.60 : 0.75,
      )
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;

    final softEdgePaint = Paint()
      ..color = isDark
          ? const Color(0xFF6E6E82).withValues(alpha: 0.65)
          : const Color(0xFF8C87A3).withValues(alpha: 0.85)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;

    final activeEdgePaint = Paint()
      ..color = AppColors.primary.withValues(alpha: isDark ? 0.9 : 1.0)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      final isConnectedToSelected =
          selectedId != null &&
          (edge.from.subject.id == selectedId ||
              edge.to.subject.id == selectedId);
      final isConnectedToHovered =
          hoveredNode != null &&
          (edge.from == hoveredNode || edge.to == hoveredNode);

      final paint = (isConnectedToSelected || isConnectedToHovered)
          ? activeEdgePaint
          : (edge.isHard ? hardEdgePaint : softEdgePaint);

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
      // Tô theo học kỳ như Graph view lớn, dùng chung bảng màu để hai chỗ
      // không nói hai chuyện khác nhau về cùng một môn.
      Color nodeColor = AppColors.forSemester(node.subject.semester);

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

    // 3. Tên môn.
    //
    // Chỉ hiện khi đã phóng đủ to, hoặc cho node đang trỏ/chọn: gần 50 mã môn
    // trong một ô rộng 260px thì chữ chồng lên nhau thành một vệt xám.
    final showAll = viewer.value.getMaxScaleOnAxis() >= labelMinScale;
    for (final node in nodes) {
      final isSelected = node.subject.id == selectedId;
      final isHovered = node == hoveredNode;
      if (!showAll && !isSelected && !isHovered) continue;

      final emphasis = isSelected || isHovered;
      final radius = isSelected ? 8.0 : (isHovered ? 7.0 : 5.0);
      final label = node.label(isDark: isDark, emphasis: emphasis);
      label.paint(
        canvas,
        Offset(node.x - label.width / 2, node.y + radius + 3),
      );
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
          child: Icon(icon, size: 13, color: AppColors.obsidianTextMuted),
        ),
      ),
    );
  }
}
