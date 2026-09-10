import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chat_message.dart';
import '../../services/ai_service.dart';
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
  final List<ChatMessage> _messages = [];
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

    final history = List<ChatMessage>.from(_messages);

    setState(() {
      _messages.add(ChatMessage.user(text));
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
      setState(() => _messages.add(ChatMessage.assistant(answer)));
    } on AiException catch (e) {
      if (!mounted) return;
      setState(
        () => _messages.add(ChatMessage.assistant(e.message, isError: true)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () =>
            _messages.add(ChatMessage.assistant(e.toString(), isError: true)),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(
          title: 'Trợ lý AI',
          subtitle: _useContext
              ? 'Đang gửi kèm ngữ cảnh đồ thị môn học từ SQLite'
              : 'Đang hỏi thuần, không gửi dữ liệu môn học',
          actions: [
            Row(
              children: [
                const Text(
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
              tooltip: 'Xoá hội thoại',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _messages.isEmpty
                  ? null
                  : () => setState(_messages.clear),
            ),
          ],
        ),
        Expanded(
          child: _messages.isEmpty
              ? _welcome()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 20,
                  ),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= _messages.length) return const _TypingBubble();
                    return _Bubble(message: _messages[i]);
                  },
                ),
        ),
        _composer(),
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
                const Text(
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
                  style: const TextStyle(
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
                        label: Text(
                          s,
                          style: const TextStyle(fontSize: 12),
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
      decoration: const BoxDecoration(
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
                decoration: const InputDecoration(
                  hintText: 'Nhập câu hỏi… (Enter để gửi, Shift+Enter xuống dòng)',
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
    final bg = message.isError
        ? const Color(0xFFFDECEF)
        : isUser
        ? AppColors.primary
        : AppColors.surface;
    final fg = message.isError
        ? AppColors.error
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
            const CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.primaryLight,
              child: Icon(
                Icons.auto_awesome,
                size: 14,
                color: AppColors.primaryDark,
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
              child: SelectableText(
                message.content,
                style: TextStyle(fontSize: 13.5, height: 1.6, color: fg),
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
    return const Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primaryLight,
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryDark,
              ),
            ),
          ),
          SizedBox(width: 10),
          Text(
            'Đang suy nghĩ…',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
