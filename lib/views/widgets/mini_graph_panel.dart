import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/mini_graph_pin.dart';
import '../../models/subject.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import 'sidebar_mini_graph.dart';

/// Nội dung tab "Đồ thị thu nhỏ" của thanh bên: **một** cửa sổ đồ thị, bên
/// trong có nhiều trang — mỗi trang là một khung đã ghim, lật qua lại như tab.
///
/// Bản trước xếp chồng nhiều ô cao 220px: thanh bên hẹp nên mỗi ô đều chật,
/// và mọi ô trong màn hình cùng chạy mô phỏng lực một lúc. Nay chỉ trang đang
/// xem được dựng, chiếm trọn chiều cao còn trống.
///
/// Tách ra khỏi `app_shell.dart` (đã 2.500 dòng) vì đây là một khối tự chứa —
/// và vì tách rồi thì vùng thả kéo mới kiểm thử được mà không phải dựng cả
/// khung ứng dụng cùng CSDL.
class MiniGraphPanel extends StatefulWidget {
  /// Bấm một node trong cửa sổ thu nhỏ.
  final ValueChanged<Subject>? onSelectSubject;

  /// Mở Graph view lớn (tab 0 của ribbon) sau khi đã chọn khung.
  final VoidCallback? onOpenGraphView;

  /// Tách cửa sổ ra thành lớp nổi trên màn hình. `null` thì không hiện nút —
  /// chính cửa sổ nổi dùng panel này mà không truyền, vì nó đã nổi rồi.
  final VoidCallback? onPopOut;

  const MiniGraphPanel({
    super.key,
    this.onSelectSubject,
    this.onOpenGraphView,
    this.onPopOut,
  });

  static const Key popOutKey = Key('mini-graph-pop-out');

  /// Khoá của vùng nhận thả, để widget test tìm được đúng chỗ cần buông chuột.
  static const Key dropTargetKey = Key('mini-graph-drop-target');

  /// Khoá của chỉ số trang "2/4" và nút mở danh sách trang, cho widget test.
  static const Key pageIndicatorKey = Key('mini-graph-page-indicator');
  static const Key pageMenuKey = Key('mini-graph-page-menu');
  static const Key previousKey = Key('mini-graph-prev');
  static const Key nextKey = Key('mini-graph-next');

  /// Thời gian chuyển cảnh giữa hai trang.
  static const Duration pageTransition = Duration(milliseconds: 200);

  /// Ghim một khung rồi báo cho người dùng khi đã đủ trang.
  ///
  /// Dùng chung cho mọi lối ghim — thả vào cửa sổ, thả lên icon tab, mục menu
  /// của Graph view — để cả ba cùng một luật và cùng một câu báo.
  static Future<MiniGraphPinResult> pinWithFeedback(
    BuildContext context,
    String? code,
  ) async {
    final result = await AppState.instance.pinMiniGraph(code);
    if (result == MiniGraphPinResult.full && context.mounted) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Đã đủ ${MiniGraphPins.maxPages} trang, hãy gỡ bớt',
            ),
            duration: Duration(seconds: 3),
          ),
        );
    }
    return result;
  }

  @override
  State<MiniGraphPanel> createState() => _MiniGraphPanelState();
}

class _MiniGraphPanelState extends State<MiniGraphPanel> {
  /// Chuột đang nằm trên cửa sổ. Ctrl+←/→ chỉ lật trang khi đó, để phím tắt
  /// không cướp mất Ctrl+← (nhảy từ) của ô soạn ghi chú đang mở bên cạnh.
  bool _hovering = false;

  /// Nháy viền khi thả vào một khung đã ghim: không có trang mới nào hiện ra,
  /// thiếu tín hiệu này thì người dùng tưởng thả trượt.
  bool _flash = false;
  Timer? _flashTimer;

  /// Một cú vuốt touchpad bắn ra cả chục sự kiện cuộn liên tiếp; không chặn
  /// thì một cú vuốt lật qua mấy trang liền.
  DateTime _lastSwipeFlip = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _swipeCooldown = Duration(milliseconds: 350);
  static const double _swipeThreshold = 15.0;

