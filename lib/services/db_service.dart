import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/graph_data.dart';
import '../models/prerequisite.dart';
import '../models/subject.dart';

/// Tầng truy cập dữ liệu duy nhất của ứng dụng.
///
/// Kiến trúc: Standalone Desktop App + Embedded Database.
/// Toàn bộ dữ liệu nằm trong MỘT file `se_knowledge.db` trên máy người dùng,
/// không có server, không cần cài MySQL, chạy offline 100%.
///
/// Vẫn vận dụng đầy đủ đặc tính CSDL quan hệ: PRIMARY KEY, FOREIGN KEY,
/// UNIQUE constraint, CHECK, ON DELETE CASCADE, INDEX, JOIN và transaction.
class DbService {
  DbService._();
  static final DbService instance = DbService._();

  static const String dbFileName = 'se_knowledge.db';
  static const int dbVersion = 1;

  Database? _db;
  String? _dbPath;

  /// Đường dẫn tuyệt đối của file .db (hiển thị trong màn hình Cài đặt).
  String get databasePath => _dbPath ?? '(chưa khởi tạo)';

  /// Nạp thư viện SQLite bản native cho desktop.
  /// Gọi một lần duy nhất trong `main()` trước `runApp`.
  static void registerFfi() => sqfliteFfiInit();

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final path = p.join(dir.path, dbFileName);
    _dbPath = path;

    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: dbVersion,
        onConfigure: (db) async {
          // SQLite tắt FOREIGN KEY theo mặc định -> phải bật thủ công.
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE subjects (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        code        TEXT    NOT NULL UNIQUE,
        name        TEXT    NOT NULL,
        semester    INTEGER NOT NULL DEFAULT 1,
        credits     INTEGER NOT NULL DEFAULT 3,
        description TEXT    NOT NULL DEFAULT '',
        note_path   TEXT,
        created_at  TEXT    NOT NULL,
        updated_at  TEXT    NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE prerequisites (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        subject_id      INTEGER NOT NULL,
        prerequisite_id INTEGER NOT NULL,
        relation_type   TEXT    NOT NULL DEFAULT 'PREREQUISITE',
        UNIQUE (subject_id, prerequisite_id),
        CHECK (subject_id <> prerequisite_id),
        FOREIGN KEY (subject_id)      REFERENCES subjects (id) ON DELETE CASCADE,
        FOREIGN KEY (prerequisite_id) REFERENCES subjects (id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_prereq_subject ON prerequisites (subject_id)',
    );
    await db.execute(
      'CREATE INDEX idx_prereq_parent ON prerequisites (prerequisite_id)',
    );
    await db.execute('CREATE INDEX idx_subject_sem ON subjects (semester)');

    await _seed(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Version 1 là bản đầu tiên, chưa có migration nào.
  }

  /// Dữ liệu mẫu để mở app lên là có đồ thị xem ngay (an toàn khi demo).
  Future<void> _seed(Database db) async {
    final now = DateTime.now().toIso8601String();

    Future<int> add(
      String code,
      String name,
      int sem,
      int credits,
      String desc,
    ) {
      return db.insert('subjects', {
        'code': code,
        'name': name,
        'semester': sem,
        'credits': credits,
        'description': desc,
        'created_at': now,
        'updated_at': now,
      });
    }

    final prf = await add(
      'PRF192',
      'Programming Fundamentals',
      1,
      3,
      'Nhập môn lập trình C.',
    );
    final mad = await add(
      'MAD101',
      'Discrete Mathematics',
      1,
      3,
      'Toán rời rạc, logic, lý thuyết đồ thị.',
    );
    final csd = await add(
      'CSD201',
      'Data Structures and Algorithms',
      2,
      3,
      'Cấu trúc dữ liệu và thuật toán.',
    );
    final dbi = await add(
      'DBI202',
      'Database Systems',
      2,
      3,
      'Mô hình quan hệ, SQL, chuẩn hoá.',
    );
    final prj = await add(
      'PRJ301',
      'Java Web Application Development',
      3,
      3,
      'Servlet, JSP, mô hình MVC.',
    );
    final prm = await add(
      'PRM393',
      'Mobile Programming',
      4,
      3,
      'Phát triển ứng dụng đa nền tảng với Flutter.',
    );
    final swr = await add(
      'SWR302',
      'Software Requirement',
      4,
      3,
      'Thu thập và đặc tả yêu cầu.',
    );

    Future<void> link(int subject, int prereq, [String type = 'PREREQUISITE']) {
      return db.insert('prerequisites', {
        'subject_id': subject,
        'prerequisite_id': prereq,
        'relation_type': type,
      });
    }

    await link(csd, prf);
    await link(csd, mad);
    await link(dbi, mad);
    await link(prj, csd);
    await link(prj, dbi);
    await link(prm, prj);
    await link(swr, dbi, 'RELATED');
  }

  // ------------------------------------------------------------------
  // SUBJECTS (Nodes)
  // ------------------------------------------------------------------

  Future<List<Subject>> getSubjects({String? keyword}) async {
    final db = await database;
    final kw = keyword?.trim() ?? '';
    final rows = await db.query(
      'subjects',
      where: kw.isEmpty ? null : 'code LIKE ? OR name LIKE ?',
      whereArgs: kw.isEmpty ? null : ['%$kw%', '%$kw%'],
      orderBy: 'semester ASC, code ASC',
    );
    return rows.map(Subject.fromMap).toList();
  }

  Future<Subject?> getSubjectById(int id) async {
    final db = await database;
    final rows = await db.query(
      'subjects',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Subject.fromMap(rows.first);
  }

  Future<Subject?> getSubjectByCode(String code) async {
    final db = await database;
    final rows = await db.query(
      'subjects',
      where: 'code = ?',
      whereArgs: [code.trim().toUpperCase()],
      limit: 1,
    );
    return rows.isEmpty ? null : Subject.fromMap(rows.first);
  }

  /// Thêm môn học. Ném [DbConflictException] nếu mã môn đã tồn tại (UNIQUE).
  Future<int> insertSubject(Subject subject) async {
    final db = await database;
    try {
      return await db.insert('subjects', subject.toMap());
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw DbConflictException('Mã môn "${subject.code}" đã tồn tại.');
      }
      rethrow;
    }
  }

  Future<void> updateSubject(Subject subject) async {
    assert(subject.id != null, 'Không thể update môn chưa có id');
    final db = await database;
    try {
      await db.update(
        'subjects',
        subject.copyWith(updatedAt: DateTime.now()).toMap(),
        where: 'id = ?',
        whereArgs: [subject.id],
      );
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw DbConflictException('Mã môn "${subject.code}" đã tồn tại.');
      }
      rethrow;
    }
  }

  /// Xoá môn học. ON DELETE CASCADE tự dọn sạch mọi edge liên quan.
  Future<void> deleteSubject(int id) async {
    final db = await database;
    await db.delete('subjects', where: 'id = ?', whereArgs: [id]);
  }

  /// Tìm môn theo mã, chưa có thì tạo mới. Dùng khi đồng bộ từ Obsidian Vault.
  Future<int> upsertSubjectByCode(Subject subject) async {
    final existing = await getSubjectByCode(subject.code);
    if (existing == null) {
      return insertSubject(subject);
    }
    await updateSubject(
      existing.copyWith(
        name: subject.name,
        semester: subject.semester,
        credits: subject.credits,
        description: subject.description,
        notePath: subject.notePath,
      ),
    );
    return existing.id!;
  }

  // ------------------------------------------------------------------
  // PREREQUISITES (Edges)
  // ------------------------------------------------------------------

  Future<List<Prerequisite>> getEdges() async {
    final db = await database;
    final rows = await db.query('prerequisites');
    return rows.map(Prerequisite.fromMap).toList();
  }

  /// Danh sách môn tiên quyết của [subjectId] (dùng INNER JOIN).
  Future<List<Subject>> getPrerequisitesOf(int subjectId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT s.*
      FROM subjects s
      INNER JOIN prerequisites pr ON pr.prerequisite_id = s.id
      WHERE pr.subject_id = ?
      ORDER BY s.semester ASC, s.code ASC
      ''',
      [subjectId],
    );
    return rows.map(Subject.fromMap).toList();
  }

  /// Danh sách môn được mở ra sau khi học xong [subjectId].
  Future<List<Subject>> getUnlockedBy(int subjectId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT s.*
      FROM subjects s
      INNER JOIN prerequisites pr ON pr.subject_id = s.id
      WHERE pr.prerequisite_id = ?
      ORDER BY s.semester ASC, s.code ASC
      ''',
      [subjectId],
    );
    return rows.map(Subject.fromMap).toList();
  }

  /// Thêm liên kết tiên quyết. Chặn tự trỏ chính mình và chặn tạo chu trình.
  Future<void> addEdge({
    required int subjectId,
    required int prerequisiteId,
    String relationType = Prerequisite.kPrerequisite,
  }) async {
    if (subjectId == prerequisiteId) {
      throw DbConflictException('Một môn không thể là tiên quyết của chính nó.');
    }
    if (await _wouldCreateCycle(subjectId, prerequisiteId)) {
      throw DbConflictException(
        'Liên kết này tạo ra chu trình trong đồ thị tiên quyết.',
      );
    }
    final db = await database;
    try {
      await db.insert('prerequisites', {
        'subject_id': subjectId,
        'prerequisite_id': prerequisiteId,
        'relation_type': relationType,
      });
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw DbConflictException('Liên kết này đã tồn tại.');
      }
      rethrow;
    }
  }

