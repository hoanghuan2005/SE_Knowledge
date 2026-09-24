import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';

/// Một phiên / đoạn chat lưu trữ các tin nhắn với AI.
class ChatSession {
  final String id;
  String title;
  final DateTime createdAt;
  final List<ChatMessage> messages;

  /// Mã khung CTĐT gắn với phiên chat này (null nếu toàn bộ CSDL).
  String? curriculumCode;

  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    List<ChatMessage>? messages,
    this.curriculumCode,
  }) : messages = messages ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
        'curriculumCode': curriculumCode,
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Đoạn chat mới',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        messages: (json['messages'] as List<dynamic>?)
                ?.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
                .toList() ??
            [],
        curriculumCode: json['curriculumCode'] as String?,
      );
}

/// Dịch vụ quản lý các đoạn chat AI, lưu trữ cục bộ qua SharedPreferences.
class ChatSessionService extends ChangeNotifier {
  ChatSessionService._();
  static final ChatSessionService instance = ChatSessionService._();

  static const String _storageKey = 'ai_chat_sessions_v1';
  List<ChatSession> _sessions = [];
  String? _currentSessionId;
  bool _initialized = false;

  List<ChatSession> get sessions => List.unmodifiable(_sessions);
  String? get currentSessionId => _currentSessionId;

  ChatSession get currentSession {
    if (_sessions.isEmpty) {
      final s = _createNewSessionInternal();
      _sessions.add(s);
      _currentSessionId = s.id;
      return s;
    }
    final found = _sessions.firstWhere(
      (s) => s.id == _currentSessionId,
      orElse: () => _sessions.first,
    );
    _currentSessionId = found.id;
    return found;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _sessions = list
            .map((item) => ChatSession.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      _sessions = [];
    }

    if (_sessions.isEmpty) {
      final s = _createNewSessionInternal();
      _sessions.add(s);
      _currentSessionId = s.id;
    } else {
      _currentSessionId = _sessions.first.id;
    }
    notifyListeners();
  }

  ChatSession _createNewSessionInternal({String? curriculumCode, String? title}) {
    final now = DateTime.now();
    return ChatSession(
      id: 'chat_${now.millisecondsSinceEpoch}',
      title: title ?? 'Đoạn chat mới',
      createdAt: now,
      curriculumCode: curriculumCode,
    );
  }

  void newSession({String? curriculumCode, String? title}) {
    // Nếu session hiện tại còn trống thì dùng luôn và cập nhật khung/tiêu đề
    if (currentSession.messages.isEmpty) {
      if (curriculumCode != null) {
        currentSession.curriculumCode = curriculumCode;
      }
      if (title != null && title.isNotEmpty) {
        currentSession.title = title;
      }
      notifyListeners();
      _save();
      return;
    }
    final s = _createNewSessionInternal(
      curriculumCode: curriculumCode,
      title: title,
    );
    _sessions.insert(0, s);
    _currentSessionId = s.id;
    notifyListeners();
    _save();
  }

  void setCurriculumCode(String? code) {
    if (currentSession.curriculumCode == code) return;
    currentSession.curriculumCode = code;
    notifyListeners();
    _save();
  }

  void selectSession(String id) {
    if (_currentSessionId == id) return;
    _currentSessionId = id;
    notifyListeners();
  }

  void deleteSession(String id) {
    _sessions.removeWhere((s) => s.id == id);
    if (_sessions.isEmpty) {
      final s = _createNewSessionInternal();
      _sessions.add(s);
      _currentSessionId = s.id;
    } else if (_currentSessionId == id) {
      _currentSessionId = _sessions.first.id;
    }
    notifyListeners();
    _save();
  }

  void renameSession(String id, String newTitle) {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    final index = _sessions.indexWhere((s) => s.id == id);
    if (index != -1) {
      _sessions[index].title = trimmed;
      notifyListeners();
      _save();
    }
  }

  void addMessage(ChatMessage message) {
    final session = currentSession;
    session.messages.add(message);

    // Tự động đặt tiêu đề đoạn chat từ câu hỏi đầu tiên của người dùng
    if (message.isUser &&
        (session.title == 'Đoạn chat mới' || session.title.isEmpty)) {
      final clean = message.content.trim().replaceAll('\n', ' ');
      session.title =
          clean.length > 32 ? '${clean.substring(0, 32)}...' : clean;
    }

    notifyListeners();
    _save();
  }

  void clearCurrentSession() {
    currentSession.messages.clear();
    currentSession.title = 'Đoạn chat mới';
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_sessions.map((s) => s.toJson()).toList());
      await prefs.setString(_storageKey, raw);
    } catch (_) {}
  }
}
