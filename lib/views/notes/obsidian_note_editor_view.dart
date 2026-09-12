import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/subject.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';

/// Chế độ hiển thị: Soạn thảo trực tiếp (Edit) hoặc Xem trước/Đọc (Preview) trên CÙNG MỘT MÀN HÌNH.
enum NoteViewMode {
  /// Soạn thảo Markdown trực tiếp trên toàn màn hình (Notion style)
  edit,

  /// Chế độ đọc tài liệu đã render (Reading mode)
  preview,
}

/// Trình soạn thảo ghi chú chuẩn Notion / Obsidian:
/// - Soạn thảo và đọc trên cùng MỘT màn hình duy nhất, chuyển đổi bằng nút chế độ.
/// - Không thanh công cụ cồng kềnh: Định dạng nhanh qua CHUỘT PHẢI (Context Menu).
/// - Tự động đồng bộ và lưu file .md vào Obsidian Vault.
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
  final FocusNode _focusNode = FocusNode();

  NoteViewMode _viewMode = NoteViewMode.edit;
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
    _focusNode.dispose();
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

    if (!selection.isValid || selection.isCollapsed) {
      final offset = selection.isValid ? selection.baseOffset : text.length;
      final newText = text.replaceRange(offset, offset, '$prefix$suffix');
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: offset + prefix.length),
      );
    } else {
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
  }

  /// Hiển thị Menu Chuột Phải (Right-Click Context Menu) chuẩn phong cách Notion / Obsidian
  Future<void> _showRightClickMenu(Offset position) async {
    final isDark = Theme.of(context).brightness == Brightness.dark || AppState.instance.isDark;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      elevation: 10,
      color: isDark ? const Color(0xFF22222C) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isDark ? const Color(0xFF363644) : const Color(0xFFD6D4E2)),
      ),
      items: [
        _menuHeader('TIÊU ĐỀ (HEADINGS)', isDark),
        _menuItem('h1', Icons.title, 'Tiêu đề 1 (# )', isDark),
        _menuItem('h2', Icons.format_size, 'Tiêu đề 2 (## )', isDark),
        _menuItem('h3', Icons.format_size, 'Tiêu đề 3 (### )', isDark),
        const PopupMenuDivider(height: 1),

        _menuHeader('ĐỊNH DẠNG VĂN BẢN', isDark),
        _menuItem('bold', Icons.format_bold, 'In đậm (**chữ**)', isDark),
        _menuItem('italic', Icons.format_italic, 'In nghiêng (*chữ*)', isDark),
        _menuItem('code', Icons.code, 'Đoạn mã (`code`)', isDark),
        const PopupMenuDivider(height: 1),

        _menuHeader('KHỐI NỘI DUNG (NOTION / OBSIDIAN)', isDark),
        _menuItem('link', Icons.link, 'Liên kết môn [[Mã môn]]', isDark, isHighlight: true),
        _menuItem('todo', Icons.check_box_outlined, 'Việc cần làm (- [ ])', isDark),
        _menuItem('bullet', Icons.format_list_bulleted, 'Dấu đầu dòng (- )', isDark),
        _menuItem('quote', Icons.format_quote, 'Trích dẫn (> )', isDark),
        _menuItem('codeblock', Icons.integration_instructions_outlined, 'Khối code (```)', isDark),
        _menuItem('divider', Icons.horizontal_rule, 'Đường phân cách (---)', isDark),
        const PopupMenuDivider(height: 1),

        _menuItem('undo', Icons.undo, 'Hoàn tác (Ctrl+Z)', isDark),
        _menuItem('select_all', Icons.select_all, 'Chọn tất cả', isDark),
      ],
    );

    if (selected == null) return;

    switch (selected) {
      case 'h1': _insertMarkdownSyntax('# '); break;
      case 'h2': _insertMarkdownSyntax('## '); break;
      case 'h3': _insertMarkdownSyntax('### '); break;
      case 'bold': _insertMarkdownSyntax('**', '**'); break;
      case 'italic': _insertMarkdownSyntax('*', '*'); break;
      case 'code': _insertMarkdownSyntax('`', '`'); break;
      case 'link': _insertMarkdownSyntax('[[', ']]'); break;
      case 'todo': _insertMarkdownSyntax('- [ ] '); break;
      case 'bullet': _insertMarkdownSyntax('- '); break;
      case 'quote': _insertMarkdownSyntax('> '); break;
      case 'codeblock': _insertMarkdownSyntax('```dart\n', '\n```'); break;
      case 'divider': _insertMarkdownSyntax('\n---\n'); break;
      case 'undo': _undoController.undo(); break;
      case 'select_all':
        _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
        break;
    }
  }

  PopupMenuItem<String> _menuHeader(String label, bool isDark) {
    return PopupMenuItem<String>(
      enabled: false,
      height: 24,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: isDark ? const Color(0xFF75758A) : const Color(0xFF888899),
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    bool isDark, {
    bool isHighlight = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 32,
      child: Row(
        children: [
          Icon(
            icon,
            size: 15,
            color: isHighlight
                ? AppColors.primary
                : (isDark ? const Color(0xFFB0B0C2) : const Color(0xFF555566)),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isHighlight ? FontWeight.w600 : FontWeight.w500,
              color: isHighlight
                  ? AppColors.primary
                  : (isDark ? Colors.white : const Color(0xFF1E1E28)),
            ),
          ),
        ],
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
      AppState.instance.openNoteTab(target);
    } else {
      Ui.toast(context, 'Không tìm thấy môn học có mã: $code');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark || AppState.instance.isDark;

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
              // 1. THANH TIÊU ĐỀ ĐIỀU KHIỂN TINH GỌN (NOTION STYLE)
              _buildTopBar(isDark),

              // 2. MÀN HÌNH SOẠN THẢO DUY NHẤT (THEO CHẾ ĐỘ CHỌN)
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildSingleWorkspaceContent(isDark),
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
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.8)),
      ),
      child: Row(
        children: [
          // Tiêu đề tệp
          Icon(Icons.description_outlined, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            '${widget.subject.code}.md',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.textPrimary,
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
          const SizedBox(width: 8),
          Text(
            '— ${widget.subject.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF9E9EB3) : const Color(0xFF6B6B80),
            ),
          ),

          const Spacer(),

          // Gợi ý chuột phải
          if (_viewMode == NoteViewMode.edit)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Row(
                children: [
                  Icon(Icons.mouse, size: 13, color: AppColors.textHint),
                  const SizedBox(width: 4),
                  Text(
                    'Chuột phải để định dạng H1, B, [[...]]',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),

          // Bộ chuyển chế độ: Cây bút (Chỉnh sửa) vs Icon Page (Đọc)
          Container(
            height: 28,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF262632) : const Color(0xFFEBE8F5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isDark ? const Color(0xFF383848) : const Color(0xFFD6D4E2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon cây bút: Chế độ chỉnh sửa
                Tooltip(
                  message: 'Chế độ chỉnh sửa',
                  child: InkWell(
                    onTap: () {
                      if (_viewMode != NoteViewMode.edit) {
                        setState(() => _viewMode = NoteViewMode.edit);
                      }
                    },
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      height: 26,
                      width: 28,
                      decoration: BoxDecoration(
                        color: _viewMode == NoteViewMode.edit
                            ? AppColors.primary.withValues(alpha: 0.25)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.edit_outlined,
                        size: 15,
                        color: _viewMode == NoteViewMode.edit
                            ? AppColors.primary
                            : (isDark
                                ? const Color(0xFF9E9EB3)
                                : const Color(0xFF6B6B80)),
                      ),
                    ),
                  ),
                ),
                // Icon page: Chế độ đọc
                Tooltip(
                  message: 'Chế độ đọc (Xem trước)',
                  child: InkWell(
                    onTap: () {
                      if (_viewMode != NoteViewMode.preview) {
                        setState(() => _viewMode = NoteViewMode.preview);
                      }
                    },
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      height: 26,
                      width: 28,
                      decoration: BoxDecoration(
                        color: _viewMode == NoteViewMode.preview
                            ? AppColors.primary.withValues(alpha: 0.25)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.description_outlined,
                        size: 15,
                        color: _viewMode == NoteViewMode.preview
                            ? AppColors.primary
                            : (isDark
                                ? const Color(0xFF9E9EB3)
                                : const Color(0xFF6B6B80)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Nút lưu (chỉ icon): Lưu (Ctrl+S)
          Tooltip(
            message: 'Lưu (Ctrl+S)',
            child: InkWell(
              onTap: _isSaving ? null : _saveNote,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 28,
                width: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: _isSaving
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.save_outlined,
                        size: 16,
                        color: Colors.white,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleWorkspaceContent(bool isDark) {
    if (_viewMode == NoteViewMode.edit) {
      // 1 màn hình duy nhất: Soạn thảo Markdown kèm menu Chuột Phải
      return GestureDetector(
        onSecondaryTapDown: (details) => _showRightClickMenu(details.globalPosition),
        child: Container(
          color: AppColors.shellWorkspace,
          padding: const EdgeInsets.fromLTRB(40, 24, 40, 24),
          child: TextField(
            controller: _controller,
            undoController: _undoController,
            focusNode: _focusNode,
            maxLines: null,
            expands: true,
            keyboardType: TextInputType.multiline,
            contextMenuBuilder: (context, editableTextState) {
              // Bắt sự kiện chuột phải ngay trên TextField để mở Menu định dạng
              final anchor = editableTextState.contextMenuAnchors.primaryAnchor;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showRightClickMenu(anchor);
              });
              return const SizedBox.shrink();
            },
            style: TextStyle(
              fontSize: 14,
              height: 1.7,
              fontFamily: 'monospace',
              color: isDark ? const Color(0xFFEEEEF2) : const Color(0xFF1E1E24),
            ),
            cursorColor: AppColors.primary,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Nhấp chuột phải để chèn H1, H2, In đậm, Liên kết môn [[...]] hoặc bắt đầu gõ...',
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      );
    } else {
      // 1 màn hình duy nhất: Xem trước / Đọc tài liệu đã render
      final text = _controller.text;
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
          data: processedMarkdown.isEmpty ? '_Chưa có nội dung ghi chú._' : processedMarkdown,
          selectable: true,
          padding: const EdgeInsets.fromLTRB(40, 24, 40, 24),
          onTapLink: (text, href, title) {
            if (href != null && href.startsWith('obsidian://')) {
              final code = href.replaceFirst('obsidian://', '');
              _handleLinkTap(code);
            }
          },
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              fontSize: 14,
              height: 1.7,
              color: isDark ? const Color(0xFFEEEEF2) : const Color(0xFF1E1E24),
            ),
            h1: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              height: 1.4,
            ),
            h2: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              height: 1.4,
            ),
            h3: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
            ),
            blockquote: TextStyle(
              fontSize: 13.5,
              color: isDark ? const Color(0xFF9E9EB3) : const Color(0xFF6B6B80),
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
