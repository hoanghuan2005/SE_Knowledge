import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/subject.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';

/// Chế độ hiển thị của trình soạn thảo.
enum NoteViewMode {
  /// Chỉ soạn thảo Markdown thô
  edit,

  /// Chỉ xem trước Markdown đã render
  preview,

  /// Chia đôi màn hình: Trái soạn thảo - Phải xem trước
  split,
}

/// Một tab ghi chú đang mở trong trình soạn thảo.
class _OpenNoteTab {
  final Subject subject;
  final TextEditingController controller;
  final UndoHistoryController undoController;
  final String filePath;
  bool isDirty;
  String originalContent;

  _OpenNoteTab({
    required this.subject,
    required this.controller,
    required this.undoController,
    required this.filePath,
    required this.originalContent,
    this.isDirty = false,
  });
}

/// Màn hình soạn thảo ghi chú toàn trang chuẩn phong cách Obsidian.
class ObsidianNoteEditorPage extends StatefulWidget {
  final Subject initialSubject;

  const ObsidianNoteEditorPage({
    super.key,
    required this.initialSubject,
  });

  /// Tiện ích mở trình soạn thảo từ bất kỳ đâu.
  static Future<void> open(BuildContext context, Subject subject) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ObsidianNoteEditorPage(initialSubject: subject),
      ),
    );
  }

  @override
  State<ObsidianNoteEditorPage> createState() => _ObsidianNoteEditorPageState();
}

class _ObsidianNoteEditorPageState extends State<ObsidianNoteEditorPage> {
  final List<_OpenNoteTab> _tabs = [];
  int _activeTabIndex = 0;
  NoteViewMode _viewMode = NoteViewMode.split;
  bool _isLoading = true;
  bool _isSaving = false;

  _OpenNoteTab? get _currentTab =>
      _tabs.isNotEmpty && _activeTabIndex < _tabs.length
          ? _tabs[_activeTabIndex]
          : null;

