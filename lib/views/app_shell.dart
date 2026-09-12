import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/subject.dart';
import '../services/chat_session_service.dart';
import '../state/app_state.dart';
import '../utils/app_colors.dart';
import 'chat/ai_chat_page.dart';
import 'graph/graph_page.dart';
import 'notes/obsidian_note_editor_view.dart';
import 'settings/settings_page.dart';
import 'subjects/subject_form_dialog.dart';
import 'subjects/subjects_page.dart';
import 'vault/vault_page.dart';
import 'widgets/subject_detail_panel.dart';

/// Intent để bắt phím tắt Ctrl+B toggle thanh bên.
class _ToggleSidebarIntent extends Intent {
  const _ToggleSidebarIntent();
}

/// Khung ứng dụng phong cách Obsidian:
/// - Thanh Ribbon hẹp ở mép trái (Activity Bar)
/// - Thanh bên mở rộng/thu gọn siêu mượt mà (Animated Sidebar)
/// - Nội dung Sidebar tự động thay đổi theo từng tab:
///   + Đồ thị / Môn học: Cây thư mục Tệp & Môn học theo kỳ
///   + Trợ lý AI: Quản lý và lưu trữ lịch sử các đoạn chat
///   + Vault: Quản lý thư mục Obsidian Vault
///   + Cài đặt: Danh mục cấu hình hệ thống
/// - Thanh Tab Bar điều hướng phong cách Obsidian Workspace
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _isSidebarOpen = true;
  String _searchQuery = '';
  final Set<int> _collapsedSemesters = {};
  int _sidebarTab = 0; // 0: Files, 1: Search, 2: Bookmarks

  final List<int> _history = [0];
  int _historyIndex = 0;

  static const List<String> _tabTitles = [
    'Graph view',
    'Danh sách môn học',
    'Obsidian Vault',
    'Trợ lý học tập AI',
    'Cài đặt hệ thống',
  ];

  static const List<IconData> _tabIcons = [
    Icons.hub,
    Icons.article_outlined,
    Icons.folder_copy_outlined,
    Icons.auto_awesome,
    Icons.settings_outlined,
  ];

  void _switchTab(int newIndex) {
    AppState.instance.setActiveNote(null);
    if (newIndex == _index) return;
    setState(() {
      _index = newIndex;
      if (_historyIndex < _history.length - 1) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(newIndex);
      _historyIndex = _history.length - 1;
    });
  }

  void _goBack() {
    if (_historyIndex > 0) {
      setState(() {
        _historyIndex--;
        _index = _history[_historyIndex];
      });
    }
  }

  void _goForward() {
    if (_historyIndex < _history.length - 1) {
      setState(() {
        _historyIndex++;
        _index = _history[_historyIndex];
      });
    }
  }

  void _toggleSidebar() {
    setState(() => _isSidebarOpen = !_isSidebarOpen);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        return Shortcuts(
          shortcuts: {
            LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyB):
                const _ToggleSidebarIntent(),
          },
          child: Actions(
            actions: {
              _ToggleSidebarIntent: CallbackAction<_ToggleSidebarIntent>(
                onInvoke: (_) => _toggleSidebar(),
              ),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                backgroundColor: AppColors.shellWorkspace,
                body: Row(
              children: [
                // 1. Thanh Ribbon mép ngoài cùng (Obsidian Activity Bar)
                _ObsidianRibbon(
                  currentIndex: _index,
                  isSidebarOpen: _isSidebarOpen,
                  onToggleSidebar: _toggleSidebar,
                  onSelectTab: (idx) {
                    _switchTab(idx);
                    if (!_isSidebarOpen) {
                      setState(() => _isSidebarOpen = true);
                    }
                  },
                  onNewSubject: () => SubjectFormDialog.show(context),
                ),

                // 2. Thanh bên thu/mở mượt mà - tự đổi nội dung theo tab đang mở
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeInOutCubic,
                  width: _isSidebarOpen ? 260 : 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.shellSidebar,
                      border: Border(
                        right: BorderSide(color: AppColors.shellBorder, width: 1),
                      ),
                    ),
                    child: ClipRect(
                      child: OverflowBox(
                        minWidth: 260,
                        maxWidth: 260,
                        alignment: Alignment.topLeft,
                        child: _ObsidianSidebarPanel(
                          mainIndex: _index,
                          activeTabIndex: _sidebarTab,
                          searchQuery: _searchQuery,
                          collapsedSemesters: _collapsedSemesters,
                          onTabChanged: (tab) => setState(() => _sidebarTab = tab),
                          onSearchChanged: (q) => setState(() => _searchQuery = q),
                          onToggleSemester: (sem) {
                            setState(() {
                              if (_collapsedSemesters.contains(sem)) {
                                _collapsedSemesters.remove(sem);
                              } else {
                                _collapsedSemesters.add(sem);
                              }
                            });
                          },
                          onCollapseAllSemesters: (semesters) {
                            setState(() {
                              if (_collapsedSemesters.length == semesters.length) {
                                _collapsedSemesters.clear();
                              } else {
                                _collapsedSemesters.addAll(semesters);
                              }
                            });
                          },
                          onSelectSubject: (subject) {
                            AppState.instance.select(subject.id);
                            AppState.instance.setActiveNote(null);
                            _switchTab(0); // Chuyển về Graph view để xem node
                          },
                          onOpenVault: () => _switchTab(2),
                          onCloseSidebar: _toggleSidebar,
                          onNewSubject: () => SubjectFormDialog.show(context),
                          onNavigateToTab: _switchTab,
                        ),
                      ),
                    ),
                  ),
                ),

                // 3. Vùng làm việc chính kèm Top Tab Bar kiểu Obsidian
                Expanded(
                  child: Column(
                    children: [
                      _ObsidianWorkspaceTabBar(
                        currentTabTitle: _tabTitles[_index],
                        currentTabIcon: _tabIcons[_index],
                        canGoBack: _historyIndex > 0,
                        canGoForward: _historyIndex < _history.length - 1,
                        isSidebarOpen: _isSidebarOpen,
                        openNotes: AppState.instance.openNoteTabs,
                        activeNote: AppState.instance.activeNote,
                        currentIndex: _index,
                        onGoBack: _goBack,
                        onGoForward: _goForward,
                        onToggleSidebar: _toggleSidebar,
                        onSelectGraphTab: () {
                          AppState.instance.setActiveNote(null);
                          _switchTab(0);
                        },
                        onSelectPageTab: (idx) {
                          AppState.instance.setActiveNote(null);
                          _switchTab(idx);
                        },
                        onClosePageTab: (idx) => _switchTab(0),
                        onSelectNoteTab: (note) => AppState.instance.setActiveNote(note),
                        onCloseNoteTab: (note) => AppState.instance.closeNoteTab(note),
                        onNewTab: () => SubjectFormDialog.show(context),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: AppState.instance.activeNote != null
                                  ? ObsidianNoteEditorView(
                                      key: ValueKey(
                                        AppState.instance.activeNote!.id ??
                                            AppState.instance.activeNote!.code,
                                      ),
                                      subject: AppState.instance.activeNote!,
                                    )
                                  : IndexedStack(
                                      key: ValueKey(AppState.instance.isDark),
                                      index: _index,
                                      children: const [
                                        GraphPage(),
                                        SubjectsPage(),
                                        VaultPage(),
                                        AiChatPage(),
                                        SettingsPage(),
                                      ],
                                    ),
                            ),
                            if (AppState.instance.activeNote != null || _index == 0)
                              const SubjectDetailPanel(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  },
);
}
}

// ============================================================================
// 1. OBSIDIAN LEFT RIBBON (Activity Bar)
// ============================================================================
class _ObsidianRibbon extends StatelessWidget {
  final int currentIndex;
  final bool isSidebarOpen;
  final VoidCallback onToggleSidebar;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onNewSubject;

  const _ObsidianRibbon({
    required this.currentIndex,
    required this.isSidebarOpen,
    required this.onToggleSidebar,
    required this.onSelectTab,
    required this.onNewSubject,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppState.instance.isDark;
    return Container(
      width: 44,
      decoration: BoxDecoration(
        color: AppColors.shellRibbon,
        border: Border(
          right: BorderSide(color: AppColors.shellBorder, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),

          // Nút đóng/mở sidebar (Icon đầu tiên ở trên như Obsidian)
          _RibbonIconButton(
            icon: isSidebarOpen ? Icons.view_sidebar : Icons.view_sidebar_outlined,
            tooltip: isSidebarOpen ? 'Thu gọn thanh bên (Ctrl+B)' : 'Mở thanh bên (Ctrl+B)',
            isActive: isSidebarOpen,
            onTap: onToggleSidebar,
          ),

          const SizedBox(height: 10),
          Divider(height: 1, color: AppColors.shellBorder),
          const SizedBox(height: 10),

          // Các icon điều hướng chính
          _RibbonIconButton(
            icon: currentIndex == 0 ? Icons.hub : Icons.hub_outlined,
            tooltip: 'Bản đồ tri thức (Graph view)',
            isSelected: currentIndex == 0,
            onTap: () => onSelectTab(0),
          ),
          const SizedBox(height: 6),
          _RibbonIconButton(
            icon: currentIndex == 1 ? Icons.article : Icons.article_outlined,
            tooltip: 'Danh sách môn học',
            isSelected: currentIndex == 1,
            onTap: () => onSelectTab(1),
          ),
          const SizedBox(height: 6),
          _RibbonIconButton(
            icon: currentIndex == 2 ? Icons.folder_copy : Icons.folder_copy_outlined,
            tooltip: 'Obsidian Vault',
            isSelected: currentIndex == 2,
            onTap: () => onSelectTab(2),
          ),
          const SizedBox(height: 6),
          _RibbonIconButton(
            icon: currentIndex == 3 ? Icons.auto_awesome : Icons.auto_awesome_outlined,
            tooltip: 'Trợ lý học tập AI (Đoạn chat)',
            isSelected: currentIndex == 3,
            onTap: () => onSelectTab(3),
          ),

          const Spacer(),

          // Nút tạo môn nhanh
          _RibbonIconButton(
            icon: Icons.add_rounded,
            tooltip: 'Thêm môn học mới',
            onTap: onNewSubject,
          ),
          const SizedBox(height: 6),

          // Nút chuyển đổi Theme (Dark / Light)
          _RibbonIconButton(
            icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            tooltip: isDark
                ? 'Giao diện: Tối (Bấm để chuyển Sáng)'
                : 'Giao diện: Sáng (Bấm để chuyển Tối)',
            onTap: () => AppState.instance.toggleTheme(),
          ),
          const SizedBox(height: 6),

          // Cài đặt
          _RibbonIconButton(
            icon: currentIndex == 4 ? Icons.settings : Icons.settings_outlined,
            tooltip: 'Cài đặt',
            isSelected: currentIndex == 4,
            onTap: () => onSelectTab(4),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _RibbonIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isSelected;
  final bool isActive;

  const _RibbonIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isSelected = false,
    this.isActive = false,
  });

  @override
  State<_RibbonIconButton> createState() => _RibbonIconButtonState();
}

class _RibbonIconButtonState extends State<_RibbonIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isSelected || widget.isActive;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? AppColors.obsidianActive
                  : (_hovered ? AppColors.obsidianHover : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (widget.isSelected)
                  Positioned(
                    left: 0,
                    top: 8,
                    bottom: 8,
                    child: Container(
                      width: 2.5,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                Icon(
                  widget.icon,
                  size: 19,
                  color: active
                      ? (AppColors.isDark ? Colors.white : AppColors.primaryDark)
                      : (_hovered ? AppColors.obsidianText : AppColors.obsidianTextMuted),
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
// 2. OBSIDIAN SIDEBAR PANEL CHÍNH (Thay đổi linh hoạt theo Tab)
// ============================================================================
class _ObsidianSidebarPanel extends StatelessWidget {
  final int mainIndex;
  final int activeTabIndex;
  final String searchQuery;
  final Set<int> collapsedSemesters;
  final ValueChanged<int> onTabChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int> onToggleSemester;
  final ValueChanged<List<int>> onCollapseAllSemesters;
  final ValueChanged<Subject> onSelectSubject;
  final VoidCallback onOpenVault;
  final VoidCallback onCloseSidebar;
  final VoidCallback onNewSubject;
  final ValueChanged<int> onNavigateToTab;

  const _ObsidianSidebarPanel({
    required this.mainIndex,
    required this.activeTabIndex,
    required this.searchQuery,
    required this.collapsedSemesters,
    required this.onTabChanged,
    required this.onSearchChanged,
    required this.onToggleSemester,
    required this.onCollapseAllSemesters,
    required this.onSelectSubject,
    required this.onOpenVault,
    required this.onCloseSidebar,
    required this.onNewSubject,
    required this.onNavigateToTab,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Khi đang ở tab Trợ lý AI (index 3) -> Hiển thị Sidebar Lịch sử các đoạn chat AI
    if (mainIndex == 3) {
      return _AiChatSidebarContent(
        onCloseSidebar: onCloseSidebar,
      );
    }

    // 2. Khi đang ở tab Obsidian Vault (index 2) -> Hiển thị Sidebar Vault Explorer
    if (mainIndex == 2) {
      return _VaultSidebarContent(
        onCloseSidebar: onCloseSidebar,
      );
    }

    // 3. Khi đang ở tab Cài đặt (index 4) -> Hiển thị Sidebar mục cài đặt
    if (mainIndex == 4) {
      return _SettingsSidebarContent(
        onCloseSidebar: onCloseSidebar,
      );
    }

    // 4. Mặc định (Đồ thị & Môn học - index 0, 1) -> Hiển thị Cây thư mục môn học theo kỳ
    return _FilesSidebarContent(
      activeTabIndex: activeTabIndex,
      searchQuery: searchQuery,
      collapsedSemesters: collapsedSemesters,
      onTabChanged: onTabChanged,
      onSearchChanged: onSearchChanged,
      onToggleSemester: onToggleSemester,
      onCollapseAllSemesters: onCollapseAllSemesters,
      onSelectSubject: onSelectSubject,
      onOpenVault: onOpenVault,
      onCloseSidebar: onCloseSidebar,
      onNewSubject: onNewSubject,
    );
  }
}

// ============================================================================
// 2A. SIDEBAR CHO TRỢ LÝ AI: NƠI LƯU & QUẢN LÝ CÁC ĐOẠN CHAT
// ============================================================================
class _AiChatSidebarContent extends StatefulWidget {
  final VoidCallback onCloseSidebar;

  const _AiChatSidebarContent({
    required this.onCloseSidebar,
  });

  @override
  State<_AiChatSidebarContent> createState() => _AiChatSidebarContentState();
}

class _AiChatSidebarContentState extends State<_AiChatSidebarContent> {
  String _chatSearch = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ChatSessionService.instance, AppState.instance]),
      builder: (context, _) {
        final chatService = ChatSessionService.instance;
        final sessions = chatService.sessions;
        final currentId = chatService.currentSessionId;

        final filtered = _chatSearch.trim().isEmpty
            ? sessions
            : sessions.where((s) {
                return s.title
                    .toLowerCase()
                    .contains(_chatSearch.trim().toLowerCase());
              }).toList();

        return Column(
          children: [
            // Header: Tiêu đề + Nút thêm đoạn chat + Nút thu gọn
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.obsidianBorder, width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.forum_outlined, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'ĐOẠN CHAT AI',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidianText,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_comment_outlined, size: 16),
                    color: AppColors.obsidianTextMuted,
                    tooltip: 'Đoạn chat mới',
                    splashRadius: 14,
                    onPressed: () => chatService.newSession(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 18),
                    color: AppColors.obsidianTextMuted,
                    tooltip: 'Thu gọn thanh bên',
                    splashRadius: 14,
                    onPressed: widget.onCloseSidebar,
                  ),
                ],
              ),
            ),

            // Nút to nổi bật "+ Cuộc trò chuyện mới"
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: InkWell(
                onTap: () => chatService.newSession(),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add, size: 16, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Cuộc trò chuyện mới',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Ô lọc nhanh đoạn chat
            if (sessions.length > 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                child: Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.obsidianRibbon,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.obsidianBorder),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 13, color: AppColors.obsidianTextMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          onChanged: (q) => setState(() => _chatSearch = q),
                          style: TextStyle(fontSize: 11.5, color: AppColors.obsidianText),
                          decoration: InputDecoration(
                            hintText: 'Tìm đoạn chat...',
                            hintStyle: TextStyle(fontSize: 11.5, color: AppColors.obsidianTextMuted),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Danh sách các đoạn chat đã lưu
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 28,
                            color: AppColors.obsidianTextMuted.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Chưa có đoạn chat nào',
                            style: TextStyle(fontSize: 11.5, color: AppColors.obsidianTextMuted),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final s = filtered[i];
                        final isSelected = s.id == currentId;
                        return _ChatSessionTile(
                          session: s,
                          isSelected: isSelected,
                          onTap: () => chatService.selectSession(s.id),
                          onDelete: () => chatService.deleteSession(s.id),
                          onRename: (newTitle) =>
                              chatService.renameSession(s.id, newTitle),
                        );
                      },
                    ),
            ),

            // Footer hiển thị số lượng đoạn chat
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.obsidianRibbon,
                border: Border(
                  top: BorderSide(color: AppColors.obsidianBorder, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.history, size: 14, color: AppColors.obsidianTextMuted),
                  const SizedBox(width: 8),
                  Text(
                    '${sessions.length} cuộc trò chuyện đã lưu',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.obsidianTextMuted,
                    ),
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

class _ChatSessionTile extends StatefulWidget {
  final ChatSession session;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<String> onRename;

  const _ChatSessionTile({
    required this.session,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
  });

  @override
  State<_ChatSessionTile> createState() => _ChatSessionTileState();
}

class _ChatSessionTileState extends State<_ChatSessionTile> {
  bool _hovered = false;

  void _showRenameDialog() {
    final controller = TextEditingController(text: widget.session.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên đoạn chat', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Nhập tiêu đề mới...',
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onRename(controller.text);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final active = widget.isSelected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: active
              ? AppColors.obsidianActive
              : (_hovered ? AppColors.obsidianHover : Colors.transparent),
          borderRadius: BorderRadius.circular(6),
          border: active
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.4))
              : null,
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 14,
                  color: active ? AppColors.primary : AppColors.obsidianTextMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                          color: active
                              ? (AppColors.isDark ? Colors.white : AppColors.primaryDark)
                              : AppColors.obsidianText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${s.messages.length} tin nhắn • ${_formatTime(s.createdAt)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.obsidianTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_hovered || active) ...[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 13),
                    color: AppColors.obsidianTextMuted,
                    tooltip: 'Đổi tên',
                    splashRadius: 12,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                    onPressed: _showRenameDialog,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 13),
                    color: AppColors.obsidianTextMuted,
                    tooltip: 'Xóa đoạn chat',
                    splashRadius: 12,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                    onPressed: widget.onDelete,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (now.day == dt.day && now.month == dt.month && now.year == dt.year) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${dt.day}/${dt.month}';
  }
}

// ============================================================================
// 2B. SIDEBAR CHO OBSIDIAN VAULT
// ============================================================================
class _VaultSidebarContent extends StatelessWidget {
  final VoidCallback onCloseSidebar;

  const _VaultSidebarContent({
    required this.onCloseSidebar,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;

        return Column(
          children: [
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.obsidianBorder, width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder_copy_outlined, size: 16, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    'OBSIDIAN VAULT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidianText,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.sync, size: 16),
                    color: AppColors.obsidianTextMuted,
                    tooltip: 'Đồng bộ lại',
                    splashRadius: 14,
                    onPressed: () => state.refresh(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 18),
                    color: AppColors.obsidianTextMuted,
                    tooltip: 'Thu gọn thanh bên',
                    splashRadius: 14,
                    onPressed: onCloseSidebar,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.obsidianRibbon,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.obsidianBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle, size: 14, color: AppColors.success),
                            const SizedBox(width: 6),
                            Text(
                              'Trạng thái Vault',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.obsidianText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          state.hasVault
                              ? 'Thư mục: ${state.vaultPath}'
                              : 'Chưa liên kết thư mục Vault nào.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.obsidianTextMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${state.stats['subjects'] ?? 0} file môn học (.md)\n'
                          '${state.stats['edges'] ?? 0} liên kết quan hệ',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.obsidianText,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Định dạng Markdown hỗ trợ:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.obsidianTextMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.obsidianRibbon,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '• Front matter YAML: code, name, semester, credits\n'
                      '• Wiki link: [[MÃ_MÔN]]\n'
                      '• Tiên quyết: ## Môn tiên quyết',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.obsidianTextMuted,
                        height: 1.5,
                      ),
                    ),
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

// ============================================================================
// 2C. SIDEBAR CHO CÀI ĐẶT
// ============================================================================
class _SettingsSidebarContent extends StatelessWidget {
  final VoidCallback onCloseSidebar;

  const _SettingsSidebarContent({
    required this.onCloseSidebar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.obsidianBorder, width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 16, color: AppColors.obsidianText),
              const SizedBox(width: 8),
              Text(
                'CÀI ĐẶT HỆ THỐNG',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidianText,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 18),
                color: AppColors.obsidianTextMuted,
                tooltip: 'Thu gọn thanh bên',
                splashRadius: 14,
                onPressed: onCloseSidebar,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            children: const [
              _SettingsMenuItem(
                icon: Icons.psychology_outlined,
                title: 'Nhà cung cấp AI',
                subtitle: 'Google Gemini & OpenAI',
              ),
              _SettingsMenuItem(
                icon: Icons.folder_outlined,
                title: 'Obsidian Vault',
                subtitle: 'Đường dẫn thư mục ghi chú',
              ),
              _SettingsMenuItem(
                icon: Icons.storage_outlined,
                title: 'SQLite Database',
                subtitle: 'se_knowledge.db cục bộ',
              ),
              _SettingsMenuItem(
                icon: Icons.keyboard_outlined,
                title: 'Phím tắt',
                subtitle: 'Ctrl+B để đóng/mở sidebar',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SettingsMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.obsidianRibbon,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.obsidianBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.obsidianText,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.obsidianTextMuted,
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

// ============================================================================
// 2D. SIDEBAR CHO TỆP & MÔN HỌC (FILE EXPLORER MẶC ĐỊNH)
// ============================================================================
class _FilesSidebarContent extends StatelessWidget {
  final int activeTabIndex;
  final String searchQuery;
  final Set<int> collapsedSemesters;
  final ValueChanged<int> onTabChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int> onToggleSemester;
  final ValueChanged<List<int>> onCollapseAllSemesters;
  final ValueChanged<Subject> onSelectSubject;
  final VoidCallback onOpenVault;
  final VoidCallback onCloseSidebar;
  final VoidCallback onNewSubject;

  const _FilesSidebarContent({
    required this.activeTabIndex,
    required this.searchQuery,
    required this.collapsedSemesters,
    required this.onTabChanged,
    required this.onSearchChanged,
    required this.onToggleSemester,
    required this.onCollapseAllSemesters,
    required this.onSelectSubject,
    required this.onOpenVault,
    required this.onCloseSidebar,
    required this.onNewSubject,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final subjects = state.graph.subjects;
        final semesters = subjects.map((s) => s.semester).toSet().toList()..sort();

        // Lọc theo từ khóa tìm kiếm
        final filtered = searchQuery.trim().isEmpty
            ? subjects
            : subjects.where((s) {
                final q = searchQuery.trim().toLowerCase();
                return s.code.toLowerCase().contains(q) ||
                    s.name.toLowerCase().contains(q);
              }).toList();

        return Column(
          children: [
            // Top Tab Icons bar (Files, Search, Bookmarks) + Collapse button
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.obsidianBorder, width: 1),
                ),
              ),
              child: Row(
                children: [
                  _PanelTabIcon(
                    icon: Icons.folder_outlined,
                    tooltip: 'Tệp môn học (Files)',
                    isSelected: activeTabIndex == 0,
                    onTap: () => onTabChanged(0),
                  ),
                  const SizedBox(width: 4),
                  _PanelTabIcon(
                    icon: Icons.search,
                    tooltip: 'Tìm kiếm nhanh (Search)',
                    isSelected: activeTabIndex == 1,
                    onTap: () => onTabChanged(1),
                  ),
                  const SizedBox(width: 4),
                  _PanelTabIcon(
                    icon: Icons.bookmark_border,
                    tooltip: 'Dấu trang (Bookmarks)',
                    isSelected: activeTabIndex == 2,
                    onTap: () => onTabChanged(2),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 18),
                    color: AppColors.obsidianTextMuted,
                    tooltip: 'Thu gọn thanh bên',
                    splashRadius: 14,
                    onPressed: onCloseSidebar,
                  ),
                ],
              ),
            ),

            // Toolbar phụ kiểu Obsidian: Tiêu đề + Các nút New Note, Sort, Collapse All
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    'TỆP & MÔN HỌC',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidianTextMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  _MiniActionIcon(
                    icon: Icons.note_add_outlined,
                    tooltip: 'Tạo môn học mới',
                    onTap: onNewSubject,
                  ),
                  _MiniActionIcon(
                    icon: Icons.sync,
                    tooltip: 'Đồng bộ lại',
                    onTap: () => state.refresh(),
                  ),
                  _MiniActionIcon(
                    icon: collapsedSemesters.length == semesters.length
                        ? Icons.unfold_more
                        : Icons.unfold_less,
                    tooltip: 'Thu gọn/Mở rộng tất cả',
                    onTap: () => onCollapseAllSemesters(semesters),
                  ),
                ],
              ),
            ),

            // Ô tìm kiếm nhanh (nếu chọn tab search hoặc muốn lọc nhanh)
            if (activeTabIndex == 1 || searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
                child: Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.obsidianRibbon,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.obsidianBorder),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 14, color: AppColors.obsidianTextMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          onChanged: onSearchChanged,
                          style: TextStyle(fontSize: 12, color: AppColors.obsidianText),
                          decoration: InputDecoration(
                            hintText: 'Tìm kiếm...',
                            hintStyle: TextStyle(fontSize: 12, color: AppColors.obsidianTextMuted),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () => onSearchChanged(''),
                          child: Icon(Icons.close, size: 14, color: AppColors.obsidianTextMuted),
                        ),
                    ],
                  ),
                ),
              ),

            // Danh sách môn học dạng cây thư mục Obsidian
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'Không có môn nào',
                        style: TextStyle(fontSize: 12, color: AppColors.obsidianTextMuted),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        for (final sem in semesters)
                          _buildSemesterGroup(
                            semester: sem,
                            subjects: filtered.where((s) => s.semester == sem).toList(),
                            isCollapsed: collapsedSemesters.contains(sem),
                            onToggle: () => onToggleSemester(sem),
                            onSelectSubject: onSelectSubject,
                            selectedId: state.selectedSubjectId,
                          ),
                      ],
                    ),
            ),

            // Vault Switcher ở chân Sidebar (y hệt Obsidian trong ảnh)
            InkWell(
              onTap: onOpenVault,
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.obsidianRibbon,
                  border: Border(
                    top: BorderSide(color: AppColors.obsidianBorder, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.swap_vert, size: 16, color: AppColors.obsidianTextMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.hasVault
                                ? state.vaultPath!.split(r'[\/]').last
                                : 'Obsidian Vault',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.obsidianText,
                            ),
                          ),
                          Text(
                            '${state.stats['subjects'] ?? 0} môn • ${state.stats['edges'] ?? 0} liên kết',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.obsidianTextMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 11,
                      color: AppColors.obsidianTextMuted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSemesterGroup({
    required int semester,
    required List<Subject> subjects,
    required bool isCollapsed,
    required VoidCallback onToggle,
    required ValueChanged<Subject> onSelectSubject,
    required int? selectedId,
  }) {
    if (subjects.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tiêu đề Folder Kỳ học
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              children: [
                Icon(
                  isCollapsed ? Icons.arrow_right : Icons.arrow_drop_down,
                  size: 16,
                  color: AppColors.obsidianTextMuted,
                ),
                const SizedBox(width: 4),
                Icon(
                  isCollapsed ? Icons.folder : Icons.folder_open,
                  size: 15,
                  color: AppColors.forSemester(semester),
                ),
                const SizedBox(width: 6),
                Text(
                  'Học kỳ $semester',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.obsidianText,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.obsidianActive,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${subjects.length}',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.obsidianTextMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Danh sách các file môn học bên trong
        if (!isCollapsed)
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Column(
              children: [
                for (final s in subjects)
                  _FileItemTile(
                    subject: s,
                    isSelected: selectedId == s.id,
                    onTap: () => onSelectSubject(s),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FileItemTile extends StatefulWidget {
  final Subject subject;
  final bool isSelected;
  final VoidCallback onTap;

  const _FileItemTile({
    required this.subject,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_FileItemTile> createState() => _FileItemTileState();
}

class _FileItemTileState extends State<_FileItemTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.subject;
    final active = widget.isSelected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: active
                ? AppColors.obsidianActive
                : (_hovered ? AppColors.obsidianHover : Colors.transparent),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 14,
                color: AppColors.obsidianTextMuted,
              ),
              const SizedBox(width: 6),
              Text(
                s.code,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active
                      ? (AppColors.isDark ? Colors.white : AppColors.primaryDark)
                      : AppColors.obsidianText,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.obsidianTextMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelTabIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  const _PanelTabIcon({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.obsidianActive : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isSelected
                ? (AppColors.isDark ? Colors.white : AppColors.primaryDark)
                : AppColors.obsidianTextMuted,
          ),
        ),
      ),
    );
  }
}

class _MiniActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MiniActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 15, color: AppColors.obsidianTextMuted),
        ),
      ),
    );
  }
}

// ============================================================================
// 3. OBSIDIAN TOP WORKSPACE TAB BAR
// ============================================================================
class _ObsidianWorkspaceTabBar extends StatelessWidget {
  final String currentTabTitle;
  final IconData currentTabIcon;
  final bool canGoBack;
  final bool canGoForward;
  final bool isSidebarOpen;
  final List<Subject> openNotes;
  final Subject? activeNote;
  final int currentIndex;
  final VoidCallback onGoBack;
  final VoidCallback onGoForward;
  final VoidCallback onToggleSidebar;
  final VoidCallback onSelectGraphTab;
  final ValueChanged<int> onSelectPageTab;
  final ValueChanged<int> onClosePageTab;
  final ValueChanged<Subject> onSelectNoteTab;
  final ValueChanged<Subject> onCloseNoteTab;
  final VoidCallback onNewTab;

  const _ObsidianWorkspaceTabBar({
    required this.currentTabTitle,
    required this.currentTabIcon,
    required this.canGoBack,
    required this.canGoForward,
    required this.isSidebarOpen,
    required this.openNotes,
    required this.activeNote,
    required this.currentIndex,
    required this.onGoBack,
    required this.onGoForward,
    required this.onToggleSidebar,
    required this.onSelectGraphTab,
    required this.onSelectPageTab,
    required this.onClosePageTab,
    required this.onSelectNoteTab,
    required this.onCloseNoteTab,
    required this.onNewTab,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppState.instance.isDark;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.shellRibbon,
        border: Border(
          bottom: BorderSide(color: AppColors.shellBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Nút History Navigation: Back & Forward
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 16),
            color: canGoBack
                ? AppColors.shellText
                : AppColors.shellTextMuted.withValues(alpha: 0.4),
            splashRadius: 14,
            tooltip: 'Quay lại',
            onPressed: canGoBack ? onGoBack : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward, size: 16),
            color: canGoForward
                ? AppColors.shellText
                : AppColors.shellTextMuted.withValues(alpha: 0.4),
            splashRadius: 14,
            tooltip: 'Tiến tới',
            onPressed: canGoForward ? onGoForward : null,
          ),
          const SizedBox(width: 6),

          // Vùng cuộn ngang chứa các Tab kiểu Obsidian
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // 1. Tab "Graph view" (luôn có)
                  _buildTab(
                    title: 'Graph view',
                    icon: Icons.hub,
                    isActive: activeNote == null && currentIndex == 0,
                    onTap: onSelectGraphTab,
                    onClose: null,
                  ),

                  // 2. Tab Trang chức năng ngoài Graph view (nếu đang chọn từ Ribbon)
                  if (currentIndex != 0 && activeNote == null)
                    _buildTab(
                      title: currentTabTitle,
                      icon: currentTabIcon,
                      isActive: true,
                      onTap: () => onSelectPageTab(currentIndex),
                      onClose: () => onClosePageTab(currentIndex),
                    ),

                  // 3. Các tab ghi chú môn học đang mở: [PRM393.md x], [CSD201.md x]
                  for (final note in openNotes)
                    _buildTab(
                      title: '${note.code}.md',
                      icon: Icons.article_outlined,
                      isActive: activeNote?.code.toUpperCase() == note.code.toUpperCase(),
                      onTap: () => onSelectNoteTab(note),
                      onClose: () => onCloseNoteTab(note),
                    ),

                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.add, size: 16),
                    color: AppColors.shellTextMuted,
                    splashRadius: 14,
                    tooltip: 'Thêm môn học mới',
                    onPressed: onNewTab,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Nút đổi theme nhanh
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 16,
            ),
            color: isDark ? const Color(0xFFFFC107) : AppColors.shellText,
            splashRadius: 14,
            tooltip: isDark
                ? 'Giao diện Tối (Bấm để chuyển Sáng)'
                : 'Giao diện Sáng (Bấm để chuyển Tối)',
            onPressed: () => AppState.instance.toggleTheme(),
          ),
          const SizedBox(width: 4),

          // Shortcut gợi ý
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.shellHover,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.shellBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.keyboard, size: 12, color: AppColors.shellTextMuted),
                const SizedBox(width: 4),
                Text(
                  'Ctrl + B để đóng/mở sidebar',
                  style: TextStyle(fontSize: 10.5, color: AppColors.shellTextMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          IconButton(
            icon: Icon(
              isSidebarOpen ? Icons.view_sidebar : Icons.view_sidebar_outlined,
              size: 16,
            ),
            color: AppColors.shellTextMuted,
            splashRadius: 14,
            tooltip: isSidebarOpen ? 'Thu gọn sidebar' : 'Mở sidebar',
            onPressed: onToggleSidebar,
          ),
        ],
      ),
    );
  }

  Widget _buildTab({
    required String title,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    VoidCallback? onClose,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        margin: const EdgeInsets.only(right: 3),
        decoration: BoxDecoration(
          color: isActive ? AppColors.shellSidebar : Colors.transparent,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          border: Border(
            top: BorderSide(
              color: isActive ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
            left: BorderSide(
              color: isActive ? AppColors.shellBorder : Colors.transparent,
            ),
            right: BorderSide(
              color: isActive ? AppColors.shellBorder : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? AppColors.primary : AppColors.shellTextMuted,
            ),
            const SizedBox(width: 7),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? AppColors.shellText : AppColors.shellTextMuted,
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close,
                    size: 12,
                    color: AppColors.shellTextMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