  @override
  void initState() {
    super.initState();
    // Bắt phím ở tầng HardwareKeyboard thay vì bọc Focus: cửa sổ thu nhỏ
    // không giành focus bàn phím, nên chỉ cần rê chuột vào là dùng được phím
    // tắt, không phải bấm vào đồ thị trước.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _flashTimer?.cancel();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (!_hovering || event is KeyUpEvent) return false;
    if (!HardwareKeyboard.instance.isControlPressed) return false;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      AppState.instance.previousMiniGraphPage();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      AppState.instance.nextMiniGraphPage();
      return true;
    }
    return false;
  }

  /// Chỉ nhận cuộn **ngang** (vuốt hai ngón trên touchpad): cuộn dọc đang là
  /// thao tác zoom của đồ thị bên trong, lật trang theo nó thì không zoom được.
  ///
  /// Đọc thẳng sự kiện chứ không đăng ký qua `pointerSignalResolver`: bộ giải
  /// đó chỉ trao sự kiện cho một người nhận, và InteractiveViewer bên trong đã
  /// đăng ký trước để zoom.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    if (dx.abs() < _swipeThreshold || dx.abs() < dy.abs() * 1.5) return;

    final now = DateTime.now();
    if (now.difference(_lastSwipeFlip) < _swipeCooldown) return;
    _lastSwipeFlip = now;

    if (dx > 0) {
      AppState.instance.nextMiniGraphPage();
    } else {
      AppState.instance.previousMiniGraphPage();
    }
  }

  Future<void> _onDrop(String? code) async {
    final result = await MiniGraphPanel.pinWithFeedback(context, code);
    if (result != MiniGraphPinResult.switched || !mounted) return;
    _flashTimer?.cancel();
    setState(() => _flash = true);
    _flashTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  void _openLarge(String? code) {
    AppState.instance.setActiveCurriculum(code);
    widget.onOpenGraphView?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final pinned = state.pinnedMiniGraphs;

        return DragTarget<MiniGraphDragData>(
          key: MiniGraphPanel.dropTargetKey,
          onAcceptWithDetails: (details) =>
              _onDrop(details.data.curriculumCode),
          builder: (context, candidate, rejected) {
            final isHovering = candidate.isNotEmpty;
            final highlight = isHovering || _flash;
            return MouseRegion(
              onEnter: (_) => _hovering = true,
              onExit: (_) => _hovering = false,
              child: Listener(
                onPointerSignal: _onPointerSignal,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    // Viền sáng lên khi đang kéo tới, để người dùng biết chắc
                    // thả vào đây là được chứ không phải đoán.
                    border: Border.all(
                      color: highlight
                          ? AppColors.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                    color: isHovering
                        ? AppColors.primary.withValues(alpha: 0.06)
                        : null,
                  ),
                  child: pinned.isEmpty
                      ? _emptyState()
                      : _window(pinned, state.activeMiniGraphIndex),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Chưa ghim gì: vẫn hiện đồ thị của khung đang chọn như trước đây, kèm một
  /// dòng chỉ cho người dùng biết có thể ghim thêm bằng cách nào.
  Widget _emptyState() {
    final code = AppState.instance.activeCurriculumCode;
    return Column(
      children: [
        Expanded(
          child: SidebarMiniGraph(
            key: ValueKey('mini-preview-$code'),
            curriculumCode: code,
            onSelectSubject: widget.onSelectSubject,
            onOpenLarge: () => _openLarge(code),
          ),
        ),
        _hint(),
      ],
    );
  }

  Widget _hint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.obsidianRibbon,
        border: Border(
          top: BorderSide(color: AppColors.obsidianBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.push_pin_outlined,
            size: 13,
            color: AppColors.obsidianTextMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Kéo Graph view vào đây để ghim thành một trang',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.35,
                color: AppColors.obsidianTextMuted,
              ),
            ),
          ),
          if (widget.onPopOut != null)
            _HeaderBtn(
              key: MiniGraphPanel.popOutKey,
              icon: Icons.picture_in_picture_alt_outlined,
              tooltip: 'Tách thành cửa sổ nổi (theo bạn qua mọi trang)',
              onTap: widget.onPopOut!,
            ),
        ],
      ),
    );
  }

  Widget _window(List<String?> pinned, int active) {
    final code = pinned[active];
    return Column(
      children: [
        _header(pinned, active),
        Expanded(
          child: ClipRect(
            child: AnimatedSwitcher(
              duration: MiniGraphPanel.pageTransition,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, animation) =>
                  _PageTransition(animation: animation, child: child),
              // Khoá theo mã khung: đổi trang thì State cũ bị huỷ, trang mới
              // dựng mô phỏng từ đúng GraphLayoutCache của khung mới thay vì
              // kéo theo vị trí node của khung trước.
              child: SidebarMiniGraph(
                key: ValueKey<String?>(code),
                curriculumCode: code,
                showHeader: false,
                onSelectSubject: widget.onSelectSubject,
                onOpenLarge: () => _openLarge(code),
              ),
            ),
          ),
        ),
        if (pinned.length > 1) _dots(pinned, active),
      ],
    );
  }

  String _labelOf(String? code) => code ?? 'Toàn bộ môn';

  /// Tên đầy đủ của khung cho danh sách trang; mã khung đứng một mình trên
  /// header đã đủ nhận ra, còn trong danh sách thì cần thêm tên để phân biệt
  /// các khóa (`BIT_SE_K19B` / `BIT_SE_K20A`).
  String _fullLabelOf(String? code) {
    if (code == null) return 'Toàn bộ môn';
    for (final g in AppState.instance.curriculumGroups) {
      if (g.code == code && g.name.trim().isNotEmpty && g.name != code) {
        return '$code — ${g.name}';
      }
    }
    return code;
  }

  Widget _header(List<String?> pinned, int active) {
    final state = AppState.instance;
    final many = pinned.length > 1;
    final code = pinned[active];

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.obsidianBorder, width: 0.8),
        ),
      ),
      child: Row(
        children: [
          if (many)
            _HeaderBtn(
              key: MiniGraphPanel.previousKey,
              icon: Icons.chevron_left,
              tooltip: 'Trang trước (Ctrl+←)',
              onTap: state.previousMiniGraphPage,
            )
          else
            const SizedBox(width: 6),
          Expanded(
            child: PopupMenuButton<int>(
              key: MiniGraphPanel.pageMenuKey,
              tooltip: 'Chọn trang',
              padding: EdgeInsets.zero,
              position: PopupMenuPosition.under,
              color: AppColors.obsidianRibbon,
              onSelected: state.selectMiniGraphPage,
              itemBuilder: (context) => [
                for (var i = 0; i < pinned.length; i++)
                  PopupMenuItem<int>(
                    value: i,
                    height: 34,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          child: i == active
                              ? const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: AppColors.primary,
                                )
                              : null,
                        ),
                        Text(
                          '${i + 1}. ',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.obsidianTextMuted,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            _fullLabelOf(pinned[i]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: i == active
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: AppColors.obsidianText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              child: Row(
                children: [
                  const Icon(
                    Icons.account_tree_outlined,
                    size: 13,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      _labelOf(code),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidianText,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: AppColors.obsidianTextMuted,
                  ),
                ],
              ),
            ),
          ),
          if (many)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                '${active + 1}/${pinned.length}',
                key: MiniGraphPanel.pageIndicatorKey,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.obsidianTextMuted,
                ),
              ),
            ),
          if (many)
            _HeaderBtn(
              key: MiniGraphPanel.nextKey,
              icon: Icons.chevron_right,
              tooltip: 'Trang sau (Ctrl+→)',
              onTap: state.nextMiniGraphPage,
            ),
          if (widget.onPopOut != null)
            _HeaderBtn(
              key: MiniGraphPanel.popOutKey,
              icon: Icons.picture_in_picture_alt_outlined,
              tooltip: 'Tách thành cửa sổ nổi (theo bạn qua mọi trang)',
              onTap: widget.onPopOut!,
            ),
          _HeaderBtn(
            icon: Icons.open_in_full,
            tooltip: 'Mở khung này trên Graph view lớn',
            onTap: () => _openLarge(code),
          ),
          _HeaderBtn(
            icon: Icons.close,
            tooltip: 'Gỡ trang này khỏi cửa sổ',
            onTap: () => state.unpinMiniGraph(code),
          ),
        ],
      ),
    );
  }

  /// Dải chấm trang ở chân cửa sổ. Kéo một chấm thả lên chấm khác để đổi thứ
  /// tự trang — thao tác đi qua `reorderMiniGraphs` như mọi lối khác.
  Widget _dots(List<String?> pinned, int active) {
    return Container(
      height: 20,
      decoration: BoxDecoration(
        color: AppColors.obsidianRibbon,
        border: Border(
          top: BorderSide(color: AppColors.obsidianBorder, width: 0.8),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < pinned.length; i++)
            _PageDot(
              key: ValueKey('mini-graph-dot-$i'),
              index: i,
              label: _fullLabelOf(pinned[i]),
              active: i == active,
            ),
        ],
      ),
    );
  }
}