  @override
  void initState() {
    super.initState();
    _openSubjectTab(widget.initialSubject);
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.controller.dispose();
      tab.undoController.dispose();
    }
    super.dispose();
  }

  Future<void> _openSubjectTab(Subject subject) async {
    // Kiểm tra xem môn học này đã mở ở tab nào chưa
    final existingIndex =
        _tabs.indexWhere((t) => t.subject.id == subject.id || t.subject.code == subject.code);
    if (existingIndex >= 0) {
      setState(() => _activeTabIndex = existingIndex);
      return;
    }

    setState(() => _isLoading = true);

    final state = AppState.instance;
    final vaultPath = state.vaultPath;
    String content = '';
    String filePath = subject.notePath ?? '';

    if (vaultPath != null && vaultPath.isNotEmpty) {
      filePath = '$vaultPath\\${subject.code}.md';
      final file = File(filePath);
      if (await file.exists()) {
        try {
          content = await file.readAsString();
        } catch (_) {
          content = '';
        }
      } else {
        // Tạo mẫu template ghi chú Obsidian ban đầu
        content = _buildInitialTemplate(subject);
      }
    } else {
      content = _buildInitialTemplate(subject);
    }

    final controller = TextEditingController(text: content);
    final undoController = UndoHistoryController();

    final newTab = _OpenNoteTab(
      subject: subject,
      controller: controller,
      undoController: undoController,
      filePath: filePath,
      originalContent: content,
      isDirty: false,
    );

    controller.addListener(() {
      if (newTab.controller.text != newTab.originalContent && !newTab.isDirty) {
        setState(() => newTab.isDirty = true);
      } else if (newTab.controller.text == newTab.originalContent && newTab.isDirty) {
        setState(() => newTab.isDirty = false);
      }
    });

    setState(() {
      _tabs.add(newTab);
      _activeTabIndex = _tabs.length - 1;
      _isLoading = false;
    });
  }

  String _buildInitialTemplate(Subject subject) {
    final state = AppState.instance;
    final prereqs = state.prerequisitesOf(subject.id ?? 0);
    final unlocks = state.unlockedBy(subject.id ?? 0);

    final sb = StringBuffer();
    sb.writeln('---');
    sb.writeln('code: ${subject.code}');
    sb.writeln('name: "${subject.name}"');
    sb.writeln('semester: ${subject.semester}');
    sb.writeln('credits: ${subject.credits}');
    sb.writeln('tags: [SE, MonHoc, Ky${subject.semester}]');
    sb.writeln('---');
    sb.writeln();
    sb.writeln('# ${subject.code} — ${subject.name}');
    sb.writeln();
    if (subject.description.isNotEmpty) {
      sb.writeln('> ${subject.description}');
      sb.writeln();
    }
    sb.writeln('## 📌 Thông tin môn học');
    sb.writeln('- **Học kỳ:** ${subject.semester}');
    sb.writeln('- **Số tín chỉ:** ${subject.credits}');
    sb.writeln();

    sb.writeln('## 🔗 Môn tiên quyết');
    if (prereqs.isEmpty) {
      sb.writeln('_Không có (Môn nền tảng)_');
    } else {
      for (final p in prereqs) {
        sb.writeln('- [[${p.code}]] — ${p.name}');
      }
    }
    sb.writeln();

    sb.writeln('## 🚀 Mở ra các môn');
    if (unlocks.isEmpty) {
      sb.writeln('_Chưa có môn nào phụ thuộc_');
    } else {
      for (final u in unlocks) {
        sb.writeln('- [[${u.code}]] — ${u.name}');
      }
    }
    sb.writeln();

    sb.writeln('## 📝 Ghi chú bài giảng & Ôn thi');
    sb.writeln('- [ ] Đọc tài liệu giáo trình');
    sb.writeln('- [ ] Làm bài Lab / Assignment');
    sb.writeln('- [ ] Ôn tập chuẩn bị cho kỳ thi PE');
    sb.writeln();

    return sb.toString();
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) {
      Navigator.of(context).pop();
      return;
    }

    final tabToClose = _tabs[index];
    tabToClose.controller.dispose();
    tabToClose.undoController.dispose();

    setState(() {
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
    });
  }

  Future<void> _saveCurrentNote() async {
    final tab = _currentTab;
    if (tab == null) return;

    final state = AppState.instance;
    if (!state.hasVault) {
      Ui.error(context, 'Chưa chọn thư mục Vault. Hãy chọn thư mục ở tab Obsidian Vault để lưu file.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final filePath = tab.filePath;
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(tab.controller.text, flush: true);

      // Cập nhật đường dẫn notePath trong database nếu chưa có
      if (tab.subject.notePath != filePath && tab.subject.id != null) {
        final updated = tab.subject.copyWith(notePath: filePath);
        await state.updateSubject(updated);
      }

      tab.originalContent = tab.controller.text;
      tab.isDirty = false;

      if (mounted) {
        Ui.success(context, 'Đã lưu ghi chú ${tab.subject.code}.md');
      }
    } catch (e) {
      if (mounted) Ui.error(context, 'Lỗi khi lưu file: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _insertMarkdownSyntax(String prefix, [String suffix = '']) {
    final tab = _currentTab;
    if (tab == null) return;

    final controller = tab.controller;
    final text = controller.text;
    final selection = controller.selection;

    if (!selection.isValid) {
      controller.text = '$text$prefix$suffix';
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
      return;
    }

    final selectedText = selection.textInside(text);
    final replacement = '$prefix$selectedText$suffix';
    final newText = text.replaceRange(selection.start, selection.end, replacement);

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: selection.start + prefix.length,
        extentOffset: selection.start + prefix.length + selectedText.length,
      ),
    );
  }

  /// Xử lý click vào liên kết trong Markdown (ví dụ: [[PRM393]])
  void _handleLinkTap(String link) {
    var code = link.replaceAll('[[', '').replaceAll(']]', '').trim().toUpperCase();
    if (code.contains('|')) code = code.split('|').first.trim().toUpperCase();
    if (code.contains('#')) code = code.split('#').first.trim().toUpperCase();

    final allSubjects = AppState.instance.graph.subjects;
    final target = allSubjects.where((s) => s.code.toUpperCase() == code).firstOrNull;

    if (target != null) {
      _openSubjectTab(target);
    } else {
      Ui.toast(context, 'Không tìm thấy môn học có mã: $code');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final tab = _currentTab;

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS):
            const _SaveIntent(),
      },
      child: Actions(
        actions: {
          _SaveIntent: CallbackAction<_SaveIntent>(
            onInvoke: (_) => _saveCurrentNote(),
          ),
        },
        child: Scaffold(
          backgroundColor: AppColors.shellWorkspace,
          body: Column(
            children: [
              // 1. THANH TAB BAR TRÊN CÙNG KIỂU OBSIDIAN WORKSPACE
              _buildObsidianTabBar(isDark),

              // 2. THANH CÔNG CỤ ĐỊNH DẠNG MARKDOWN NHANH
              _buildMarkdownToolbar(isDark),

              // 3. VÙNG SOẠN THẢO / XEM TRƯỚC CHÍNH
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : tab == null
                        ? const Center(child: Text('Không có ghi chú nào'))
                        : _buildEditorWorkspace(tab, isDark),
              ),

              // 4. THANH TRẠNG THÁI (STATUS BAR) PHONG CÁCH OBSIDIAN
              _buildObsidianStatusBar(tab, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildObsidianTabBar(bool isDark) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.shellRibbon,
        border: Border(bottom: BorderSide(color: AppColors.shellBorder, width: 1)),
      ),
      child: Row(
        children: [
          // Nút quay lại đồ thị
          IconButton(
            tooltip: 'Quay lại bản đồ tri thức',
            icon: const Icon(Icons.arrow_back, size: 18),
            splashRadius: 18,
            color: AppColors.textSecondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),

          // Các tab đang mở (như ảnh chụp Obsidian của người dùng)
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              itemBuilder: (context, i) {
                final t = _tabs[i];
                final isSelected = i == _activeTabIndex;

                return GestureDetector(
                  onTap: () => setState(() => _activeTabIndex = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    margin: const EdgeInsets.only(right: 2, top: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.shellWorkspace : Colors.transparent,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                      border: Border(
                        top: BorderSide(
                          color: isSelected ? AppColors.primary : Colors.transparent,
                          width: 2,
                        ),
                        left: BorderSide(
                          color: isSelected ? AppColors.shellBorder : Colors.transparent,
                          width: 1,
                        ),
                        right: BorderSide(
                          color: isSelected ? AppColors.shellBorder : Colors.transparent,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 15,
                          color: isSelected ? AppColors.primary : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          t.subject.code,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                          ),
                        ),
                        if (t.isDirty) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: AppColors.warning,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _closeTab(i),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.all(2.0),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Bộ chuyển chế độ: Soạn thảo | Xem trước | Chia đôi
          _buildViewModeToggle(isDark),
          const SizedBox(width: 12),

          // Nút lưu (Ctrl+S)
          SizedBox(
            height: 28,
            child: ElevatedButton.icon(
              icon: _isSaving
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined, size: 14),
              label: Text(
                _isSaving ? 'Đang lưu...' : 'Lưu (Ctrl+S)',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: _isSaving ? null : _saveCurrentNote,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _buildViewModeToggle(bool isDark) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: AppColors.shellWorkspace,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.shellBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewModeButton(
            mode: NoteViewMode.edit,
            icon: Icons.edit_note,
            tooltip: 'Chỉ soạn thảo',
          ),
          _viewModeButton(
            mode: NoteViewMode.split,
            icon: Icons.vertical_split_outlined,
            tooltip: 'Chia đôi: Soạn thảo & Xem trước',
          ),
          _viewModeButton(
            mode: NoteViewMode.preview,
            icon: Icons.chrome_reader_mode_outlined,
            tooltip: 'Chỉ xem trước (Đọc)',
          ),
        ],
      ),
    );
  }

  Widget _viewModeButton({
    required NoteViewMode mode,
    required IconData icon,
    required String tooltip,
  }) {
    final isSelected = _viewMode == mode;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => setState(() => _viewMode = mode),
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.2)
              : Colors.transparent,
          child: Icon(
            icon,
            size: 16,
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMarkdownToolbar(bool isDark) {
    if (_viewMode == NoteViewMode.preview) return const SizedBox.shrink();

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.shellWorkspace,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.8)),
      ),
      child: Row(
        children: [
          _toolbarBtn('# H1', () => _insertMarkdownSyntax('# ')),
          _toolbarBtn('## H2', () => _insertMarkdownSyntax('## ')),
          _toolbarBtn('### H3', () => _insertMarkdownSyntax('### ')),
          const VerticalDivider(width: 16, indent: 8, endIndent: 8),
          _toolbarBtn('B', () => _insertMarkdownSyntax('**', '**'), isBold: true),
          _toolbarBtn('I', () => _insertMarkdownSyntax('*', '*'), isItalic: true),
          _toolbarBtn('`code`', () => _insertMarkdownSyntax('`', '`')),
          const VerticalDivider(width: 16, indent: 8, endIndent: 8),
          _toolbarBtn('[[Liên kết]]', () => _insertMarkdownSyntax('[[', ']]'), isLink: true),
          _toolbarBtn('- [ ] Việc', () => _insertMarkdownSyntax('- [ ] ')),
          _toolbarBtn('> Trích dẫn', () => _insertMarkdownSyntax('> ')),
          _toolbarBtn('``` Khối code', () => _insertMarkdownSyntax('```dart\n', '\n```')),
          const Spacer(),
          Text(
            'Markdown & Wikilinks',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbarBtn(
    String label,
    VoidCallback onTap, {
    bool isBold = false,
    bool isItalic = false,
    bool isLink = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
            color: isLink ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildEditorWorkspace(_OpenNoteTab tab, bool isDark) {
    if (_viewMode == NoteViewMode.edit) {
      return _buildTextEditorPane(tab, isDark);
    } else if (_viewMode == NoteViewMode.preview) {
      return _buildPreviewPane(tab, isDark);
    } else {
      // Split mode (Soạn thảo bên trái, Xem trước bên phải)
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildTextEditorPane(tab, isDark)),
          VerticalDivider(width: 1, color: AppColors.divider),
          Expanded(child: _buildPreviewPane(tab, isDark)),
        ],
      );
    }
  }

  Widget _buildTextEditorPane(_OpenNoteTab tab, bool isDark) {
    return Container(
      color: AppColors.shellWorkspace,
      padding: const EdgeInsets.fromLTRB(36, 20, 36, 20),
      child: TextField(
        controller: tab.controller,
        undoController: tab.undoController,
        maxLines: null,
        expands: true,
        keyboardType: TextInputType.multiline,
        style: TextStyle(
          fontSize: 14,
          height: 1.65,
          fontFamily: 'monospace',
          color: AppColors.textPrimary,
        ),
        cursorColor: AppColors.primary,
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Bắt đầu gõ nội dung ghi chú Markdown hoặc [[Mã_Môn]] tại đây...',
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildPreviewPane(_OpenNoteTab tab, bool isDark) {
    final text = tab.controller.text;

    // Chuyển đổi cú pháp Obsidian [[CODE]] thành clickable link markdown [CODE](obsidian://CODE)
    final processedMarkdown = text.replaceAllMapped(
      RegExp(r'\[\[([^\[\]]+?)\]\]'),
      (match) {
        final inner = match.group(1) ?? '';
        final parts = inner.split('|');
        final target = parts.first.trim();
        final label = parts.length > 1 ? parts[1].trim() : target;
        return '[$label](obsidian://$target)';
      },
    );

    return Container(
      color: AppColors.shellWorkspace,
      child: Markdown(
        data: processedMarkdown.isEmpty
            ? '_Chưa có nội dung ghi chú. Hãy chuyển sang chế độ Soạn thảo để viết._'
            : processedMarkdown,
        selectable: true,
        padding: const EdgeInsets.fromLTRB(36, 20, 36, 20),
        onTapLink: (text, href, title) {
          if (href != null && href.startsWith('obsidian://')) {
            final code = href.replaceFirst('obsidian://', '');
            _handleLinkTap(code);
          }
        },
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(
            fontSize: 14,
            height: 1.65,
            color: AppColors.textPrimary,
          ),
          h1: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.4,
          ),
          h2: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            height: 1.4,
          ),
          h3: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          blockquote: TextStyle(
            fontSize: 13.5,
            color: AppColors.textSecondary,
            fontStyle: FontStyle.italic,
          ),
          blockquoteDecoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E26) : const Color(0xFFF1F1F5),
            borderRadius: BorderRadius.circular(6),
          ),
          code: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.5,
            color: AppColors.primary,
            backgroundColor: isDark ? const Color(0xFF22222E) : const Color(0xFFEEEEF5),
          ),
          codeblockDecoration: BoxDecoration(
            color: isDark ? const Color(0xFF181822) : const Color(0xFFF4F4F8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          a: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
          listBullet: TextStyle(color: AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildObsidianStatusBar(_OpenNoteTab? tab, bool isDark) {
    final state = AppState.instance;
    final text = tab?.controller.text ?? '';
    final words = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final chars = text.length;
    final backlinks = RegExp(r'\[\[([^\[\]]+?)\]\]').allMatches(text).length;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.shellRibbon,
        border: Border(top: BorderSide(color: AppColors.shellBorder, width: 1)),
      ),
      child: Row(
        children: [
          // Bên trái: Tên Obsidian Vault
          Icon(Icons.folder_open, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            state.hasVault ? 'Obsidian Vault: ${state.vaultPath}' : 'Chưa liên kết Vault',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),

          // Bên phải: backlinks • words • characters (Giống 100% Obsidian)
          Text(
            '$backlinks liên kết [[...]]',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          _statusDot(),
          Text(
            '$words từ',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          _statusDot(),
          Text(
            '$chars ký tự',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _statusDot() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          color: AppColors.textSecondary.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}
