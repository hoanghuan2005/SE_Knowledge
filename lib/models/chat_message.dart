enum ChatRole { user, assistant, system }

/// Mot luot hoi/dap trong khung chat AI.
class ChatMessage {
  final ChatRole role;
  final String content;
  final DateTime at;
  final bool isError;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? at,
    this.isError = false,
  }) : at = at ?? DateTime.now();

  factory ChatMessage.user(String content) =>
      ChatMessage(role: ChatRole.user, content: content);

  factory ChatMessage.assistant(String content, {bool isError = false}) =>
      ChatMessage(role: ChatRole.assistant, content: content, isError: isError);

  bool get isUser => role == ChatRole.user;
}
