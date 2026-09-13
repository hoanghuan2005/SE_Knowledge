import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chat_message.dart';
import '../../models/graph_rag_context.dart';
import '../../models/subject.dart';
import '../../services/ai_service.dart';
import '../../services/chat_session_service.dart';
import '../../services/obsidian_service.dart';
import '../../services/settings_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_constants.dart';
import '../../utils/ui_helpers.dart';

/// Khung chat với trợ lý học tập.
///
/// Request đi trực tiếp từ app tới Gemini/OpenAI bằng package `http`.
/// Trước khi gửi, app nạp thêm ngữ cảnh lấy từ SQLite để AI trả lời dựa trên
/// đúng đồ thị môn học của người dùng.
class AiChatPage extends StatefulWidget {
  /// Nhảy sang tab đồ thị. Chỉ số tab do `app_shell` giữ nên màn hình này
  /// không tự chuyển được; shell phải truyền hàm chuyển tab vào đây thì nút
  /// "Xem trên đồ thị" mới hiện.
  final VoidCallback? onOpenGraph;

  const AiChatPage({super.key, this.onOpenGraph});

  @override                                           
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;
  bool _useContext = true;

  /// Nội dung đang chảy về của câu trả lời chưa hoàn tất. Chỉ nằm trong state
  /// của màn hình; lưu vào phiên chat sau khi stream kết thúc.
  String _streamText = '';
  GraphRagSummary? _streamRag;

  String _provider = AppConstants.providerGemini;
  bool _hasKey = false;

  /// Kết quả lần gọi gần nhất: null khi chưa gọi lần nào trong phiên làm việc.
  bool? _lastCallOk;

  static const List<String> _suggestions = [
    'Tôi nên học môn nào trước để vào được PRJ301?',
    'Giải thích vì sao CSD201 cần MAD101.',
    'Lập lộ trình 2 kỳ tới dựa trên các môn tôi đã có.',
    'Những môn nào đang là nút thắt trong đồ thị của tôi?',
  ];

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Đọc lại nhà cung cấp và tình trạng API key. Gọi lúc mở màn hình và mỗi
  /// lần gửi câu hỏi, vì người dùng có thể vừa đổi key bên tab Cài đặt.
  Future<void> _refreshStatus() async {
    final provider = await SettingsService.instance.getAiProvider();
    final configured = await AiService.instance.isConfigured;
    if (!mounted) return;
    setState(() {
      _provider = provider;
      _hasKey = configured;
    });
  }

  String get _providerName =>
      _provider == AppConstants.providerOpenAi ? 'OpenAI' : 'Gemini';

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

  /// Lúc chữ đang chảy về thì nhảy thẳng xuống đáy: chạy animation cho từng
  /// mẩu chữ sẽ giật vì animation sau cắt ngang animation trước.
  void _stickToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;

    final session = ChatSessionService.instance.currentSession;
    final history = List<ChatMessage>.from(session.messages);
    _refreshStatus();

    setState(() {
      ChatSessionService.instance.addMessage(ChatMessage.user(text));
      _input.clear();
      _sending = true;
      _streamText = '';
      _streamRag = null;
    });
    _scrollToBottom();

