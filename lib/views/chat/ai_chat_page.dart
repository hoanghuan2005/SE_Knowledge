import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chat_message.dart';
import '../../models/graph_rag_context.dart';
import '../../services/ai_service.dart';
import '../../services/chat_session_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';

/// Khung chat với trợ lý học tập.
///
/// Request đi trực tiếp từ app tới Gemini/OpenAI bằng package `http`.
/// Trước khi gửi, app nạp thêm ngữ cảnh lấy từ SQLite để AI trả lời dựa trên
/// đúng đồ thị môn học của người dùng.
class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override                                           
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;
  bool _useContext = true;

  static const List<String> _suggestions = [
    'Tôi nên học môn nào trước để vào được PRJ301?',
    'Giải thích vì sao CSD201 cần MAD101.',
    'Lập lộ trình 2 kỳ tới dựa trên các môn tôi đã có.',
    'Những môn nào đang là nút thắt trong đồ thị của tôi?',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;

    final session = ChatSessionService.instance.currentSession;
    final history = List<ChatMessage>.from(session.messages);

    setState(() {
      ChatSessionService.instance.addMessage(ChatMessage.user(text));
      _input.clear();
      _sending = true;
    });
    _scrollToBottom();

    try {
      final answer = await AiService.instance.ask(
        question: text,
        history: history,
        includeKnowledgeContext: _useContext,
      );
      if (!mounted) return;
      ChatSessionService.instance.addMessage(
        ChatMessage.assistant(answer.text, ragSummary: answer.ragSummary),
      );
    } on AiException catch (e) {
      if (!mounted) return;
      ChatSessionService.instance.addMessage(
        ChatMessage.assistant(e.message, isError: true),
      );
    } catch (e) {
      if (!mounted) return;
      ChatSessionService.instance.addMessage(
        ChatMessage.assistant(e.toString(), isError: true),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ChatSessionService.instance, AppState.instance]),
      builder: (context, _) {
        final session = ChatSessionService.instance.currentSession;
        final messages = session.messages;

        return Column(
          children: [
            PageHeader(
              title: session.title.isEmpty ? 'Trợ lý AI' : session.title,
              subtitle: _useContext
                  ? 'Đang gửi kèm ngữ cảnh đồ thị môn học từ SQLite'
                  : 'Đang hỏi thuần, không gửi dữ liệu môn học',
              actions: [
                Row(
                  children: [
                    Text(
                      'Gửi kèm ngữ cảnh',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Switch(
                      value: _useContext,
                      onChanged: (v) => setState(() => _useContext = v),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Tạo đoạn chat mới',
                  icon: const Icon(Icons.add_comment_outlined),
                  onPressed: () {
                    ChatSessionService.instance.newSession();
                    setState(() {});
                  },
                ),
                IconButton(
                  tooltip: 'Xoá đoạn chat này',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: messages.isEmpty
                      ? null
                      : () => setState(() {
                            ChatSessionService.instance.clearCurrentSession();
                          }),
                ),
              ],
            ),
            Expanded(
              child: messages.isEmpty
                  ? _welcome()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 20,
                      ),
                      itemCount: messages.length + (_sending ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= messages.length) return const _TypingBubble();
                        return _Bubble(message: messages[i]);
                      },
                    ),
            ),
            _composer(),
          ],
        );
      },
    );
  }

  Widget _welcome() {
    return FutureBuilder<bool>(
      future: AiService.instance.isConfigured,
      builder: (context, snapshot) {
        final configured = snapshot.data ?? false;
        final stats = AppState.instance.stats;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 48,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Hỏi về lộ trình học của bạn',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  configured
                      ? 'Trợ lý đọc được ${stats['subjects'] ?? 0} môn và '
                            '${stats['edges'] ?? 0} liên kết trong CSDL cục bộ '
                            'của bạn.'
                      : 'Chưa có API key. Vào tab Cài đặt để nhập key của '
                            'Gemini hoặc OpenAI trước khi chat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _suggestions)
                      ActionChip(
                        elevation: 0,
                        pressElevation: 0,
                        backgroundColor: AppColors.surface,
                        side: BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        label: Text(
                          s,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        onPressed: configured ? () => _send(s) : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): _send,
              },
              child: TextField(
                controller: _input,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Nhập câu hỏi… (Enter để gửi, Shift+Enter xuống dòng)',
                  hintStyle: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textHint,
                  ),
                  fillColor: AppColors.isDark ? const Color(0xFF16161A) : Colors.white,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, size: 18),
              label: const Text('Gửi'),
              onPressed: _sending ? null : () => _send(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;

  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isDark = AppColors.isDark;
    final bg = message.isError
        ? (isDark ? const Color(0xFF3B1E28) : const Color(0xFFFDECEF))
        : isUser
        ? AppColors.primary
        : AppColors.surface;
    final fg = message.isError
        ? (isDark ? const Color(0xFFFF7A8A) : AppColors.error)
        : isUser
        ? Colors.white
        : AppColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: isDark
                  ? const Color(0xFF2C2442)
                  : AppColors.primaryLight,
              child: Icon(
                Icons.auto_awesome,
                size: 14,
                color: isDark ? AppColors.primaryLight : AppColors.primaryDark,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 620),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: isUser
                    ? null
                    : Border.all(
                        color: message.isError
                            ? AppColors.error.withValues(alpha: 0.3)
                            : AppColors.border,
                      ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.ragSummary != null) ...[
                    _RagContextPanel(summary: message.ragSummary!),
                    const SizedBox(height: 10),
                  ],
                  SelectableText(
                    message.content,
                    style: TextStyle(fontSize: 13.5, height: 1.6, color: fg),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: isDark
                ? const Color(0xFF2C2442)
                : AppColors.primaryLight,
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isDark ? AppColors.primaryLight : AppColors.primaryDark,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Đang suy nghĩ…',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Hiển thị lại subgraph mà Graph RAG đã trích từ SQLite để gửi kèm câu hỏi:
/// những môn nào được xem là liên quan, và vài con số để người dùng tin
/// tưởng rằng AI không bị "đọc" toàn bộ CSDL một cách lãng phí.
class _RagContextPanel extends StatefulWidget {
  final GraphRagSummary summary;

  const _RagContextPanel({required this.summary});

  @override
  State<_RagContextPanel> createState() => _RagContextPanelState();
}

class _RagContextPanelState extends State<_RagContextPanel> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final summary = widget.summary;
    final tint = isDark ? const Color(0xFF20263A) : const Color(0xFFEFF3FF);
    final border = isDark ? const Color(0xFF33406B) : const Color(0xFFD4E0FB);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Icon(Icons.hub_outlined, size: 15, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Graph RAG — ngữ cảnh đã trích từ đồ thị',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                Text(
                  _expanded ? 'thu gọn' : 'mở rộng',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            if (summary.matchedCodes.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final code in summary.matchedCodes)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2442) : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: border),
                      ),
                      child: Text(
                        code,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                ],
              )
            else
              Text(
                'Không khớp môn cụ thể nào trong câu hỏi — dùng toàn bộ đồ thị.',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textSecondary,
                ),
              ),
            const SizedBox(height: 6),
            Text(
              '${summary.nodeCount} node · ${summary.edgeCount} cạnh · '
              '~${summary.approxTokens} token · truy vấn SQLite '
              '${summary.elapsedMs}ms',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
