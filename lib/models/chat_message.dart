import 'graph_rag_context.dart';

enum ChatRole { user, assistant, system }

/// Mot luot hoi/dap trong khung chat AI.
class ChatMessage {
  final ChatRole role;
  final String content;
  final DateTime at;
  final bool isError;

  /// Chỉ có ở tin nhắn của assistant khi câu hỏi trước đó được gửi kèm ngữ
  /// cảnh Graph RAG — cho UI hiển thị lại subgraph nào đã được dùng.
  final GraphRagSummary? ragSummary;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? at,
    this.isError = false,
    this.ragSummary,
  }) : at = at ?? DateTime.now();

  factory ChatMessage.user(String content) =>
      ChatMessage(role: ChatRole.user, content: content);

  factory ChatMessage.assistant(
    String content, {
    bool isError = false,
    GraphRagSummary? ragSummary,
  }) =>
      ChatMessage(
        role: ChatRole.assistant,
        content: content,
        isError: isError,
        ragSummary: ragSummary,
      );

  bool get isUser => role == ChatRole.user;

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': content,
        'at': at.toIso8601String(),
        'isError': isError,
        if (ragSummary != null) 'ragSummary': ragSummary!.toJson(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: ChatRole.values.firstWhere(
          (e) => e.name == json['role'],
          orElse: () => ChatRole.user,
        ),
        content: json['content'] as String? ?? '',
        at: json['at'] != null ? DateTime.tryParse(json['at'] as String) : null,
        isError: json['isError'] as bool? ?? false,
        ragSummary: json['ragSummary'] != null
            ? GraphRagSummary.fromJson(
                json['ragSummary'] as Map<String, dynamic>)
            : null,
      );
}