    try {
      final answer = await AiService.instance.ask(
        question: text,
        history: history,
        includeKnowledgeContext: _useContext,
        onContext: (summary) {
          if (!mounted) return;
          setState(() => _streamRag = summary);
        },
        onDelta: (delta) {
          if (!mounted) return;
          setState(() => _streamText += delta);
          _stickToBottom();
        },
      );
      if (!mounted) return;
      _lastCallOk = true;
      ChatSessionService.instance.addMessage(
        ChatMessage.assistant(answer.text, ragSummary: answer.ragSummary),
      );
    } on AiException catch (e) {
      if (!mounted) return;
      _lastCallOk = false;
      ChatSessionService.instance.addMessage(
        ChatMessage.assistant(e.message, isError: true),
      );
    } catch (e) {
      if (!mounted) return;
      _lastCallOk = false;
      ChatSessionService.instance.addMessage(
        ChatMessage.assistant(e.toString(), isError: true),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _streamText = '';
          _streamRag = null;
        });
      }
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
                _statusChip(),
                const SizedBox(width: 16),
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
                        if (i < messages.length) {
                          return _Bubble(
                            message: messages[i],
                            onOpenGraph: widget.onOpenGraph,
                          );
                        }
                        // Chưa trích xong ngữ cảnh và chưa có chữ nào chảy về.
                        if (_streamRag == null && _streamText.isEmpty) {
                          return const _TypingBubble();
                        }
                        return _Bubble(
                          message: ChatMessage.assistant(
                            _streamText,
                            ragSummary: _streamRag,
                          ),
                          streaming: true,
                        );
                      },
                    ),
            ),
            _composer(),
          ],
        );
      },
    );
  }

  /// Chấm màu + tên nhà cung cấp AI đang dùng. Trạng thái lấy từ việc đã có
  /// API key hay chưa, và kết quả lần gọi gần nhất.
  Widget _statusChip() {
    final (Color color, String label) = switch ((_hasKey, _lastCallOk)) {
      (false, _) => (AppColors.textHint, 'Chưa có API key'),
      (true, false) => (AppColors.error, '$_providerName mất kết nối'),
      (true, _) => (AppColors.success, '$_providerName đã kết nối'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
      ],
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

  /// Câu trả lời còn đang chảy về: hiện thêm con trỏ nhấp nháy ở cuối chữ.
  final bool streaming;

  final VoidCallback? onOpenGraph;

  const _Bubble({
    required this.message,
    this.streaming = false,
    this.onOpenGraph,
  });

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
                  // Lúc đang stream thì để chữ thường: câu còn dở có thể cắt
                  // ngang giữa "[[CSD2", bóc link lúc đó sẽ nhấp nháy lung tung.
                  if (isUser || message.isError || streaming)
                    SelectableText(
                      streaming ? '${message.content}▌' : message.content,
                      style: TextStyle(fontSize: 13.5, height: 1.6, color: fg),
                    )
                  else
                    _LinkedAnswerText(
                      text: message.content,
                      style: TextStyle(fontSize: 13.5, height: 1.6, color: fg),
                    ),
                  // Chỉ hiện khi câu trả lời đã hoàn tất, tránh chép về một
                  // đoạn đang dở.
                  if (!isUser && !message.isError && !streaming) ...[
                    const SizedBox(height: 6),
                    _AnswerActions(
                      message: message,
                      onOpenGraph: onOpenGraph,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bóc `[[MÃ MÔN]]` trong câu trả lời của AI thành liên kết bấm được, bấm
/// vào là mở thẳng note của môn đó (giống wiki link trong Obsidian).
///
/// Mã nào không có trong CSDL thì để nguyên chữ thường, không tạo link chết.
class _LinkedAnswerText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _LinkedAnswerText({required this.text, required this.style});

  @override
  State<_LinkedAnswerText> createState() => _LinkedAnswerTextState();
}

class _LinkedAnswerTextState extends State<_LinkedAnswerText> {
  /// Giữ theo mã môn và tái dùng qua các lần build. Tạo recognizer mới mỗi
  /// lần build sẽ rò rỉ, vì TextSpan không tự huỷ recognizer của nó.
  final Map<String, TapGestureRecognizer> _recognizers = {};

  @override
  void dispose() {
    for (final r in _recognizers.values) {
      r.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _recognizerFor(Subject subject) {
    return _recognizers.putIfAbsent(
      subject.code,
      () => TapGestureRecognizer()
        ..onTap = () => AppState.instance.openNoteTab(subject),
    );
  }

  @override
  Widget build(BuildContext context) {
    final byCode = AppState.instance.graph.byCode;
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in ObsidianService.wikiLinkPattern.allMatches(widget.text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, match.start)));
      }
      cursor = match.end;

      final raw = match.group(1) ?? '';
      // Chấp nhận cả "[[CSD201|Cấu trúc dữ liệu]]" lẫn "[[CSD201#Mục]]".
      final code = raw.split(RegExp(r'[|#]')).first.trim().toUpperCase();
      final subject = byCode[code];

      if (subject == null) {
        spans.add(TextSpan(text: raw));
        continue;
      }
      spans.add(
        TextSpan(
          text: subject.code,
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
          recognizer: _recognizerFor(subject),
        ),
      );
    }

    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return SelectableText.rich(
      TextSpan(style: widget.style, children: spans),
    );
  }
}

/// Hàng nút dưới mỗi câu trả lời của AI.
class _AnswerActions extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onOpenGraph;

  const _AnswerActions({required this.message, this.onOpenGraph});

  static final ButtonStyle _style = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) {
    final codes = message.ragSummary?.matchedCodes ?? const <String>[];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onOpenGraph != null && codes.isNotEmpty)
          TextButton.icon(
            style: _style.copyWith(
              foregroundColor: WidgetStatePropertyAll(AppColors.primary),
            ),
            icon: const Icon(Icons.arrow_forward, size: 14),
            label: const Text(
              'Xem trên đồ thị',
              style: TextStyle(fontSize: 11.5),
            ),
            onPressed: () {
              // Chọn sẵn môn đầu tiên trong ngữ cảnh rồi nhờ shell chuyển tab,
              // để mở đồ thị lên là node đó đã được highlight.
              final subject = AppState.instance.graph.byCode[codes.first];
              if (subject?.id != null) {
                AppState.instance.select(subject!.id);
              }
              onOpenGraph!();
            },
          ),
        TextButton.icon(
          style: _style.copyWith(
            foregroundColor: WidgetStatePropertyAll(AppColors.textSecondary),
          ),
          icon: const Icon(Icons.copy_outlined, size: 14),
          label: const Text('Sao chép', style: TextStyle(fontSize: 11.5)),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: message.content));
            if (context.mounted) Ui.success(context, 'Đã chép câu trả lời.');
          },
        ),
      ],
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
