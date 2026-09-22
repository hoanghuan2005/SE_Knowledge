import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/graph_data.dart';
import '../models/prerequisite.dart';
import '../models/subject.dart';
import '../models/curriculum.dart';
import '../models/graph_settings.dart';
import '../models/transcript_entry.dart';
import '../services/academic_analytics_service.dart';
import '../services/db_service.dart';
import '../services/fap_markdown_parser.dart';
import '../services/md_intake_service.dart';
import '../services/obsidian_service.dart';
import '../services/settings_service.dart';
import '../services/curriculum_parser_service.dart';
import '../services/subject_delete_guard.dart';
import '../services/transcript_parser_service.dart';
import '../services/window_theme_service.dart';
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
    unawaited(WindowThemeService.setDarkTitleBar(AppColors.isDark));
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
    unawaited(WindowThemeService.setDarkTitleBar(AppColors.isDark));

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
      await _loadTranscript();

      if (_selectedSubjectId != null &&
          !_graph.byId.containsKey(_selectedSubjectId)) {
        _selectedSubjectId = null;
      }

      // Khung đang lọc có thể vừa bị đổi mã, bị xoá, hoặc — với nhóm "ngoài
      // khung" — vừa hết môn nên biến mất khỏi cây. Để con trỏ chỉ vào một mã
      // không còn tồn tại thì DropdownButton lọc khung trên Bản đồ tri thức
      // vỡ khẳng định "đúng một item khớp value" và cả trang thành ô báo lỗi.
      if (_activeCurriculumCode != null &&
          !_curriculumGroups.any((g) => g.code == _activeCurriculumCode)) {
        _activeCurriculumCode = null;
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

  // --- Quản lý thành viên của một tệp môn học ---

  /// Tìm tệp môn học theo mã, chưa có thì tạo. Trả về `curriculums.id`.
  Future<int> ensureCurriculumByCode(String code, {String? name}) async {
    final id = await _db.ensureCurriculumByCode(code: code, name: name);
    await refresh();
    return id;
  }

  /// Gắn một loạt môn vào tệp môn học. Kỳ lấy theo [Subject.semester].
  Future<void> assignSubjectsToCurriculum({
    required int curriculumId,
    required List<Subject> subjects,
  }) async {
    await _db.assignSubjectsToCurriculum(
      curriculumId: curriculumId,
      entries: [
        for (final s in subjects)
          if (s.id != null)
            CurriculumCourseEntry(
              subjectId: s.id!,
              term: s.semester,
              credits: s.credits,
            ),
      ],
    );
    await refresh();
  }

  /// Gỡ môn khỏi một tệp môn học mà không xoá môn khỏi CSDL.
  Future<int> removeSubjectsFromCurriculum({
    required int curriculumId,
    required List<int> subjectIds,
  }) async {
    final n = await _db.removeSubjectsFromCurriculum(
      curriculumId: curriculumId,
      subjectIds: subjectIds,
    );
    await refresh();
    return n;
  }

  /// Chuyển môn sang tệp môn học khác.
  Future<void> moveSubjectsToCurriculum({
    int? fromCurriculumId,
    required int toCurriculumId,
    required List<int> subjectIds,
  }) async {
    await _db.moveSubjectsToCurriculum(
      fromCurriculumId: fromCurriculumId,
      toCurriculumId: toCurriculumId,
      subjectIds: subjectIds,
    );
    await refresh();
  }

  /// Đổi kỳ của một loạt môn trong phạm vi một tệp môn học.
  Future<void> setTermOfSubjects({
    int? curriculumId,
    required List<int> subjectIds,
    required int term,
  }) async {
    await _db.setTermOfSubjects(
      curriculumId: curriculumId,
      subjectIds: subjectIds,
      term: term,
    );
    await refresh();
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

  // ------------------------------------------------------------------
  // BẢNG ĐIỂM CÁ NHÂN
  // ------------------------------------------------------------------

  List<TranscriptEntry> _transcript = const [];
  List<TranscriptEntry> get transcript => _transcript;

  Map<String, TranscriptEntry> _gradeByCode = const {};

  /// Tra điểm theo mã môn (đã viết hoa). Dựng lại trong mỗi [refresh] để luôn
  /// khớp với đồ thị đang hiển thị.
  Map<String, TranscriptEntry> get gradeByCode => _gradeByCode;

  AcademicProfile? _academicProfile;

  /// Tính **một lần** sau mỗi lần nạp, không tính lại trong `build()`: phân
  /// tích rủi ro duyệt toàn bộ cạnh của đồ thị nên không thuộc về đường vẽ
  /// giao diện.
  AcademicProfile? get academicProfile => _academicProfile;

  /// Tiện cho giao diện: chưa nhập bảng điểm thì vẫn có một hồ sơ rỗng để đọc.
  AcademicProfile get academicProfileOrEmpty =>
      _academicProfile ?? AcademicProfile.empty;

  bool get hasTranscript => _transcript.isNotEmpty;

  /// Điểm của một môn theo mã, `null` nghĩa là chưa từng học.
  TranscriptEntry? gradeOf(String code) =>
      _gradeByCode[code.trim().toUpperCase()];

  Future<void> _loadTranscript() async {
    try {
      _transcript = await _db.getTranscript();
      _gradeByCode = await _db.latestGradeByCode();
      _academicProfile = _transcript.isEmpty
          ? null
          : AcademicAnalyticsService.instance.analyze(_transcript, _graph);
    } catch (e) {
      // Bảng điểm là phần cộng thêm: hỏng nó không được phép kéo sập cả lần
      // refresh, vì [refresh] cũng là chỗ nạp đồ thị và cây môn học — ném lỗi
      // ở đây thì mất luôn hai thứ đó, tức là cả app trắng vì một tính năng
      // phụ. Mất bảng điểm thì các màn hình khác vẫn chạy như trước khi có nó.
      _transcript = const [];
      _gradeByCode = const {};
      _academicProfile = null;
      dev.log('Không nạp được bảng điểm: $e');
    }
  }

  /// Đọc file transcript và đối chiếu với CSDL. Chưa ghi gì — kết quả dùng để
  /// dựng màn hình xem trước, đúng mạch `planImport()` của Vault.
  Future<TranscriptImportPlan> planTranscriptImport(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final parsed = TranscriptParserService.instance.parseBytes(
      bytes,
      fileName: p.basename(filePath),
    );
    if (parsed.isEmpty) {
      throw TranscriptImportException(
        'Không đọc được dòng điểm nào từ file này. Kiểm tra lại xem đã tải '
        'đúng file "StudentTranscript_<MSSV>.xls" từ FAP chưa.',
      );
    }
    return _db.planTranscriptImport(
      parsed.entries,
      warnings: parsed.warnings,
    );
  }

  Future<TranscriptImportResult> applyTranscriptPlan(
    TranscriptImportPlan plan, {
    bool createMissingSubjects = false,
  }) async {
    final result = await _db.applyTranscriptPlan(
      plan,
      createMissingSubjects: createMissingSubjects,
    );
    await refresh();
    return result;
  }

  Future<void> clearTranscript() async {
    await _db.clearTranscript();
    await refresh();
  }

  /// Người dùng tự bật/tắt việc tính một dòng vào GPA, ví dụ khi quy chế khoá
  /// của họ khác với cờ mà FAP đánh.
  Future<void> setCountsTowardGpa(int entryId, bool value) async {
    await _db.setCountsTowardGpa(entryId, value);
    await refresh();
  }

  /// Lần nhập bảng điểm gần nhất, để màn hình Cài đặt hiện trạng thái.
  Future<DateTime?> lastTranscriptImportAt() => _db.lastTranscriptImportAt();

  // --- Obsidian Vault ---

  Future<void> setVaultPath(String? path) async {
    await _settings.setVaultPath(path);
    _vaultPath = path;
    notifyListeners();
  }

  Future<VaultSyncReport> importFromVault({
    String subFolder = '',
    VaultImportTarget? target,
  }) async {
    final report = await _vault.importVault(
      _requireVault(),
      subFolder: subFolder,
      target: target,
    );
    await refresh();
    return report;
  }

  // ------------------------------------------------------------------
  // CỔNG NHẬN TRANG FAP TỪ EXTENSION CHROME
  // ------------------------------------------------------------------

  StreamSubscription<IncomingNote>? _intakeSub;

  /// Kết quả lần nhận gần nhất, để màn hình Cài đặt hiện được trạng thái.
  String? _lastFapIntakeMessage;
  String? get lastFapIntakeMessage => _lastFapIntakeMessage;

  /// Nối cổng nhận markdown của extension vào CSDL.
  ///
  /// Công tắc "Tự động lưu vào CSDL khi nhận từ extension" trong Cài đặt trước
  /// đây không nối vào đâu cả: trang được ghi thành file `.md` rồi thôi, nên
  /// cào xong cả khung mà CSDL vẫn trống và đồ thị vẫn rỗng. Tắt công tắc thì
  /// file vẫn nằm sẵn trong `<Vault>/FAP` chờ nút "Quét & Nhập toàn bộ".
  void listenFapIntake() {
    _intakeSub ??= MdIntakeService.instance.onNote.listen(_onIncomingFapNote);
  }

  Future<void> _onIncomingFapNote(IncomingNote note) async {
    if (!await _settings.getAutoSaveFapNotes()) return;
    try {
      final parsed = FapMarkdownParser.parse(note.markdown);
      if (parsed.curriculum != null) {
        await _db.importFapCurriculum(parsed.curriculum!);
      } else if (parsed.syllabus != null) {
        await _db.importFapSyllabus(parsed.syllabus!);
      } else {
        _lastFapIntakeMessage = '${note.title}: ${parsed.message}';
        notifyListeners();
        return;
      }

      // Trang vừa nạp có thể là mắt xích còn thiếu của một cạnh đã chờ sẵn.
      final edges = await _db.syncPrerequisitesFromFap();
      _lastFapIntakeMessage = edges > 0
          ? 'Đã nạp "${note.title}" và dựng thêm $edges liên kết tiên quyết.'
          : 'Đã nạp "${note.title}".';
      await refresh();
    } catch (e) {
      _lastFapIntakeMessage = 'Không nạp được "${note.title}": $e';
      dev.log('Nhập trang FAP thất bại: $e');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _intakeSub?.cancel();
    _intakeSub = null;
    super.dispose();
  }

  /// Xem trước thay đổi trước khi nạp Vault vào CSDL. Chưa ghi gì.
  Future<VaultSyncPlan> planImportFromVault({String subFolder = ''}) =>
      _vault.planImport(_requireVault(), subFolder: subFolder);

  /// Các thư mục con có thể chọn làm phạm vi nạp.
  Future<List<VaultFolderOption>> listVaultFolders() =>
      _vault.listImportableFolders(_requireVault());

  /// Ghi một kế hoạch đã được người dùng xác nhận xuống CSDL.
  Future<VaultSyncReport> applyVaultPlan(
    VaultSyncPlan plan, {
    VaultImportTarget? target,
  }) async {
    final report = await _vault.applyPlan(plan, target: target);
    await refresh();
    return report;
  }

  /// Ghi ra Vault đúng một nhóm môn (một tệp môn học hoặc một kỳ).
  ///
  /// Đi theo thư mục đích của lần ghi đầy đủ gần nhất, để môn mới không rơi
  /// lạc ra gốc Vault trong khi cả bộ còn lại nằm trong thư mục con.
  Future<int> exportSubjectsToVault(List<Subject> subjects) async {
    final written = await _vault.exportSubjects(
      _requireVault(),
      subjects,
      subFolder: await lastExportSubFolder(),
    );
    await refresh();
    return written;
  }

  /// Chụp trạng thái Vault để hộp thoại "Ghi ra Vault" tính con số xem trước.
  /// Không ghi gì.
  Future<VaultExportPreview> buildExportPreview({String subFolder = ''}) =>
      _vault.buildExportPreview(_requireVault(), subFolder: subFolder);

  /// Thư mục con đã dùng ở lần ghi trước, để hộp thoại điền sẵn.
  Future<String> lastExportSubFolder() async =>
      (await _settings.getExportSubFolder()) ?? '';

  /// Đường dẫn vừa chọn trong hộp thoại hệ điều hành -> thư mục con của Vault.
  /// `null` nghĩa là chọn ra ngoài Vault.
  String? subFolderFromAbsolute(String absolute) =>
      _vault.subFolderFromAbsolute(_requireVault(), absolute);

  /// Ghi ra Vault đúng nhóm môn người dùng đã tích trong hộp thoại.
  Future<VaultExportReport> exportSelectionToVault(
    List<Subject> subjects, {
    bool writeIndex = false,
    String subFolder = '',
    bool moveExisting = true,
  }) async {
    final vault = _requireVault();
    final report = await _vault.exportSelection(
      vault,
      subjects: subjects,
      writeIndex: writeIndex,
      subFolder: subFolder,
      moveExisting: moveExisting,
    );
    await _settings.setExportSubFolder(
      _vault.normalizeSubFolder(vault, subFolder),
    );
    await refresh();
    return report;
  }

  String _requireVault() {
    final path = _vaultPath;
    if (path == null || path.isEmpty) {
      throw ObsidianException('Chưa chọn thư mục Obsidian Vault.');
    }
    return path;
  }

  Future<List<Subject>?> suggestLearningOrder([GraphData? customGraph]) =>
      _db.suggestLearningOrder(customGraph: customGraph ?? currentGraph);

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

/// Lỗi nghiệp vụ của luồng nhập bảng điểm, để giao diện hiện một câu tử tế
/// thay vì stack trace.
class TranscriptImportException implements Exception {
  final String message;
  TranscriptImportException(this.message);
  @override
  String toString() => message;
}
