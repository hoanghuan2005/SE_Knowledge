import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/subject.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import 'mini_graph_panel.dart';

/// Cửa sổ đồ thị thu nhỏ nổi đè lên giao diện, kéo đi đâu cũng được.
///
/// Nằm ở tầng `AppShell` (trên cả thanh bên lẫn vùng làm việc) nên chuyển
/// trang — Graph view, Khung chương trình, Vault, AI, một ghi chú đang mở —
/// cửa sổ vẫn ở nguyên chỗ, giữ đúng trang đang xem. Nội dung chính là
/// [MiniGraphPanel] y như trong thanh bên: cùng các trang, cùng luật ghim,
/// cùng vùng nhận thả tab "Graph view".
///
/// Phải đặt làm con trực tiếp của một `Stack` phủ kín vùng ứng dụng: widget
/// trả về `Positioned`, và [area] là kích thước của chính `Stack` đó.
class FloatingMiniGraphWindow extends StatefulWidget {
  /// Kích thước vùng chứa, để kẹp cửa sổ không bị kéo lọt ra ngoài màn hình.
  final Size area;

  final ValueChanged<Subject>? onSelectSubject;
  final VoidCallback? onOpenGraphView;

  const FloatingMiniGraphWindow({
    super.key,
    required this.area,
    this.onSelectSubject,
    this.onOpenGraphView,
  });

  static const Key titleBarKey = Key('floating-mini-graph-title');
  static const Key dockKey = Key('floating-mini-graph-dock');
  static const Key collapseKey = Key('floating-mini-graph-collapse');
  static const Key resizeKey = Key('floating-mini-graph-resize');

  static const Size defaultSize = Size(340, 380);
  static const Size minSize = Size(220, 200);
  static const double titleHeight = 26;

  /// Khoảng cách tới mép khi tự đặt cửa sổ lần đầu.
  static const double margin = 16;

  @override
  State<FloatingMiniGraphWindow> createState() =>
      _FloatingMiniGraphWindowState();
}

class _FloatingMiniGraphWindowState extends State<FloatingMiniGraphWindow> {
  late Rect _rect;

  /// Thu gọn chỉ còn thanh tiêu đề. Khi đó đồ thị bị gỡ khỏi cây widget nên
  /// ticker mô phỏng lực dừng hẳn — cửa sổ nằm chờ không tốn CPU.
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    final saved = AppState.instance.miniGraphFloatRect;
    const size = FloatingMiniGraphWindow.defaultSize;
    const m = FloatingMiniGraphWindow.margin;
    // Lần đầu: góc dưới bên phải, chỗ ít che nội dung chính nhất.
    _rect =
        saved ??
        Rect.fromLTWH(
          widget.area.width - size.width - m,
          widget.area.height - size.height - m,
          size.width,
          size.height,
        );
  }

  /// Kẹp cửa sổ vào trong vùng chứa. Chạy lại mỗi lần build nên cửa sổ tự
  /// dạt vào trong khi người dùng thu nhỏ cửa sổ ứng dụng, thay vì mất hút
  /// ngoài mép và không còn chỗ nào để nắm kéo về.
  Rect _clamp(Rect r) {
    final area = widget.area;
    const min = FloatingMiniGraphWindow.minSize;
    final w = r.width.clamp(
      min.width,
      area.width < min.width ? min.width : area.width,
    );
    final h = r.height.clamp(
      min.height,
      area.height < min.height ? min.height : area.height,
    );
    final maxLeft = area.width - w;
    final maxTop = area.height - h;
    return Rect.fromLTWH(
      r.left.clamp(0.0, maxLeft < 0 ? 0.0 : maxLeft),
      r.top.clamp(0.0, maxTop < 0 ? 0.0 : maxTop),
      w,
      h,
    );
  }

  void _move(DragUpdateDetails d) =>
      setState(() => _rect = _clamp(_rect.shift(d.delta)));

  void _resize(DragUpdateDetails d) => setState(
    () => _rect = _clamp(
      Rect.fromLTWH(
        _rect.left,
        _rect.top,
        _rect.width + d.delta.dx,
        _rect.height + d.delta.dy,
      ),
    ),
  );

  /// Ghi xuống đĩa một lần khi thả chuột, không ghi theo từng pixel.
  void _save([DragEndDetails? _]) =>
      AppState.instance.saveMiniGraphFloatRect(_rect);

  @override
  Widget build(BuildContext context) {
    final rect = _clamp(_rect);
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: _collapsed
          ? FloatingMiniGraphWindow.titleHeight + 2
          : rect.height,
      child: Material(
        elevation: 12,
        color: AppColors.shellSidebar,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.shellBorder, width: 1),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  _titleBar(),
                  if (!_collapsed)
                    Expanded(
                      child: MiniGraphPanel(
                        onSelectSubject: widget.onSelectSubject,
                        onOpenGraphView: widget.onOpenGraphView,
                      ),
                    ),
                ],
              ),
              if (!_collapsed)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeDownRight,
                    child: GestureDetector(
                      key: FloatingMiniGraphWindow.resizeKey,
                      behavior: HitTestBehavior.opaque,
                      // Bắt đầu tính từ điểm bấm: mặc định Flutter nuốt ~20px đầu làm ngưỡng
                      // nhận kéo, cửa sổ bị tụt lại sau con trỏ suốt cú kéo.
                      dragStartBehavior: DragStartBehavior.down,
                      onPanUpdate: _resize,
                      onPanEnd: _save,
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: Icon(
                          Icons.south_east,
                          size: 11,
                          color: AppColors.obsidianTextMuted,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Thanh tiêu đề là tay nắm để kéo cửa sổ. Tách hẳn khỏi header của
  /// [MiniGraphPanel]: header đó đã kín nút lật trang và danh sách trang, lấy
  /// nó làm tay nắm thì bấm nút nào cũng dễ thành kéo nhầm.
  Widget _titleBar() {
    final state = AppState.instance;
    final pages = state.pinnedMiniGraphs.length;
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        key: FloatingMiniGraphWindow.titleBarKey,
        behavior: HitTestBehavior.opaque,
        // Bắt đầu tính từ điểm bấm: mặc định Flutter nuốt ~20px đầu làm ngưỡng
        // nhận kéo, cửa sổ bị tụt lại sau con trỏ suốt cú kéo.
        dragStartBehavior: DragStartBehavior.down,
        onPanUpdate: _move,
        onPanEnd: _save,
        child: Container(
          height: FloatingMiniGraphWindow.titleHeight,
          padding: const EdgeInsets.only(left: 6, right: 2),
          color: AppColors.obsidianRibbon,
          child: Row(
            children: [
              Icon(
                Icons.drag_indicator,
                size: 14,
                color: AppColors.obsidianTextMuted,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _collapsed && pages > 0
                      ? 'Đồ thị thu nhỏ · ${state.activeMiniGraphCode ?? "Toàn bộ môn"}'
                      : 'Đồ thị thu nhỏ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.obsidianTextMuted,
                  ),
                ),
              ),
              _TitleBtn(
                key: FloatingMiniGraphWindow.collapseKey,
                icon: _collapsed ? Icons.unfold_more : Icons.remove,
                tooltip: _collapsed ? 'Mở ra' : 'Thu gọn',
                onTap: () => setState(() => _collapsed = !_collapsed),
              ),
              _TitleBtn(
                key: FloatingMiniGraphWindow.dockKey,
                icon: Icons.view_sidebar_outlined,
                tooltip: 'Thu về thanh bên',
                onTap: () => state.setMiniGraphFloating(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _TitleBtn({
    super.key,
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
