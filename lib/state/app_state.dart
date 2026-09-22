import 'package:flutter/material.dart';

import '../models/graph_data.dart';
import '../models/prerequisite.dart';
import '../models/subject.dart';
import '../models/curriculum.dart';
import '../models/graph_settings.dart';
import '../services/db_service.dart';
import '../services/obsidian_service.dart';
import '../services/settings_service.dart';
import '../services/curriculum_parser_service.dart';
import '../services/subject_delete_guard.dart';
import '../utils/app_colors.dart';

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

  // --- Theme Mode ---
  ThemeMode _themeMode = ThemeMode.dark;
  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> toggleTheme() async {
    final next = isDark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(next);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    AppColors.isDark = (mode == ThemeMode.dark);
    await _settings.setThemeMode(mode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }

  // --- Graph Custom Settings ---
  GraphSettings _graphSettings = GraphSettings.defaults;
  GraphSettings get graphSettings => _graphSettings;

  void updateGraphSettings(GraphSettings newSettings) {
    _graphSettings = newSettings;
    _settings.setGraphSettings(newSettings);
    notifyListeners();
  }

  void resetGraphSettings() {
    updateGraphSettings(GraphSettings.defaults);
  }

  GraphData _graph = GraphData.empty;
  GraphData get graph => _graph;

  String? _vaultPath;
  String? get vaultPath => _vaultPath;
  bool get hasVault => (_vaultPath ?? '').isNotEmpty;

  int? _selectedSubjectId;
  int? get selectedSubjectId => _selectedSubjectId;
  Subject? get selectedSubject =>
      _selectedSubjectId == null ? null : _graph.byId[_selectedSubjectId];

  // --- Workspace Note Tabs (Obsidian style) ---
  final List<Subject> _openNoteTabs = [];
  List<Subject> get openNoteTabs => List.unmodifiable(_openNoteTabs);

  Subject? _activeNote;
  Subject? get activeNote => _activeNote;

  void openNoteTab(Subject subject) {
    if (!_openNoteTabs.any((s) => s.id == subject.id || s.code.toUpperCase() == subject.code.toUpperCase())) {
      _openNoteTabs.add(subject);
    }
    _activeNote = subject;
    _selectedSubjectId = subject.id;
    notifyListeners();
  }

  void closeNoteTab(Subject subject) {
    _openNoteTabs.removeWhere((s) => s.id == subject.id || s.code.toUpperCase() == subject.code.toUpperCase());
    if (_activeNote?.id == subject.id || _activeNote?.code.toUpperCase() == subject.code.toUpperCase()) {
      _activeNote = _openNoteTabs.isNotEmpty ? _openNoteTabs.last : null;
    }
    notifyListeners();
  }

  void setActiveNote(Subject? subject) {
    _activeNote = subject;
    if (subject != null) {
      _selectedSubjectId = subject.id;
    }
    notifyListeners();
  }

  bool _loading = false;
  bool get loading => _loading;

  Map<String, int> _stats = const {'subjects': 0, 'edges': 0, 'orphans': 0};
  Map<String, int> get stats => _stats;

  List<Map<String, dynamic>> _curriculums = [];
  List<Map<String, dynamic>> get curriculums => _curriculums;

  List<CurriculumGroup> _curriculumGroups = [];
  List<CurriculumGroup> get curriculumGroups => _curriculumGroups;

  String? _activeCurriculumCode;
  String? get activeCurriculumCode => _activeCurriculumCode;

  void setActiveCurriculum(String? code) {
    if (_activeCurriculumCode == code) return;
    _activeCurriculumCode = code;
    notifyListeners();
  }

  /// Dữ liệu đồ thị lọc theo Khung CTĐT đang hoạt động (null = Toàn bộ môn trong DB)
  GraphData get currentGraph {
    if (_activeCurriculumCode == null) return _graph;

    CurriculumGroup? group;
    for (final g in _curriculumGroups) {
      if (g.code == _activeCurriculumCode) {
        group = g;
        break;
      }
    }
    if (group == null) return _graph;

    final groupSubjects = group.semesters.values.expand((list) => list).toList();
    final groupSubjectIds = groupSubjects.map((s) => s.id).whereType<int>().toSet();

    final groupEdges = _graph.edges.where((e) {
      return groupSubjectIds.contains(e.subjectId) &&
          groupSubjectIds.contains(e.prerequisiteId);
    }).toList();

    return GraphData(subjects: groupSubjects, edges: groupEdges);
  }

  /// Nạp lần đầu khi app khởi động.
  Future<void> bootstrap() async {
    final savedTheme = await _settings.getThemeMode();
    _themeMode = savedTheme == 'light' ? ThemeMode.light : ThemeMode.dark;
    AppColors.isDark = (_themeMode == ThemeMode.dark);

    _vaultPath = await _settings.getVaultPath();
    _graphSettings = await _settings.getGraphSettings();

    // Dọn dẹp các node PLO rác cũ nếu có trong CSDL
    await _db.cleanInvalidPloSubjects();

    await refresh();
  }

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      _graph = await _db.loadGraph();
      _stats = await _db.stats();
      _curriculums = await _db.getCurriculumsWithStats();
      _curriculumGroups = await _db.getCurriculumTreeData();

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

  // --- Quản lý Khung chương trình (Curriculum CRUD) ---

  Future<int> addCurriculum({
    required String code,
    required String name,
    required String major,
    int totalCredits = 145,
    String decisionNo = '',
    String description = '',
  }) async {
    final id = await _db.insertCurriculum(
      code: code,
      name: name,
      major: major,
      totalCredits: totalCredits,
      decisionNo: decisionNo,
      description: description,
    );
    await refresh();
    return id;
  }

  Future<void> updateCurriculum(int id, {
    String? code,
    String? name,
    String? major,
    int? totalCredits,
    String? decisionNo,
    String? description,
  }) async {
    await _db.updateCurriculum(
      id,
      code: code,
      name: name,
      major: major,
      totalCredits: totalCredits,
      decisionNo: decisionNo,
      description: description,
    );
    await refresh();
  }

  Future<void> deleteCurriculum(int id, {bool deleteSubjects = false}) async {
    final group = _curriculumGroups.firstWhere(
      (g) => g.curriculumId == id,
      orElse: () => CurriculumGroup(
        curriculumId: id,
        code: '',
        name: '',
        major: '',
        totalCredits: 0,
        semesters: {},
        totalSubjects: 0,
      ),
    );
    final deletedCode = group.code;

    await _db.deleteCurriculum(id, deleteSubjects: deleteSubjects);

    if (deletedCode.isNotEmpty && _activeCurriculumCode == deletedCode) {
      _activeCurriculumCode = null;
    }
    await refresh();

    if (deleteSubjects) {
      _openNoteTabs.removeWhere((tab) => !_graph.byId.containsKey(tab.id));
      if (_activeNote != null && !_graph.byId.containsKey(_activeNote!.id)) {
        _activeNote = _openNoteTabs.isNotEmpty ? _openNoteTabs.last : null;
      }
      notifyListeners();
    }
  }

  /// Dọn dẹp thủ công các node PLO rác
  Future<int> cleanLegacyPloSubjects() async {
    final count = await _db.cleanInvalidPloSubjects();
    if (count > 0) {
      await refresh();
    }
    return count;
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

  /// Xem trước hậu quả của việc xoá một môn, để dựng hộp thoại cảnh báo.
  /// Chỉ đọc, chưa ghi gì xuống CSDL.
  Future<DeleteImpact> analyzeDelete(int subjectId) =>
      SubjectDeleteGuard.instance.analyze(subjectId);

  /// Xoá môn sau khi người dùng đã xác nhận trên hộp thoại.
  ///
  /// [strategy] chọn giữa xoá thẳng và nối tắt các liên kết bắc cầu;
  /// [deleteNoteFile] quyết định có xoá luôn file `.md` trong Vault không —
  /// giữ file lại thì lần nhập dữ liệu sau sẽ tạo lại đúng môn vừa xoá.
  Future<DeleteResult> deleteSubjectSafely(
    DeleteImpact impact, {
    DeleteStrategy strategy = DeleteStrategy.cascade,
    bool deleteNoteFile = false,
  }) async {
    final result = await SubjectDeleteGuard.instance.execute(
      impact,
      strategy: strategy,
      deleteNoteFile: deleteNoteFile,
    );
    if (_selectedSubjectId == impact.target.id) _selectedSubjectId = null;
    _openNoteTabs.removeWhere((s) => s.id == impact.target.id);
    if (_activeNote?.id == impact.target.id) {
      _activeNote = _openNoteTabs.isNotEmpty ? _openNoteTabs.last : null;
    }
    await refresh();
    return result;
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

  /// Xem trước thay đổi trước khi nạp Vault vào CSDL. Chưa ghi gì.
  Future<VaultSyncPlan> planImportFromVault() {
    final path = _vaultPath;
    if (path == null || path.isEmpty) {
      throw ObsidianException('Chưa chọn thư mục Obsidian Vault.');
    }
    return _vault.planImport(path);
  }

  /// Ghi một kế hoạch đã được người dùng xác nhận xuống CSDL.
  Future<VaultSyncReport> applyVaultPlan(VaultSyncPlan plan) async {
    final report = await _vault.applyPlan(plan);
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

  // --- Curriculum (FLM Scraper & Cache & Auto DB Sync) ---
  Curriculum? _curriculum;
  Curriculum? get curriculum => _curriculum;

  bool _isScrapingCurriculum = false;
  bool get isScrapingCurriculum => _isScrapingCurriculum;

  String? _curriculumError;
  String? get curriculumError => _curriculumError;

  CurriculumImportResult? _lastImportResult;
  CurriculumImportResult? get lastImportResult => _lastImportResult;

  /// Nạp đối tượng Curriculum vào CSDL SQLite và cập nhật toàn bộ đồ thị
  Future<CurriculumImportResult> importCurriculumToDb(Curriculum curriculum) async {
    final res = await _db.importCurriculum(curriculum);
    _lastImportResult = res;
    await refresh();
    return res;
  }

  /// Bóc tách chương trình học. Mặc định [autoSaveToDb] = true:
  /// Ngay khi cào xong sẽ tự động lưu thẳng vào CSDL SQLite và làm mới đồ thị.
  Future<Curriculum> loadCurriculum({
    String? rawHtml,
    bool forceRefresh = false,
    bool autoSaveToDb = true,
  }) async {
    _isScrapingCurriculum = true;
    _curriculumError = null;
    notifyListeners();

    try {
      final result = await CurriculumParserService.instance.getCurriculum(
        rawHtml: rawHtml,
        forceRefresh: forceRefresh,
      );
      _curriculum = result;

      // Tự động lưu vào SQLite DB nếu có môn học hợp lệ
      if (autoSaveToDb && result.semesters.isNotEmpty) {
        _lastImportResult = await _db.importCurriculum(result);
        await refresh();
      }

      return result;
    } catch (e) {
      _curriculumError = e.toString();
      rethrow;
    } finally {
      _isScrapingCurriculum = false;
      notifyListeners();
    }
  }
}
