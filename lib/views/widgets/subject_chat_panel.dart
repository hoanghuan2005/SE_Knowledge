import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chat_message.dart';
import '../../models/subject.dart';
import '../../services/obsidian_service.dart';
import '../../services/subject_chat_service.dart';
import '../../utils/app_colors.dart';

/// Khung chat AI thu gọn, gắn theo TỪNG môn học — hiện trong sidebar bên phải
/// ngay khi bấm chọn một node trên đồ thị.
///
/// Khác với tab "Trợ lý AI" (dùng Graph RAG trên toàn bộ đồ thị), ngữ cảnh ở
/// đây luôn là nội dung của riêng môn đang chọn: đọc từ file `.md` trong
/// Obsidian Vault nếu đã xuất ra (`subject.notePath`), hoặc ghép từ các
/// trường trong CSDL nếu môn chưa có file `.md`. Ngay khi mở, AI được nhờ đọc
/// nội dung đó và đề xuất sẵn vài câu hỏi để bấm hỏi ngay, không cần tự gõ.
class SubjectChatPanel extends StatefulWidget {
  final Subject subject;

  const SubjectChatPanel({super.key, required this.subject});

  @override
  State<SubjectChatPanel> createState() => _SubjectChatPanelState();
}

class _SubjectChatPanelState extends State<SubjectChatPanel> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  String? _context;
  bool _loadingContext = true;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void didUpdateWidget(covariant SubjectChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject.id != widget.subject.id) {
      _loadContext();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Ưu tiên đọc nguyên văn file `.md` trong Vault; nếu chưa xuất ra file nào
  /// thì ghép tạm từ các trường đã có trong CSDL để vẫn hỏi được.
  Future<void> _loadContext() async {
    setState(() => _loadingContext = true);
    final subject = widget.subject;

    String context =
        '${subject.code} — ${subject.name}\n'
        'Học kỳ ${subject.semester} · ${subject.credits} tín chỉ\n'
        '${subject.description}';

    final path = subject.notePath;
    if (path != null && path.isNotEmpty) {
      try {
        final raw = await ObsidianService.instance.readNote(path);
        if (raw.trim().isNotEmpty) context = raw;
      } catch (_) {
        // Không đọc được file (đã bị xoá/đổi tên ngoài app...) — vẫn còn
        // context mặc định ghép từ CSDL ở trên, không chặn người dùng hỏi.
      }
    }

    if (!mounted) return;
    setState(() {
      _context = context;
      _loadingContext = false;
    });

    if (subject.id != null) {
      SubjectChatService.instance.ensureSuggestions(subject.id!, context);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send([String? preset]) async {
    final subjectId = widget.subject.id;
    final context = _context;
    if (subjectId == null || context == null) return;

    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || SubjectChatService.instance.isSending(subjectId)) {
      return;
    }

    _input.clear();
    _scrollToBottom();
    await SubjectChatService.instance.send(
      subjectId: subjectId,
      context: context,
      question: text,
    );
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final subjectId = widget.subject.id;

    return ListenableBuilder(
      listenable: SubjectChatService.instance,
      builder: (context, _) {
        final messages = subjectId == null
            ? const <ChatMessage>[]
            : SubjectChatService.instance.messagesOf(subjectId);
        final sending =
            subjectId != null && SubjectChatService.instance.isSending(subjectId);

        return Column(
          children: [
            Expanded(
              child: _loadingContext
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      children: [
                        _suggestionsBlock(subjectId),
                        for (final m in messages) _ChatBubble(message: m),
                        if (sending) const _TypingRow(),
                      ],
                    ),
            ),
            _composer(sending),
          ],
        );
      },
    );
  }

  Widget _suggestionsBlock(int? subjectId) {
    if (subjectId == null) return const SizedBox.shrink();
    final service = SubjectChatService.instance;
    final loading = service.isLoadingSuggestions(subjectId);
    final suggestions = service.suggestionsOf(subjectId);
    final hasChatted = service.messagesOf(subjectId).isNotEmpty;

    // Đã chat vài câu rồi thì thôi không chiếm chỗ bằng khối gợi ý ban đầu
    // nữa, trừ khi gợi ý vẫn đang tải hoặc chưa từng sinh được.
    if (hasChatted && !loading && suggestions.isNotEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Câu hỏi gợi ý từ nội dung môn học',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              if (!loading)
                IconButton(
                  tooltip: 'Tạo gợi ý khác',
                  icon: const Icon(Icons.refresh, size: 15),
                  visualDensity: VisualDensity.compact,
                  color: AppColors.textSecondary,
                  onPressed: () {
                    final ctx = _context;
                    if (ctx != null) {
                      service.regenerateSuggestions(subjectId, ctx);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (loading)
            Row(
              children: [
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'AI đang đọc nội dung môn học…',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            )
          else if (suggestions.isEmpty)
            Text(
              'Chưa tạo được câu hỏi gợi ý — cứ hỏi trực tiếp bên dưới.',
              style: TextStyle(fontSize: 12, color: AppColors.textHint),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in suggestions)
                  ActionChip(
                    elevation: 0,
                    pressElevation: 0,
                    backgroundColor: AppColors.background,
                    side: BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    label: Text(
                      s,
                      style: TextStyle(fontSize: 11.5, color: AppColors.textPrimary),
                    ),
                    onPressed: () => _send(s),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _composer(bool sending) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.enter): _send},
              child: TextField(
                controller: _input,
                maxLines: 3,
                minLines: 1,
                style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Hỏi về môn này…',
                  hintStyle: TextStyle(fontSize: 12, color: AppColors.textHint),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            height: 40,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              onPressed: sending ? null : () => _send(),
              child: sending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isDark = AppColors.isDark;
    final bg = message.isError
        ? (isDark ? const Color(0xFF3B1E28) : const Color(0xFFFDECEF))
        : isUser
            ? AppColors.primary
            : AppColors.background;
    final fg = message.isError
        ? (isDark ? const Color(0xFFFF7A8A) : AppColors.error)
        : isUser
            ? Colors.white
            : AppColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: isUser ? null : Border.all(color: AppColors.border),
          ),
          child: SelectableText(
            message.content,
            style: TextStyle(fontSize: 12.5, height: 1.5, color: fg),
          ),
        ),
      ),
    );
  }
}

class _TypingRow extends StatelessWidget {
  const _TypingRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                'Đang suy nghĩ…',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