/// Mờ dần khi chuyển trang, và **tắt ticker của trang đang rời đi** ngay từ
/// khung hình đầu của hiệu ứng: 200ms đó trang cũ vẫn còn trong cây widget,
/// để nó chạy tiếp mô phỏng lực là hai trang cùng ngốn CPU.
class _PageTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _PageTransition({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => TickerMode(
        enabled: animation.status != AnimationStatus.reverse &&
            animation.status != AnimationStatus.dismissed,
        child: child!,
      ),
      child: FadeTransition(opacity: animation, child: child),
    );
  }
}

class _PageDot extends StatelessWidget {
  final int index;
  final String label;
  final bool active;

  const _PageDot({
    super.key,
    required this.index,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final dot = Container(
      width: 16,
      height: 20,
      alignment: Alignment.center,
      child: AnimatedContainer(
        duration: MiniGraphPanel.pageTransition,
        width: active ? 12 : 6,
        height: 6,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.obsidianTextMuted,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      // `reorder` nhận chỉ số kiểu ReorderableListView (tính trên danh sách
      // chưa gỡ phần tử), nên kéo sang phải phải cộng một.
      onAcceptWithDetails: (d) => state.reorderMiniGraphs(
        d.data,
        index > d.data ? index + 1 : index,
      ),
      builder: (context, candidate, _) => Draggable<int>(
        data: index,
        axis: Axis.horizontal,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: 12,
            height: 6,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        child: Tooltip(
          message: '${index + 1}. $label',
          waitDuration: const Duration(milliseconds: 300),
          child: InkWell(
            onTap: () => state.selectMiniGraphPage(index),
            child: candidate.isEmpty
                ? dot
                : DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: AppColors.primary, width: 2),
                      ),
                    ),
                    child: dot,
                  ),
          ),
        ),
      ),
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeaderBtn({
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
          child: Icon(icon, size: 14, color: AppColors.obsidianTextMuted),
        ),
      ),
    );
  }
}
