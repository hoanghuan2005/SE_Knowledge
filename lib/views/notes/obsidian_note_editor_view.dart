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

  /// Chia đôi màn hình: Trái soạn thảo - Phải xem trước
  split,

  /// Chỉ xem trước Markdown đã render
  preview,
}

/// Widget soạn thảo ghi chú chuẩn Obsidian được nhúng trực tiếp trong Workspace chính.
/// Phía trên có thanh công cụ Markdown, ở giữa là trình soạn thảo/xem trước, phía dưới là Status Bar.
class ObsidianNoteEditorView extends StatefulWidget {
  final Subject subject;

  const ObsidianNoteEditorView({
    super.key,
    required this.subject,
  });

  @override
  State<ObsidianNoteEditorView> createState() => _ObsidianNoteEditorViewState();
}

class _ObsidianNoteEditorViewState extends State<ObsidianNoteEditorView> {
  late final TextEditingController _controller;
  late final UndoHistoryController _undoController;
  NoteViewMode _viewMode = NoteViewMode.split;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDirty = false;
  String _originalContent = '';
  String _filePath = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _undoController = UndoHistoryController();
    _loadFile();
  }

  @override
  void didUpdateWidget(covariant ObsidianNoteEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.subject.id != oldWidget.subject.id ||
        widget.subject.code != oldWidget.subject.code) {
      _loadFile();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _undoController.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    setState(() => _isLoading = true);

    final s = widget.subject;
    final state = AppState.instance;
    final vaultPath = state.vaultPath;
    String content = '';
    String path = s.notePath ?? '';

    if (vaultPath != null && vaultPath.isNotEmpty) {
      path = '$vaultPath\\${s.code}.md';
      final file = File(path);
      if (await file.exists()) {
        try {
          content = await file.readAsString();
        } catch (_) {
          content = '';
        }
      } else {
        content = _buildInitialTemplate(s);
      }
    } else {
      content = _buildInitialTemplate(s);
    }

    _filePath = path;
    _originalContent = content;
    _controller.text = content;
    _isDirty = false;

    _controller.removeListener(_checkDirty);
    _controller.addListener(_checkDirty);

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _checkDirty() {
    final changed = _controller.text != _originalContent;
    if (changed != _isDirty && mounted) {
      setState(() => _isDirty = changed);
    }
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

  Future<void> _saveNote() async {
    final state = AppState.instance;
    if (!state.hasVault) {
      Ui.error(context, 'Chưa chọn thư mục Vault. Hãy chọn thư mục ở tab Obsidian Vault để lưu file.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final file = File(_filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(_controller.text, flush: true);

      if (widget.subject.notePath != _filePath && widget.subject.id != null) {
        final updated = widget.subject.copyWith(notePath: _filePath);
        await state.updateSubject(updated);
      }

      _originalContent = _controller.text;
      _isDirty = false;

      if (mounted) {
        Ui.success(context, 'Đã lưu ghi chú ${widget.subject.code}.md');
      }
    } catch (e) {
      if (mounted) Ui.error(context, 'Lỗi khi lưu file: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _insertMarkdownSyntax(String prefix, [String suffix = '']) {
    final text = _controller.text;
    final selection = _controller.selection;

    if (!selection.isValid) {
      _controller.text = '$text$prefix$suffix';
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      return;
    }

    final selectedText = selection.textInside(text);
    final replacement = '$prefix$selectedText$suffix';
    final newText = text.replaceRange(selection.start, selection.end, replacement);

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: selection.start + prefix.length,
        extentOffset: selection.start + prefix.length + selectedText.length,
      ),
    );
  }

  void _handleLinkTap(String link) {
    var code = link.replaceAll('[[', '').replaceAll(']]', '').trim().toUpperCase();
    if (code.contains('|')) code = code.split('|').first.trim().toUpperCase();
    if (code.contains('#')) code = code.split('#').first.trim().toUpperCase();

    final allSubjects = AppState.instance.graph.subjects;
    final target = allSubjects.where((s) => s.code.toUpperCase() == code).firstOrNull;

    if (target != null) {
      // Mở ngay môn đó thành tab trên thanh trên cùng
      AppState.instance.openNoteTab(target);
    } else {
      Ui.toast(context, 'Không tìm thấy môn học có mã: $code');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS):
            const _SaveNoteIntent(),
      },
      child: Actions(
        actions: {
          _SaveNoteIntent: CallbackAction<_SaveNoteIntent>(
            onInvoke: (_) => _saveNote(),
          ),
        },
        child: Container(
          color: AppColors.shellWorkspace,
          child: Column(
            children: [
              // 1. THANH CÔNG CỤ SOẠN THẢO & ĐIỀU KHIỂN CHẾ ĐỘ
              _buildTopBar(isDark),

              // 2. VÙNG SOẠN THẢO / XEM TRƯỚC CHÍNH
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildWorkspaceContent(isDark),
              ),

              // 3. THANH TRẠNG THÁI STATUS BAR (OBSIDIAN STYLE)
              _buildStatusBar(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isDark) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.8)),
      ),
      child: Row(
        children: [
          // Tiêu đề tệp
          Icon(Icons.article_outlined, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            '${widget.subject.code}.md',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (_isDirty) ...[
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.warning,
                shape: BoxShape.circle,
              ),
            ),
          ],

          const SizedBox(width: 16),
          const VerticalDivider(width: 1, indent: 8, endIndent: 8),
          const SizedBox(width: 12),

          // Các nút Markdown định dạng nhanh
          if (_viewMode != NoteViewMode.preview) ...[
            _toolbarBtn('# H1', () => _insertMarkdownSyntax('# ')),
            _toolbarBtn('## H2', () => _insertMarkdownSyntax('## ')),
            _toolbarBtn('B', () => _insertMarkdownSyntax('**', '**'), isBold: true),
            _toolbarBtn('I', () => _insertMarkdownSyntax('*', '*'), isItalic: true),
            _toolbarBtn('`code`', () => _insertMarkdownSyntax('`', '`')),
            _toolbarBtn('[[Liên kết]]', () => _insertMarkdownSyntax('[[', ']]'), isLink: true),
            _toolbarBtn('- [ ] Việc', () => _insertMarkdownSyntax('- [ ] ')),
          ],

          const Spacer(),

          // Bộ chọn chế độ xem: Edit / Split / Preview
          _buildViewModeToggle(isDark),
          const SizedBox(width: 10),

          // Nút lưu (Ctrl + S)
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
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: _isSaving ? null : _saveNote,
            ),
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
            color: isLink ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspaceContent(bool isDark) {
    if (_viewMode == NoteViewMode.edit) {
      return _buildTextEditorPane(isDark);
    } else if (_viewMode == NoteViewMode.preview) {
      return _buildPreviewPane(isDark);
    } else {
      // Split view: 50% Edit, 50% Preview
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildTextEditorPane(isDark)),
          VerticalDivider(width: 1, color: AppColors.divider),
          Expanded(child: _buildPreviewPane(isDark)),
        ],
      );
    }
  }

  Widget _buildTextEditorPane(bool isDark) {
    return Container(
      color: AppColors.shellWorkspace,
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
      child: TextField(
        controller: _controller,
        undoController: _undoController,
        maxLines: null,
        expands: true,
        keyboardType: TextInputType.multiline,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.65,
          fontFamily: 'monospace',
          color: AppColors.textPrimary,
        ),
        cursorColor: AppColors.primary,
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Bắt đầu gõ ghi chú Markdown hoặc [[Mã_Môn]] tại đây...',
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildPreviewPane(bool isDark) {
    final text = _controller.text;

    // Bóc tách cú pháp [[CODE]] thành link [CODE](obsidian://CODE)
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
            ? '_Chưa có nội dung ghi chú._'
            : processedMarkdown,
        selectable: true,
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
        onTapLink: (text, href, title) {
          if (href != null && href.startsWith('obsidian://')) {
            final code = href.replaceFirst('obsidian://', '');
            _handleLinkTap(code);
          }
        },
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(
            fontSize: 13.5,
            height: 1.65,
            color: AppColors.textPrimary,
          ),
          h1: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.4,
          ),
          h2: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            height: 1.4,
          ),
          h3: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          blockquote: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontStyle: FontStyle.italic,
          ),
          blockquoteDecoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E26) : const Color(0xFFF1F1F5),
            borderRadius: BorderRadius.circular(6),
            border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
          ),
          code: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
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

  Widget _buildStatusBar(bool isDark) {
    final state = AppState.instance;
    final text = _controller.text;
    final words = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final chars = text.length;
    final backlinks = RegExp(r'\[\[([^\[\]]+?)\]\]').allMatches(text).length;

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.shellRibbon,
        border: Border(top: BorderSide(color: AppColors.shellBorder, width: 1)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            state.hasVault ? 'Obsidian Vault: ${state.vaultPath}' : 'Chưa liên kết Vault',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            '$backlinks liên kết [[...]]',
            style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
          ),
          _statusDot(),
          Text(
            '$words từ',
            style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
          ),
          _statusDot(),
          Text(
            '$chars ký tự',
            style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
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

class _SaveNoteIntent extends Intent {
  const _SaveNoteIntent();
}
