import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/curriculum.dart';
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
  static const int dbVersion = 2;

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
    // 1. Bảng Khung chương trình ngành (Curriculums)
    await db.execute('''
      CREATE TABLE curriculums (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        code          TEXT    NOT NULL UNIQUE,
        name          TEXT    NOT NULL,
        major         TEXT    NOT NULL,
        total_credits INTEGER NOT NULL DEFAULT 145,
        decision_no   TEXT    NOT NULL DEFAULT '',
        description   TEXT    NOT NULL DEFAULT '',
        created_at    TEXT    NOT NULL,
        updated_at    TEXT    NOT NULL
      )
    ''');

    // 2. Bảng Danh mục môn học gốc (Master Subjects)
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

    // 3. Bảng Node môn học thuộc Khung chương trình (Curriculum Courses / Nodes)
    await db.execute('''
      CREATE TABLE curriculum_courses (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        curriculum_id INTEGER NOT NULL,
        subject_id    INTEGER NOT NULL,
        term          INTEGER NOT NULL DEFAULT 1,
        credits       INTEGER NOT NULL DEFAULT 3,
        UNIQUE (curriculum_id, subject_id),
        FOREIGN KEY (curriculum_id) REFERENCES curriculums (id) ON DELETE CASCADE,
        FOREIGN KEY (subject_id)    REFERENCES subjects (id)    ON DELETE CASCADE
      )
    ''');

    // 4. Bảng liên kết tiên quyết giữa các môn (Prerequisites / Edges)
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
    await db.execute(
      'CREATE INDEX idx_curr_course_curr ON curriculum_courses (curriculum_id)',
    );
    await db.execute(
      'CREATE INDEX idx_curr_course_subj ON curriculum_courses (subject_id)',
    );
    await db.execute('CREATE INDEX idx_curr_code ON curriculums (code)');

    await _seed(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS curriculums (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          code          TEXT    NOT NULL UNIQUE,
          name          TEXT    NOT NULL,
          major         TEXT    NOT NULL,
          total_credits INTEGER NOT NULL DEFAULT 145,
          decision_no   TEXT    NOT NULL DEFAULT '',
          description   TEXT    NOT NULL DEFAULT '',
          created_at    TEXT    NOT NULL,
          updated_at    TEXT    NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS curriculum_courses (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          curriculum_id INTEGER NOT NULL,
          subject_id    INTEGER NOT NULL,
          term          INTEGER NOT NULL DEFAULT 1,
          credits       INTEGER NOT NULL DEFAULT 3,
          UNIQUE (curriculum_id, subject_id),
          FOREIGN KEY (curriculum_id) REFERENCES curriculums (id) ON DELETE CASCADE,
          FOREIGN KEY (subject_id)    REFERENCES subjects (id)    ON DELETE CASCADE
        )
      ''');

      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_curr_course_curr ON curriculum_courses (curriculum_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_curr_course_subj ON curriculum_courses (subject_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_curr_code ON curriculums (code)',
      );
    }
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

    // Tạo khung chương trình mẫu (BIT_SE)
    final currId = await db.insert('curriculums', {
      'code': 'BIT_SE',
      'name': 'Bachelor Program of Information Technology, Software Engineering Major',
      'major': 'Kỹ thuật phần mềm (Software Engineering - SE)',
      'total_credits': 145,
      'decision_no': '577/QĐ-ĐHFPT',
      'description': 'Đào tạo cử nhân ngành CNTT, chuyên ngành Kỹ thuật phần mềm.',
      'created_at': now,
      'updated_at': now,
    });

    Future<void> addNode(int subj, int term, int cr) {
      return db.insert('curriculum_courses', {
        'curriculum_id': currId,
        'subject_id': subj,
        'term': term,
        'credits': cr,
      });
    }

    await addNode(prf, 1, 3);
    await addNode(mad, 1, 3);
    await addNode(csd, 2, 3);
    await addNode(dbi, 2, 3);
    await addNode(prj, 3, 3);
    await addNode(prm, 4, 3);
    await addNode(swr, 4, 3);
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
  ///
  /// Xoá thẳng, không cảnh báo. Giao diện nên gọi qua `SubjectDeleteGuard` để
  /// người dùng biết trước mình sắp mất những liên kết nào.
  Future<void> deleteSubject(int id) async {
    final db = await database;
    await db.delete('subjects', where: 'id = ?', whereArgs: [id]);
  }

  /// Xoá môn học sau khi đã nối tắt các liên kết bắc cầu, trong **một
  /// transaction duy nhất**.
  ///
  /// Xoá một môn nằm giữa chuỗi `A -> B -> C` làm mất cả hai cạnh. Truyền
  /// [rewireEdges] gồm cạnh `A -> C` để lộ trình học không bị đứt. Gói chung
  /// một transaction để không bao giờ rơi vào trạng thái nửa vời: nối tắt
  /// xong mà xoá hỏng, hoặc xoá xong mà chưa kịp nối.
  ///
  /// Các cạnh truyền vào phải được kiểm tra chu trình từ trước (xem
  /// `SubjectDeleteGuard`) — ở đây chỉ ghi, không kiểm tra lại.
  Future<void> deleteSubjectWithRewire({
    required int id,
    List<Prerequisite> rewireEdges = const [],
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final edge in rewireEdges) {
        await txn.insert(
          'prerequisites',
          {
            'subject_id': edge.subjectId,
            'prerequisite_id': edge.prerequisiteId,
            'relation_type': edge.relationType,
          },
          // Cạnh đã tồn tại thì bỏ qua, không làm hỏng cả transaction.
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await txn.delete('subjects', where: 'id = ?', whereArgs: [id]);
    });
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
    final c = await db.rawQuery('SELECT COUNT(*) AS c FROM curriculums');
    final orphan = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM subjects s
      WHERE NOT EXISTS (SELECT 1 FROM prerequisites p WHERE p.subject_id = s.id)
        AND NOT EXISTS (SELECT 1 FROM prerequisites p WHERE p.prerequisite_id = s.id)
    ''');
    return {
      'subjects': (s.first['c'] as int?) ?? 0,
      'edges': (e.first['c'] as int?) ?? 0,
      'curriculums': (c.first['c'] as int?) ?? 0,
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

  /// Lấy danh sách các khung chương trình đã lưu trong CSDL
  Future<List<Map<String, dynamic>>> getCurriculums() async {
    final db = await database;
    return db.query('curriculums', orderBy: 'code ASC');
  }

  /// Lấy danh sách khung CTĐT kèm số môn và số học kỳ
  Future<List<Map<String, dynamic>>> getCurriculumsWithStats() async {
    final db = await database;
    return db.rawQuery('''
      SELECT c.*,
             COUNT(DISTINCT cc.subject_id) AS course_count,
             COUNT(DISTINCT cc.term) AS semester_count
      FROM curriculums c
      LEFT JOIN curriculum_courses cc ON cc.curriculum_id = c.id
      GROUP BY c.id
      ORDER BY c.code ASC
    ''');
  }

  /// Thêm khung chương trình mới thủ công
  Future<int> insertCurriculum({
    required String code,
    required String name,
    required String major,
    int totalCredits = 145,
    String decisionNo = '',
    String description = '',
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return db.insert('curriculums', {
      'code': code.trim().toUpperCase(),
      'name': name.trim(),
      'major': major.trim().isNotEmpty ? major.trim() : name.trim(),
      'total_credits': totalCredits,
      'decision_no': decisionNo.trim(),
      'description': description.trim(),
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Cập nhật thông tin khung chương trình
  Future<int> updateCurriculum(int id, {
    String? code,
    String? name,
    String? major,
    int? totalCredits,
    String? decisionNo,
    String? description,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final data = <String, dynamic>{
      'updated_at': now,
    };
    if (code != null) data['code'] = code.trim().toUpperCase();
    if (name != null) data['name'] = name.trim();
    if (major != null) data['major'] = major.trim();
    if (totalCredits != null) data['total_credits'] = totalCredits;
    if (decisionNo != null) data['decision_no'] = decisionNo.trim();
    if (description != null) data['description'] = description.trim();

    return db.update(
      'curriculums',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Xoá khung chương trình:
  /// - [deleteSubjects] = true: Xoá luôn các môn chỉ thuộc khung này và các liên kết tiên quyết của chúng.
  /// - [deleteSubjects] = false: Chỉ gỡ liên kết khung (giữ lại master subjects trong CSDL).
  Future<void> deleteCurriculum(int id, {bool deleteSubjects = false}) async {
    final db = await database;
    await db.transaction((txn) async {
      if (deleteSubjects) {
        // Tìm các subject_id chỉ thuộc về curriculum này
        final rows = await txn.rawQuery('''
          SELECT cc1.subject_id
          FROM curriculum_courses cc1
          WHERE cc1.curriculum_id = ?
            AND NOT EXISTS (
              SELECT 1 FROM curriculum_courses cc2
              WHERE cc2.subject_id = cc1.subject_id AND cc2.curriculum_id <> ?
            )
        ''', [id, id]);

        final subjectIdsToDelete = rows.map((r) => r['subject_id'] as int).toList();

        // Xóa curriculum (cascade tự động xóa trong curriculum_courses)
        await txn.delete('curriculums', where: 'id = ?', whereArgs: [id]);

        // Xóa các subjects và prerequisites tương ứng
        for (final sId in subjectIdsToDelete) {
          await txn.delete('prerequisites', where: 'subject_id = ? OR prerequisite_id = ?', whereArgs: [sId, sId]);
          await txn.delete('subjects', where: 'id = ?', whereArgs: [sId]);
        }
      } else {
        await txn.delete('curriculums', where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  /// Dọn dẹp các môn học rác PLO do các lần bóc tách cũ trước đây lỡ lưu vào CSDL
  Future<int> cleanInvalidPloSubjects() async {
    final db = await database;
    return await db.transaction((txn) async {
      final invalidRows = await txn.rawQuery('''
        SELECT id FROM subjects
        WHERE UPPER(code) LIKE 'PLO%'
           OR code GLOB '[0-9]*'
           OR UPPER(name) LIKE '%PROGRAM LEARNING OUTCOME%'
      ''');

      final ids = invalidRows.map((r) => r['id'] as int).toList();
      for (final id in ids) {
        await txn.delete('prerequisites', where: 'subject_id = ? OR prerequisite_id = ?', whereArgs: [id, id]);
        await txn.delete('curriculum_courses', where: 'subject_id = ?', whereArgs: [id]);
        await txn.delete('subjects', where: 'id = ?', whereArgs: [id]);
      }
      return ids.length;
    });
  }

  /// Lấy cấu trúc cây thư mục phân cấp theo Khung CTĐT:
  /// Khung CTĐT -> Học kỳ (Term) -> Danh sách môn học
  Future<List<CurriculumGroup>> getCurriculumTreeData() async {
    final db = await database;
    final currs = await getCurriculums();
    final allSubjects = await getSubjects();
    final subjectMap = {for (final s in allSubjects) s.id!: s};

    final treeList = <CurriculumGroup>[];
    final assignedSubjectIds = <int>{};

    for (final curr in currs) {
      final currId = curr['id'] as int;
      final rows = await db.rawQuery('''
        SELECT subject_id, term, credits
        FROM curriculum_courses
        WHERE curriculum_id = ?
        ORDER BY term ASC, subject_id ASC
      ''', [currId]);

      final semMap = <int, List<Subject>>{};
      int subCount = 0;

      for (final r in rows) {
        final sId = r['subject_id'] as int;
        final term = (r['term'] as int?) ?? 1;
        final subject = subjectMap[sId];
        if (subject != null) {
          assignedSubjectIds.add(sId);
          subCount++;
          semMap.putIfAbsent(term, () => []).add(subject.copyWith(semester: term));
        }
      }

      // Sắp xếp các môn trong kỳ theo mã môn
      for (final semCourses in semMap.values) {
        semCourses.sort((a, b) => a.code.compareTo(b.code));
      }

      treeList.add(CurriculumGroup(
        curriculumId: currId,
        code: curr['code'] as String? ?? 'CURR',
        name: curr['name'] as String? ?? '',
        major: curr['major'] as String? ?? '',
        totalCredits: (curr['total_credits'] as int?) ?? 0,
        semesters: semMap,
        totalSubjects: subCount,
      ));
    }

    // Các môn học tự do hoặc chưa phân vào khung nào
    final unassigned = allSubjects.where((s) => !assignedSubjectIds.contains(s.id)).toList();
    if (unassigned.isNotEmpty) {
      final unassignedSemMap = <int, List<Subject>>{};
      for (final s in unassigned) {
        unassignedSemMap.putIfAbsent(s.semester, () => []).add(s);
      }
      for (final semCourses in unassignedSemMap.values) {
        semCourses.sort((a, b) => a.code.compareTo(b.code));
      }
      treeList.add(CurriculumGroup(
        curriculumId: null,
        code: 'OTHER',
        name: 'Môn ngoài khung / Chưa phân loại',
        major: 'Chưa gắn Khung CTĐT',
        semesters: unassignedSemMap,
        totalSubjects: unassigned.length,
      ));
    }

    return treeList;
  }

  /// Lấy danh sách môn học kèm học kỳ của 1 khung chương trình cụ thể
  Future<List<Map<String, dynamic>>> getCoursesOfCurriculum(int curriculumId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT s.*, cc.term, cc.credits AS curr_credits
      FROM subjects s
      INNER JOIN curriculum_courses cc ON cc.subject_id = s.id
      WHERE cc.curriculum_id = ?
      ORDER BY cc.term ASC, s.code ASC
    ''', [curriculumId]);
  }

  /// Xoá toàn bộ dữ liệu (dùng trong Cài đặt khi muốn làm lại demo).
  Future<void> resetAll() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('prerequisites');
      await txn.delete('curriculum_courses');
      await txn.delete('subjects');
      await txn.delete('curriculums');
    });
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Nạp tự động toàn bộ khung chương trình (Curriculum) vào CSDL SQLite:
  /// 1. Bảng `curriculums`: Lưu thông tin ngành/chuyên ngành & mã khung (VD: BIT_SE_K20B).
  /// 2. Bảng `subjects`: Danh mục các môn học (Master Nodes - UPSERT bảo toàn ghi chú Obsidian).
  /// 3. Bảng `curriculum_courses`: Định nghĩa các môn học thuộc về ngành đó ở kỳ (term) nào.
  /// 4. Bảng `prerequisites`: Các liên kết điều kiện tiên quyết (Edges).
  Future<CurriculumImportResult> importCurriculum(Curriculum curriculum) async {
    final db = await database;
    int insertedSubjects = 0;
    int updatedSubjects = 0;
    int insertedEdges = 0;
    int curriculumId = 0;

    final currCode = curriculum.code.trim().isNotEmpty
        ? curriculum.code.trim()
        : 'SE';

    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final codeToId = <String, int>{};

      // 1. Lưu hoặc cập nhật thông tin Khung chương trình (curriculums)
      final currName = curriculum.name.trim().isNotEmpty
          ? curriculum.name.trim()
          : curriculum.major;
      final currMajor = curriculum.major.trim().isNotEmpty
          ? curriculum.major.trim()
          : 'Software Engineering';
      final totalCredits = curriculum.totalCredits > 0
          ? curriculum.totalCredits
          : (curriculum.calculatedTotalCredits > 0
              ? curriculum.calculatedTotalCredits
              : 145);

      final existingCurrs = await txn.query(
        'curriculums',
        where: 'code = ?',
        whereArgs: [currCode],
        limit: 1,
      );

      if (existingCurrs.isNotEmpty) {
        curriculumId = existingCurrs.first['id'] as int;
        await txn.update(
          'curriculums',
          {
            'name': currName,
            'major': currMajor,
            'total_credits': totalCredits,
            'decision_no': curriculum.decisionNo,
            'description': curriculum.description,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [curriculumId],
        );
      } else {
        curriculumId = await txn.insert('curriculums', {
          'code': currCode,
          'name': currName,
          'major': currMajor,
          'total_credits': totalCredits,
          'decision_no': curriculum.decisionNo,
          'description': curriculum.description,
          'created_at': now,
          'updated_at': now,
        });
      }

      // 2. Lấy tất cả môn học hiện có trong DB để tra cứu nhanh
      final existingRows = await txn.query('subjects');
      final existingMap = <String, Map<String, dynamic>>{};
      for (final row in existingRows) {
        final code = (row['code'] as String).trim().toUpperCase();
        existingMap[code] = row;
        codeToId[code] = row['id'] as int;
      }

      // 3. Thu thập danh sách tất cả các Course trong Curriculum
      final allCourses = <Course>[];
      for (final semester in curriculum.semesters) {
        for (final course in semester.courses) {
          if (course.code.trim().isNotEmpty) {
            allCourses.add(course);
          }
        }
      }

      // 4. Upsert từng môn học (Node) vào `subjects` và `curriculum_courses`
      for (final course in allCourses) {
        final code = course.code.trim().toUpperCase();
        final name = course.name.trim().isEmpty ? code : course.name.trim();
        final semester = course.term > 0 ? course.term : 1;
        final credits = course.credits > 0 ? course.credits : 3;

        int subjectId;
        if (existingMap.containsKey(code)) {
          final existing = existingMap[code]!;
          subjectId = existing['id'] as int;
          await txn.update(
            'subjects',
            {
              'name': name,
              'semester': semester,
              'credits': credits,
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [subjectId],
          );
          codeToId[code] = subjectId;
          updatedSubjects++;
        } else {
          subjectId = await txn.insert('subjects', {
            'code': code,
            'name': name,
            'semester': semester,
            'credits': credits,
            'description': '',
            'created_at': now,
            'updated_at': now,
          });
          codeToId[code] = subjectId;
          existingMap[code] = {'id': subjectId, 'code': code};
          insertedSubjects++;
        }

        // Lưu liên kết môn với Khung chương trình ngành (curriculum_courses)
        final existingNode = await txn.query(
          'curriculum_courses',
          where: 'curriculum_id = ? AND subject_id = ?',
          whereArgs: [curriculumId, subjectId],
          limit: 1,
        );

        if (existingNode.isEmpty) {
          await txn.insert('curriculum_courses', {
            'curriculum_id': curriculumId,
            'subject_id': subjectId,
            'term': semester,
            'credits': credits,
          });
        } else {
          await txn.update(
            'curriculum_courses',
            {
              'term': semester,
              'credits': credits,
            },
            where: 'curriculum_id = ? AND subject_id = ?',
            whereArgs: [curriculumId, subjectId],
          );
        }
      }

      // 5. Lấy tất cả các edges hiện có để xây đồ thị và tránh trùng lặp
      final existingEdgeRows = await txn.query('prerequisites');
      final existingEdges = <String>{};
      final parents = <int, List<int>>{};
      for (final row in existingEdgeRows) {
        final sId = row['subject_id'] as int;
        final pId = row['prerequisite_id'] as int;
        existingEdges.add('$sId->$pId');
        parents.putIfAbsent(sId, () => []).add(pId);
      }

      // Kiểm tra chu trình cục bộ trong transaction
      bool checkCycle(int subjectId, int prerequisiteId) {
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

      // 6. Thêm các liên kết tiên quyết (Edges)
      for (final course in allCourses) {
        final subjectCode = course.code.trim().toUpperCase();
        final subjectId = codeToId[subjectCode];
        if (subjectId == null) continue;

        for (final prereqRaw in course.prerequisites) {
          final prereqCode = prereqRaw.trim().toUpperCase();
          final prereqId = codeToId[prereqCode];
          if (prereqId == null || prereqId == subjectId) continue;

          final edgeKey = '$subjectId->$prereqId';
          if (existingEdges.contains(edgeKey)) continue;

          // Bỏ qua nếu tạo chu trình
          if (checkCycle(subjectId, prereqId)) continue;

          await txn.insert('prerequisites', {
            'subject_id': subjectId,
            'prerequisite_id': prereqId,
            'relation_type': Prerequisite.kPrerequisite,
          });
          existingEdges.add(edgeKey);
          parents.putIfAbsent(subjectId, () => []).add(prereqId);
          insertedEdges++;
        }
      }
    });

    return CurriculumImportResult(
      curriculumId: curriculumId,
      curriculumCode: currCode,
      insertedSubjects: insertedSubjects,
      updatedSubjects: updatedSubjects,
      insertedEdges: insertedEdges,
    );
  }

  /// Kích thước file .db theo byte (hiển thị trong Cài đặt).
  Future<int> databaseSizeInBytes() async {
    final path = _dbPath;
    if (path == null) return 0;
    final file = File(path);
    return await file.exists() ? file.length() : 0;
  }
}

/// Kết quả sau khi nạp Curriculum vào CSDL SQLite.
class CurriculumImportResult {
  final int curriculumId;
  final String curriculumCode;
  final int insertedSubjects;
  final int updatedSubjects;
  final int insertedEdges;

  const CurriculumImportResult({
    required this.curriculumId,
    required this.curriculumCode,
    required this.insertedSubjects,
    required this.updatedSubjects,
    required this.insertedEdges,
  });

  int get totalSubjects => insertedSubjects + updatedSubjects;

  @override
  String toString() =>
      'CurriculumImportResult(id: $curriculumId, code: $curriculumCode, inserted: $insertedSubjects, updated: $updatedSubjects, edges: $insertedEdges)';
}

/// Lỗi nghiệp vụ từ tầng DB (trùng khoá, chu trình, ...) để UI hiển thị tử tế.
class DbConflictException implements Exception {
  final String message;
  DbConflictException(this.message);
  @override
  String toString() => message;
}
