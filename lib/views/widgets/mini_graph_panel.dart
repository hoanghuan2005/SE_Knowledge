import 'package:flutter/material.dart';

import '../../models/mini_graph_pin.dart';
import '../../models/subject.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import 'sidebar_mini_graph.dart';

/// Nội dung tab "Đồ thị thu nhỏ" của thanh bên: danh sách các ô đã ghim.
///
/// Tách ra khỏi `app_shell.dart` (đã 2.500 dòng) vì đây là một khối tự chứa —
/// và vì tách rồi thì vùng thả kéo mới kiểm thử được mà không phải dựng cả
/// khung ứng dụng cùng CSDL.
class MiniGraphPanel extends StatelessWidget {
  /// Bấm một node trong ô thu nhỏ.
  final ValueChanged<Subject>? onSelectSubject;

  /// Mở Graph view lớn (tab 0 của ribbon) sau khi đã chọn khung.
  final VoidCallback? onOpenGraphView;

  const MiniGraphPanel({super.key, this.onSelectSubject, this.onOpenGraphView});

  /// Khoá của vùng nhận thả, để widget test tìm được đúng chỗ cần buông chuột.
  static const Key dropTargetKey = Key('mini-graph-drop-target');

  /// Chiều cao một ô. Đủ thấy hình thù đồ thị mà vẫn xếp được 2–3 ô trong một
  /// màn hình thanh bên.
  static const double cardHeight = 220.0;

  void _openLarge(String? code) {
    AppState.instance.setActiveCurriculum(code);
    onOpenGraphView?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final pinned = AppState.instance.pinnedMiniGraphs;

        return DragTarget<MiniGraphDragData>(
          key: dropTargetKey,
          onAcceptWithDetails: (details) =>
              AppState.instance.pinMiniGraph(details.data.curriculumCode),
          builder: (context, candidate, rejected) {
            final isHovering = candidate.isNotEmpty;
            return Container(
              decoration: BoxDecoration(
                // Viền sáng lên khi đang kéo tới, để người dùng biết chắc thả
                // vào đây là được chứ không phải đoán.
                border: Border.all(
                  color: isHovering ? AppColors.primary : Colors.transparent,
                  width: 2,
                ),
                color: isHovering
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : null,
              ),
              child: pinned.isEmpty
                  ? _emptyState(context)
                  : _pinnedList(pinned),
            );
          },
        );
      },
    );
  }

  /// Chưa ghim gì: vẫn hiện một ô của khung đang chọn như trước đây, kèm một
  /// dòng chỉ cho người dùng biết có thể ghim thêm bằng cách nào.
  Widget _emptyState(BuildContext context) {
    final code = AppState.instance.activeCurriculumCode;
    return Column(
      children: [
        Expanded(
          child: SidebarMiniGraph(
            key: ValueKey('mini-preview-$code'),
            curriculumCode: code,
            onSelectSubject: onSelectSubject,
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
              'Kéo Graph view vào đây để ghim',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.35,
                color: AppColors.obsidianTextMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pinnedList(List<String?> pinned) {
    // ListView.builder tự huỷ ô cuộn ra ngoài màn hình, nên ticker mô phỏng
    // lực của ô đó cũng dừng theo — không có ô khuất nào còn ngốn CPU.
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: pinned.length,
      itemBuilder: (context, index) {
        final code = pinned[index];
        return _PinnedMiniGraphCard(
          key: ValueKey('mini-pin-${code ?? "__ALL__"}'),
          curriculumCode: code,
          onSelectSubject: onSelectSubject,
          onOpenLarge: () => _openLarge(code),
          onClose: () => AppState.instance.unpinMiniGraph(code),
        );
      },
    );
  }
}

/// Một ô đã ghim: thu gọn được, và khi thu gọn thì đồ thị bên trong bị gỡ hẳn
/// khỏi cây widget chứ không chỉ bị che — đó là cách dừng ticker mô phỏng lực
/// của ô đó mà không cần thêm cờ tạm dừng nào.
class _PinnedMiniGraphCard extends StatefulWidget {
  final String? curriculumCode;
  final ValueChanged<Subject>? onSelectSubject;
  final VoidCallback onOpenLarge;
  final VoidCallback onClose;

  const _PinnedMiniGraphCard({
    super.key,
    required this.curriculumCode,
    required this.onSelectSubject,
    required this.onOpenLarge,
    required this.onClose,
  });

  @override
  State<_PinnedMiniGraphCard> createState() => _PinnedMiniGraphCardState();
}

class _PinnedMiniGraphCardState extends State<_PinnedMiniGraphCard> {
  bool _collapsed = false;

  String get _title => widget.curriculumCode ?? 'Toàn bộ môn';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.obsidianBorder, width: 1),
        ),
      ),
      child: _collapsed
          ? _collapsedHeader()
          : SizedBox(
              height: MiniGraphPanel.cardHeight,
              child: SidebarMiniGraph(
                curriculumCode: widget.curriculumCode,
                onSelectSubject: widget.onSelectSubject,
                onOpenLarge: widget.onOpenLarge,
                onClose: widget.onClose,
                onToggleCollapse: () => setState(() => _collapsed = true),
              ),
            ),
    );
  }

  Widget _collapsedHeader() {
    // Số node đọc thẳng từ AppState: cùng một con số với lúc mở, khỏi phải
    // dựng cả đồ thị chỉ để đếm.
    final count = AppState.instance
        .graphFor(widget.curriculumCode)
        .subjects
        .length;

    return InkWell(
      onTap: () => setState(() => _collapsed = false),
      child: SizedBox(
        height: 30,
        child: Row(
          children: [
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: AppColors.obsidianTextMuted,
            ),
            const SizedBox(width: 2),
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
            Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.obsidianTextMuted,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 13),
              color: AppColors.obsidianTextMuted,
              splashRadius: 12,
              tooltip: 'Gỡ ô này khỏi thanh bên',
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }
}