  Future<void> removeEdge({
    required int subjectId,
    required int prerequisiteId,
  }) async {
    final db = await database;
    await db.delete(
      'prerequisites',
      where: 'subject_id = ? AND prerequisite_id = ?',
      whereArgs: [subjectId, prerequisiteId],
    );
  }

  /// Nếu thêm edge `prerequisiteId -> subjectId` thì có sinh chu trình không?
  /// Chu trình xuất hiện khi `subjectId` đã là tổ tiên của `prerequisiteId`.
  Future<bool> _wouldCreateCycle(int subjectId, int prerequisiteId) async {
    final edges = await getEdges();
    final parents = <int, List<int>>{};
    for (final e in edges) {
      parents.putIfAbsent(e.subjectId, () => []).add(e.prerequisiteId);
    }

    final stack = <int>[prerequisiteId];
    final seen = <int>{};
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (current == subjectId) return true;
      if (!seen.add(current)) continue;
      stack.addAll(parents[current] ?? const []);
    }
    return false;
  }

  // ------------------------------------------------------------------
  // GRAPH & THỐNG KÊ
  // ------------------------------------------------------------------

  Future<GraphData> loadGraph() async {
    final subjects = await getSubjects();
    final edges = await getEdges();
    return GraphData(subjects: subjects, edges: edges);
  }

  Future<Map<String, int>> stats() async {
    final db = await database;
    final s = await db.rawQuery('SELECT COUNT(*) AS c FROM subjects');
    final e = await db.rawQuery('SELECT COUNT(*) AS c FROM prerequisites');
    final orphan = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM subjects s
      WHERE NOT EXISTS (SELECT 1 FROM prerequisites p WHERE p.subject_id = s.id)
        AND NOT EXISTS (SELECT 1 FROM prerequisites p WHERE p.prerequisite_id = s.id)
    ''');
    return {
      'subjects': (s.first['c'] as int?) ?? 0,
      'edges': (e.first['c'] as int?) ?? 0,
      'orphans': (orphan.first['c'] as int?) ?? 0,
    };
  }

  /// Sắp xếp topo: gợi ý thứ tự học hợp lệ (thuật toán Kahn).
  /// Trả về null nếu đồ thị còn chu trình.
  Future<List<Subject>?> suggestLearningOrder() async {
    final graph = await loadGraph();
    final byId = graph.byId;
    final indegree = <int, int>{for (final id in byId.keys) id: 0};
    final children = <int, List<int>>{};

    for (final e in graph.edges) {
      if (!byId.containsKey(e.subjectId) ||
          !byId.containsKey(e.prerequisiteId)) {
        continue;
      }
      indegree[e.subjectId] = (indegree[e.subjectId] ?? 0) + 1;
      children.putIfAbsent(e.prerequisiteId, () => []).add(e.subjectId);
    }

    int compare(int a, int b) {
      final sa = byId[a]!;
      final sb = byId[b]!;
      final bySem = sa.semester.compareTo(sb.semester);
      return bySem != 0 ? bySem : sa.code.compareTo(sb.code);
    }

    final ready = indegree.entries
        .where((x) => x.value == 0)
        .map((x) => x.key)
        .toList()
      ..sort(compare);

    final result = <Subject>[];
    while (ready.isNotEmpty) {
      final id = ready.removeAt(0);
      result.add(byId[id]!);
      for (final child in children[id] ?? const <int>[]) {
        indegree[child] = indegree[child]! - 1;
        if (indegree[child] == 0) ready.add(child);
      }
      ready.sort(compare);
    }

    return result.length == byId.length ? result : null;
  }

  /// Xoá toàn bộ dữ liệu (dùng trong Cài đặt khi muốn làm lại demo).
  Future<void> resetAll() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('prerequisites');
      await txn.delete('subjects');
    });
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Kích thước file .db theo byte (hiển thị trong Cài đặt).
  Future<int> databaseSizeInBytes() async {
    final path = _dbPath;
    if (path == null) return 0;
    final file = File(path);
    return await file.exists() ? file.length() : 0;
  }
}

/// Lỗi nghiệp vụ từ tầng DB (trùng khoá, chu trình, ...) để UI hiển thị tử tế.
class DbConflictException implements Exception {
  final String message;
  DbConflictException(this.message);
  @override
  String toString() => message;
}
