import 'package:flutter/foundation.dart';

import '../models/graph_data.dart';
import '../models/prerequisite.dart';
import '../models/subject.dart';
import '../services/db_service.dart';
import '../services/obsidian_service.dart';
import '../services/settings_service.dart';

/// Store trạng thái dùng chung, không cần package quản lý state bên ngoài.
///
/// Mọi màn hình lắng nghe cùng một [AppState] nên khi thêm/xoá môn ở màn hình
/// danh sách thì đồ thị tự vẽ lại ngay.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  final DbService _db = DbService.instance;
  final ObsidianService _vault = ObsidianService.instance;
  final SettingsService _settings = SettingsService.instance;

  GraphData _graph = GraphData.empty;
  GraphData get graph => _graph;

  String? _vaultPath;
  String? get vaultPath => _vaultPath;
  bool get hasVault => (_vaultPath ?? '').isNotEmpty;

  int? _selectedSubjectId;
  int? get selectedSubjectId => _selectedSubjectId;
  Subject? get selectedSubject =>
      _selectedSubjectId == null ? null : _graph.byId[_selectedSubjectId];

  bool _loading = false;
  bool get loading => _loading;

  Map<String, int> _stats = const {'subjects': 0, 'edges': 0, 'orphans': 0};
  Map<String, int> get stats => _stats;

  /// Nạp lần đầu khi app khởi động.
  Future<void> bootstrap() async {
    _vaultPath = await _settings.getVaultPath();
    await refresh();
  }

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      _graph = await _db.loadGraph();
      _stats = await _db.stats();
      if (_selectedSubjectId != null &&
          !_graph.byId.containsKey(_selectedSubjectId)) {
        _selectedSubjectId = null;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void select(int? subjectId) {
    _selectedSubjectId = subjectId;
    notifyListeners();
  }

  // --- Môn học ---

  Future<int> addSubject(Subject subject) async {
    final id = await _db.insertSubject(subject);
    await refresh();
    return id;
  }

  Future<void> updateSubject(Subject subject) async {
    await _db.updateSubject(subject);
    await refresh();
  }

  Future<void> deleteSubject(int id) async {
    await _db.deleteSubject(id);
    if (_selectedSubjectId == id) _selectedSubjectId = null;
    await refresh();
  }

  // --- Liên kết tiên quyết ---

  Future<void> addEdge({
    required int subjectId,
    required int prerequisiteId,
    String relationType = Prerequisite.kPrerequisite,
  }) async {
    await _db.addEdge(
      subjectId: subjectId,
      prerequisiteId: prerequisiteId,
      relationType: relationType,
    );
    await refresh();
  }

  Future<void> removeEdge({
    required int subjectId,
    required int prerequisiteId,
  }) async {
    await _db.removeEdge(
      subjectId: subjectId,
      prerequisiteId: prerequisiteId,
    );
    await refresh();
  }

  List<Subject> prerequisitesOf(int subjectId) {
    final byId = _graph.byId;
    return _graph.edges
        .where((e) => e.subjectId == subjectId)
        .map((e) => byId[e.prerequisiteId])
        .whereType<Subject>()
        .toList()
      ..sort((a, b) => a.code.compareTo(b.code));
  }

  List<Subject> unlockedBy(int subjectId) {
    final byId = _graph.byId;
    return _graph.edges
        .where((e) => e.prerequisiteId == subjectId)
        .map((e) => byId[e.subjectId])
        .whereType<Subject>()
        .toList()
      ..sort((a, b) => a.code.compareTo(b.code));
  }

  // --- Obsidian Vault ---

  Future<void> setVaultPath(String? path) async {
    await _settings.setVaultPath(path);
    _vaultPath = path;
    notifyListeners();
  }

  Future<VaultSyncReport> importFromVault() async {
    final path = _vaultPath;
    if (path == null || path.isEmpty) {
      throw ObsidianException('Chưa chọn thư mục Obsidian Vault.');
    }
    final report = await _vault.importVault(path);
    await refresh();
    return report;
  }

  Future<int> exportToVault() async {
    final path = _vaultPath;
    if (path == null || path.isEmpty) {
      throw ObsidianException('Chưa chọn thư mục Obsidian Vault.');
    }
    final written = await _vault.exportAll(path);
    await refresh();
    return written;
  }

  Future<List<Subject>?> suggestLearningOrder() => _db.suggestLearningOrder();

  Future<void> resetAll() async {
    await _db.resetAll();
    _selectedSubjectId = null;
    await refresh();
  }
}
