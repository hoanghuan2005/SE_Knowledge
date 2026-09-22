import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/curriculum.dart';
import '../models/graph_data.dart';
import '../models/prerequisite.dart';
import '../models/subject.dart';
import 'fap_markdown_parser.dart';
import 'settings_service.dart';

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
  static const int dbVersion = 5;

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
        updated_at  TEXT    NOT NULL,
        -- 1 = kỳ/tín chỉ là giá trị tạm gán khi tạo môn từ một trang Syllabus
        -- lẻ (trang đó không có cột Semester). Trang Curriculum Details đầu
        -- tiên xác nhận kỳ thật của môn được phép ghi đè khi cờ này bật.
        semester_is_placeholder INTEGER NOT NULL DEFAULT 0
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

    await _createFapTables(db);

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

    if (oldVersion < 3) {
      await _createFapTables(db);
    }

    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE subjects ADD COLUMN semester_is_placeholder INTEGER NOT NULL DEFAULT 0',
      );
    }

    if (oldVersion < 5) {
      // Vá ngược cho dữ liệu đã nhập TRƯỚC khi có cột `semester_is_placeholder`
      // (v4): những môn có bản ghi trong `syllabi` (nghĩa là từng được tạo chỉ
      // từ một trang Syllabus lẻ, không có cột kỳ) nhưng chưa từng gắn với
      // `curriculum_subjects` nào (chưa có Curriculum Details nào xác nhận kỳ
      // thật) thì coi kỳ hiện tại là giá trị tạm, cho phép ghi đè sau này.
      await db.execute('''
        UPDATE subjects
        SET semester_is_placeholder = 1
        WHERE id IN (SELECT subject_id FROM syllabi)
          AND id NOT IN (SELECT subject_id FROM curriculum_subjects)
      ''');
    }
  }

  /// 10 bảng phục vụ nhập dữ liệu từ FAP (PHẦN 2 + PHẦN 3 của `schema_full.sql`).
  ///
  /// Migration thuần cộng thêm: không DROP, không đổi cột nào của các bảng cũ,
  /// và KHÔNG gọi `_seed` — file .db trên máy người dùng đang có dữ liệu thật.
  ///
  /// Thứ tự tạo bảng là bắt buộc vì có khoá ngoại phụ thuộc nhau: `curricula`
  /// trước `program_learning_outcomes`/`curriculum_subjects`; `syllabi` trước
  /// `materials`/`learning_outcomes`/`sessions`/`assessments`;
  /// `learning_outcomes` trước hai bảng nối `*_learning_outcomes`.
  ///
  /// Phân biệt với hai bảng cũ cùng chủ đề: `curriculums` +
  /// `curriculum_courses` là khung CTĐT của luồng scraper/demo cũ, còn
  /// `curricula` + `curriculum_subjects` dưới đây là dữ liệu nhập trực tiếp từ
  /// FAP. Hai bộ tồn tại song song, không ghi đè nhau.
  Future<void> _createFapTables(Database db) async {
    // --- PHẦN 2: Chương trình đào tạo (trang "Curriculum Details") ---
    await db.execute('''
      CREATE TABLE IF NOT EXISTS curricula (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        fap_curriculum_id INTEGER UNIQUE,
        code              TEXT    NOT NULL,
        name_vn           TEXT,
        name_en           TEXT,
        description       TEXT,
        decision_no       TEXT,
        decision_date     TEXT,
        total_credits     INTEGER,
        source_url        TEXT,
        synced_at         TEXT    NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_curricula_code ON curricula (code)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS program_learning_outcomes (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        curriculum_id INTEGER NOT NULL,
        code          TEXT    NOT NULL,
        description   TEXT    NOT NULL,
        UNIQUE (curriculum_id, code),
        FOREIGN KEY (curriculum_id) REFERENCES curricula (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_plo_curriculum ON program_learning_outcomes (curriculum_id)',
    );

    // Bảng nối nhiều-nhiều BẮT BUỘC: kỳ học / tín chỉ / tiên quyết là thuộc
    // tính THEO TỪNG CHƯƠNG TRÌNH, không phải thuộc tính cố định của môn.
    // Xem mục 4 trong FAP_Syllabus_Schema.md.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS curriculum_subjects (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        curriculum_id         INTEGER NOT NULL,
        subject_id            INTEGER NOT NULL,
        semester              INTEGER,
        credits               INTEGER,
        raw_prerequisite_text TEXT,
        UNIQUE (curriculum_id, subject_id),
        FOREIGN KEY (curriculum_id) REFERENCES curricula (id) ON DELETE CASCADE,
        FOREIGN KEY (subject_id)    REFERENCES subjects (id)   ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cursub_curriculum ON curriculum_subjects (curriculum_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cursub_subject ON curriculum_subjects (subject_id)',
    );

    // --- PHẦN 3: Syllabus chi tiết (trang "Syllabus Details") ---
    await db.execute('''
      CREATE TABLE IF NOT EXISTS syllabi (
        id                       INTEGER PRIMARY KEY AUTOINCREMENT,
        subject_id               INTEGER NOT NULL,
        fap_syllabus_id          INTEGER UNIQUE,
        name_en                  TEXT,
        name_native              TEXT,
        degree_level             TEXT,
        learning_teaching_method TEXT,
        time_allocation          TEXT,
        description              TEXT,
        student_tasks            TEXT,
        tools                    TEXT,
        scoring_scale            INTEGER,
        decision_no              TEXT,
        decision_date            TEXT,
        is_approved              INTEGER NOT NULL DEFAULT 0,
        is_scored                INTEGER NOT NULL DEFAULT 1,
        min_avg_mark_to_pass     REAL,
        is_active                INTEGER NOT NULL DEFAULT 1,
        approved_date            TEXT,
        raw_prerequisite_text    TEXT,
        source_url               TEXT,
        synced_at                TEXT    NOT NULL,
        FOREIGN KEY (subject_id) REFERENCES subjects (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_syllabi_subject ON syllabi (subject_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS materials (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        syllabus_id    INTEGER NOT NULL,
        seq_no         INTEGER,
        description    TEXT    NOT NULL,
        author         TEXT,
        publisher      TEXT,
        published_date TEXT,
        edition        TEXT,
        isbn           TEXT,
        is_main        INTEGER NOT NULL DEFAULT 0,
        is_hard_copy   INTEGER NOT NULL DEFAULT 0,
        is_online      INTEGER NOT NULL DEFAULT 0,
        note           TEXT,
        FOREIGN KEY (syllabus_id) REFERENCES syllabi (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_materials_syllabus ON materials (syllabus_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS learning_outcomes (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        syllabus_id INTEGER NOT NULL,
        code        TEXT    NOT NULL,
        detail      TEXT    NOT NULL,
        UNIQUE (syllabus_id, code),
        FOREIGN KEY (syllabus_id) REFERENCES syllabi (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_lo_syllabus ON learning_outcomes (syllabus_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        syllabus_id       INTEGER NOT NULL,
        session_no        INTEGER NOT NULL,
        topic             TEXT    NOT NULL,
        teaching_type     TEXT,
        itu               TEXT,
        student_materials TEXT,
        download_url      TEXT,
        student_tasks     TEXT,
        urls              TEXT,
        UNIQUE (syllabus_id, session_no),
        FOREIGN KEY (syllabus_id) REFERENCES syllabi (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sessions_syllabus ON sessions (syllabus_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS session_learning_outcomes (
        session_id INTEGER NOT NULL,
        clo_id     INTEGER NOT NULL,
        PRIMARY KEY (session_id, clo_id),
        FOREIGN KEY (session_id) REFERENCES sessions (id)          ON DELETE CASCADE,
        FOREIGN KEY (clo_id)     REFERENCES learning_outcomes (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS assessments (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        syllabus_id         INTEGER NOT NULL,
        seq_no              INTEGER,
        category            TEXT    NOT NULL,
        type                TEXT,
        part                INTEGER,
        weight_percent      REAL    NOT NULL,
        completion_criteria TEXT,
        duration            TEXT,
        question_type       TEXT,
        no_question         INTEGER,
        knowledge_skill     TEXT,
        grading_guide       TEXT,
        note                TEXT,
        FOREIGN KEY (syllabus_id) REFERENCES syllabi (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_assessments_syllabus ON assessments (syllabus_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS assessment_learning_outcomes (
        assessment_id INTEGER NOT NULL,
        clo_id        INTEGER NOT NULL,
        PRIMARY KEY (assessment_id, clo_id),
        FOREIGN KEY (assessment_id) REFERENCES assessments (id)       ON DELETE CASCADE,
        FOREIGN KEY (clo_id)        REFERENCES learning_outcomes (id) ON DELETE CASCADE
      )
    ''');
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
  Future<bool> _wouldCreateCycle(
    int subjectId,
    int prerequisiteId, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? await database;
    final rows = await executor.query('prerequisites');
    final edges = rows.map(Prerequisite.fromMap).toList();
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
  Future<List<Subject>?> suggestLearningOrder({GraphData? customGraph}) async {
    final graph = customGraph ?? await loadGraph();
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

  /// Cập nhật thông tin khung chương trình.
  ///
  /// Đổi mã thì phải đổi CẢ hàng song song bên `curricula` (bộ bảng FAP).
  /// Hai bảng được `getCurriculumTreeData` soi chiếu với nhau BẰNG MÃ: để lệch
  /// mã thì lần dựng cây kế tiếp tưởng hàng `curricula` chưa có bản sao, bèn
  /// tạo lại một khung trùng nội dung — người dùng đổi tên một tệp lại thấy
  /// mọc ra hai.
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
    final newCode = code?.trim().toUpperCase();
    if (newCode != null) data['code'] = newCode;
    if (name != null) data['name'] = name.trim();
    if (major != null) data['major'] = major.trim();
    if (totalCredits != null) data['total_credits'] = totalCredits;
    if (decisionNo != null) data['decision_no'] = decisionNo.trim();
    if (description != null) data['description'] = description.trim();

    return db.transaction((txn) async {
      final current = await txn.query(
        'curriculums',
        columns: ['code'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (current.isEmpty) return 0;
      final oldCode = (current.first['code'] as String).trim().toUpperCase();

      if (newCode != null && newCode != oldCode) {
        if (newCode.isEmpty) {
          throw DbConflictException('Mã tệp môn học không được để trống.');
        }
        final clash = await txn.query(
          'curriculums',
          columns: ['id'],
          where: 'UPPER(code) = ? AND id <> ?',
          whereArgs: [newCode, id],
          limit: 1,
        );
        if (clash.isNotEmpty) {
          throw DbConflictException('Đã có tệp môn học mang mã "$newCode".');
        }
        await txn.update(
          'curricula',
          {'code': newCode},
          where: 'UPPER(code) = ?',
          whereArgs: [oldCode],
        );
      }

      return txn.update('curriculums', data, where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Xoá khung chương trình:
  /// - [deleteSubjects] = true: Xoá luôn các môn chỉ thuộc khung này và các liên kết tiên quyết của chúng.
  /// - [deleteSubjects] = false: Chỉ gỡ liên kết khung (giữ lại master subjects trong CSDL).
  Future<void> deleteCurriculum(int id, {bool deleteSubjects = false}) async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. Tìm thông tin curriculum để biết mã code và legacy ID
      var currRows = await txn.query(
        'curriculums',
        columns: ['id', 'code'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      String? currCode;
      int legacyId = id;

      if (currRows.isNotEmpty) {
        currCode = (currRows.first['code'] as String).trim().toUpperCase();
      } else {
        // Có thể id truyền vào là id của bảng FAP curricula
        final fapRows = await txn.query(
          'curricula',
          columns: ['id', 'code'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (fapRows.isNotEmpty) {
          currCode = (fapRows.first['code'] as String).trim().toUpperCase();
          final legRows = await txn.query(
            'curriculums',
            columns: ['id'],
            where: 'UPPER(code) = ?',
            whereArgs: [currCode],
            limit: 1,
          );
          if (legRows.isNotEmpty) {
            legacyId = legRows.first['id'] as int;
          }
        }
      }

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
        ''', [legacyId, legacyId]);

        final subjectIdsToDelete = rows.map((r) => r['subject_id'] as int).toList();

        // Xóa curriculum courses và curriculum
        await txn.delete('curriculum_courses', where: 'curriculum_id = ?', whereArgs: [legacyId]);
        await txn.delete('curriculums', where: 'id = ?', whereArgs: [legacyId]);

        // Xoá bên bảng FAP curricula nếu có
        if (currCode != null && currCode.isNotEmpty) {
          final fapCurrs = await txn.query(
            'curricula',
            columns: ['id'],
            where: 'UPPER(code) = ?',
            whereArgs: [currCode],
          );
          for (final fc in fapCurrs) {
            final fcId = fc['id'] as int;
            await txn.delete('curriculum_subjects', where: 'curriculum_id = ?', whereArgs: [fcId]);
            await txn.delete('program_learning_outcomes', where: 'curriculum_id = ?', whereArgs: [fcId]);
            await txn.delete('curricula', where: 'id = ?', whereArgs: [fcId]);
          }
        }

        // Xóa các subjects và prerequisites tương ứng
        for (final sId in subjectIdsToDelete) {
          await txn.delete('prerequisites', where: 'subject_id = ? OR prerequisite_id = ?', whereArgs: [sId, sId]);
          await txn.delete('curriculum_courses', where: 'subject_id = ?', whereArgs: [sId]);
          await txn.delete('curriculum_subjects', where: 'subject_id = ?', whereArgs: [sId]);
          await txn.delete('subjects', where: 'id = ?', whereArgs: [sId]);
        }
      } else {
        await txn.delete('curriculum_courses', where: 'curriculum_id = ?', whereArgs: [legacyId]);
        await txn.delete('curriculums', where: 'id = ?', whereArgs: [legacyId]);

        if (currCode != null && currCode.isNotEmpty) {
          final fapCurrs = await txn.query(
            'curricula',
            columns: ['id'],
            where: 'UPPER(code) = ?',
            whereArgs: [currCode],
          );
          for (final fc in fapCurrs) {
            final fcId = fc['id'] as int;
            await txn.delete('curriculum_subjects', where: 'curriculum_id = ?', whereArgs: [fcId]);
            await txn.delete('program_learning_outcomes', where: 'curriculum_id = ?', whereArgs: [fcId]);
            await txn.delete('curricula', where: 'id = ?', whereArgs: [fcId]);
          }
        }
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

    // Tự động đồng bộ các bản ghi từ bảng FAP curricula sang curriculums nếu chưa có
    final fapCurrs = await db.query('curricula');
    for (final fc in fapCurrs) {
      final code = (fc['code'] as String? ?? '').trim().toUpperCase();
      if (code.isEmpty) continue;
      final existing = await db.query('curriculums', where: 'UPPER(code) = ?', whereArgs: [code], limit: 1);
      if (existing.isEmpty) {
        final now = DateTime.now().toIso8601String();
        final name = (fc['name_en'] as String?) ?? (fc['name_vn'] as String?) ?? code;
        final newId = await db.insert('curriculums', {
          'code': code,
          'name': name,
          'major': name,
          'total_credits': (fc['total_credits'] as int?) ?? 145,
          'decision_no': (fc['decision_no'] as String?) ?? '',
          'description': (fc['description'] as String?) ?? '',
          'created_at': now,
          'updated_at': now,
        });
        final fcId = fc['id'] as int;
        final curSubs = await db.query('curriculum_subjects', where: 'curriculum_id = ?', whereArgs: [fcId]);
        for (final cs in curSubs) {
          await db.insert('curriculum_courses', {
            'curriculum_id': newId,
            'subject_id': cs['subject_id'],
            'term': cs['semester'] ?? 1,
            'credits': cs['credits'] ?? 3,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    }

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

  // ------------------------------------------------------------------
  // GÁN MÔN VÀO "TỆP MÔN HỌC" (KHUNG CTĐT)
  //
  // Một "tệp môn học" trên thanh bên chính là một hàng của bảng `curriculums`.
  // Quan hệ môn <-> tệp nằm ở `curriculum_courses`, nên cùng một môn dùng
  // chung (PRF192, MAD101...) có thể thuộc nhiều tệp mà không bị nhân bản
  // trong bảng `subjects`.
  // ------------------------------------------------------------------

  /// Lấy một khung theo id, `null` nếu không còn.
  Future<Map<String, dynamic>?> getCurriculumById(int id) async {
    final db = await database;
    final rows = await db.query(
      'curriculums',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Tìm khung theo mã, tạo mới nếu chưa có. Trả về id trong `curriculums`.
  ///
  /// So khớp không phân biệt hoa thường vì mã khung nhập từ FAP
  /// (`bit_se_k19b`) và mã người dùng gõ tay (`BIT_SE_K19B`) phải là một.
  Future<int> ensureCurriculumByCode({
    required String code,
    String? name,
    String? major,
    int? totalCredits,
    String? description,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await database;
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) {
      throw DbConflictException('Mã tệp môn học không được để trống.');
    }

    final existing = await db.query(
      'curriculums',
      columns: ['id'],
      where: 'UPPER(code) = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;

    final now = DateTime.now().toIso8601String();
    final label = (name ?? '').trim().isNotEmpty ? name!.trim() : normalized;
    return db.insert('curriculums', {
      'code': normalized,
      'name': label,
      'major': (major ?? '').trim().isNotEmpty ? major!.trim() : label,
      'total_credits': totalCredits ?? 0,
      'decision_no': '',
      'description': (description ?? '').trim(),
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Gắn một loạt môn vào một tệp môn học. Trả về số dòng thêm mới.
  ///
  /// [entries] là các bộ `(subjectId, term, credits)`. Môn đã nằm trong tệp
  /// thì MẶC ĐỊNH giữ nguyên kỳ và tín chỉ đang có: kỳ trong một tệp là thứ
  /// người dùng tự sửa bằng "Đổi kỳ…" và file `.md` không có chỗ nào ghi được
  /// nó (front matter chỉ có một khoá `semester` dùng chung cho mọi tệp), nên
  /// nạp lại Vault mà ghi đè thì mọi lần sửa kỳ đều bị nuốt mất.
  ///
  /// [overwriteExisting] = true khi nguồn dữ liệu thật sự có thẩm quyền về kỳ
  /// (trang Curriculum Details của FAP chẳng hạn).
  Future<int> assignSubjectsToCurriculum({
    required int curriculumId,
    required List<CurriculumCourseEntry> entries,
    bool overwriteExisting = false,
  }) async {
    if (entries.isEmpty) return 0;
    final db = await database;
    var inserted = 0;

    await db.transaction((txn) async {
      for (final e in entries) {
        final existing = await txn.query(
          'curriculum_courses',
          columns: ['id'],
          where: 'curriculum_id = ? AND subject_id = ?',
          whereArgs: [curriculumId, e.subjectId],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert('curriculum_courses', {
            'curriculum_id': curriculumId,
            'subject_id': e.subjectId,
            'term': e.term,
            'credits': e.credits,
          });
          inserted++;
        } else if (overwriteExisting) {
          await txn.update(
            'curriculum_courses',
            {'term': e.term, 'credits': e.credits},
            where: 'id = ?',
            whereArgs: [existing.first['id'] as int],
          );
        }
      }
    });
    return inserted;
  }

  /// Gỡ môn khỏi một tệp môn học. KHÔNG xoá môn khỏi bảng `subjects` —
  /// môn rơi về nhóm "Môn ngoài khung" và mọi ghi chú vẫn còn nguyên.
  Future<int> removeSubjectsFromCurriculum({
    required int curriculumId,
    required List<int> subjectIds,
  }) async {
    if (subjectIds.isEmpty) return 0;
    final db = await database;
    final placeholders = List.filled(subjectIds.length, '?').join(', ');
    return db.delete(
      'curriculum_courses',
      where: 'curriculum_id = ? AND subject_id IN ($placeholders)',
      whereArgs: [curriculumId, ...subjectIds],
    );
  }

  /// Chuyển môn từ tệp này sang tệp khác, giữ nguyên kỳ và tín chỉ.
  ///
  /// [fromCurriculumId] null nghĩa là môn đang ở nhóm "ngoài khung" — lúc đó
  /// chỉ thêm vào tệp đích chứ không gỡ ở đâu cả.
  Future<void> moveSubjectsToCurriculum({
    int? fromCurriculumId,
    required int toCurriculumId,
    required List<int> subjectIds,
    int? forcedTerm,
  }) async {
    if (subjectIds.isEmpty || fromCurriculumId == toCurriculumId) return;
    final db = await database;

    await db.transaction((txn) async {
      for (final subjectId in subjectIds) {
        int term = forcedTerm ?? 1;
        int credits = 3;

        if (forcedTerm == null) {
          if (fromCurriculumId != null) {
            final src = await txn.query(
              'curriculum_courses',
              columns: ['term', 'credits'],
              where: 'curriculum_id = ? AND subject_id = ?',
              whereArgs: [fromCurriculumId, subjectId],
              limit: 1,
            );
            if (src.isNotEmpty) {
              term = (src.first['term'] as int?) ?? 1;
              credits = (src.first['credits'] as int?) ?? 3;
            }
          } else {
            final subj = await txn.query(
              'subjects',
              columns: ['semester', 'credits'],
              where: 'id = ?',
              whereArgs: [subjectId],
              limit: 1,
            );
            if (subj.isNotEmpty) {
              term = (subj.first['semester'] as int?) ?? 1;
              credits = (subj.first['credits'] as int?) ?? 3;
            }
          }
        }

        if (fromCurriculumId != null) {
          await txn.delete(
            'curriculum_courses',
            where: 'curriculum_id = ? AND subject_id = ?',
            whereArgs: [fromCurriculumId, subjectId],
          );
        }

        final dup = await txn.query(
          'curriculum_courses',
          columns: ['id'],
          where: 'curriculum_id = ? AND subject_id = ?',
          whereArgs: [toCurriculumId, subjectId],
          limit: 1,
        );
        final values = {
          'curriculum_id': toCurriculumId,
          'subject_id': subjectId,
          'term': term,
          'credits': credits,
        };
        if (dup.isEmpty) {
          await txn.insert('curriculum_courses', values);
        } else {
          await txn.update(
            'curriculum_courses',
            values,
            where: 'id = ?',
            whereArgs: [dup.first['id'] as int],
          );
        }
      }
    });
  }

  /// Đổi kỳ của một loạt môn.
  ///
  /// [curriculumId] null = môn ngoài khung, lúc đó kỳ nằm ở `subjects.semester`.
  /// Có khung thì ghi vào `curriculum_courses.term` để không đụng tới kỳ mà
  /// các tệp môn học khác đang khai báo cho cùng một môn.
  Future<void> setTermOfSubjects({
    int? curriculumId,
    required List<int> subjectIds,
    required int term,
  }) async {
    if (subjectIds.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(subjectIds.length, '?').join(', ');

    if (curriculumId == null) {
      await db.rawUpdate(
        'UPDATE subjects SET semester = ?, semester_is_placeholder = 0, '
        'updated_at = ? WHERE id IN ($placeholders)',
        [term, DateTime.now().toIso8601String(), ...subjectIds],
      );
      return;
    }

    await db.update(
      'curriculum_courses',
      {'term': term},
      where: 'curriculum_id = ? AND subject_id IN ($placeholders)',
      whereArgs: [curriculumId, ...subjectIds],
    );
  }

  /// `{subject_id: [mã tệp môn học, ...]}` — dùng khi ghi front matter
  /// `curriculum:` ra file `.md` để lần nạp sau nhận lại đúng tệp.
  Future<Map<int, List<String>>> curriculumCodesBySubjectId() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT cc.subject_id AS sid, c.code AS code
      FROM curriculum_courses cc
      INNER JOIN curriculums c ON c.id = cc.curriculum_id
      ORDER BY c.code ASC
    ''');
    final out = <int, List<String>>{};
    for (final r in rows) {
      final sid = r['sid'] as int;
      final code = (r['code'] as String?)?.trim() ?? '';
      if (code.isEmpty) continue;
      out.putIfAbsent(sid, () => []).add(code);
    }
    return out;
  }

  /// Xoá toàn bộ dữ liệu (dùng trong Cài đặt khi muốn làm lại demo).
  Future<void> resetAll() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('prerequisites');
      await txn.delete('curriculum_courses');
      await txn.delete('subjects');
      await txn.delete('curriculums');
      await txn.delete('curricula');
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

  // ------------------------------------------------------------------
  // NHẬP DỮ LIỆU TỪ FAP (trang "Curriculum Details")
  // ------------------------------------------------------------------
  //
  // Mọi phương thức dưới đây nhận [txn] tuỳ chọn để [importFapCurriculum] gói
  // được cả lượt nhập vào MỘT transaction: hỏng giữa chừng thì rollback sạch,
  // không để lại chương trình đã tạo mà thiếu môn.

  /// Upsert một chương trình đào tạo theo `fap_curriculum_id` (UNIQUE).
  ///
  /// Trang FAP không có `curid` thì lùi về đối chiếu theo `code`, để vẫn nhận
  /// ra chương trình cũ thay vì tạo bản trùng.
  Future<int> upsertCurriculum({
    required int? fapCurriculumId,
    required String code,
    String? nameVn,
    String? nameEn,
    String? description,
    String? decisionNo,
    String? decisionDate,
    int? totalCredits,
    String? sourceUrl,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await database;
    final values = <String, Object?>{
      'fap_curriculum_id': fapCurriculumId,
      'code': code,
      'name_vn': nameVn,
      'name_en': nameEn,
      'description': description,
      'decision_no': decisionNo,
      'decision_date': decisionDate,
      'total_credits': totalCredits,
      'source_url': sourceUrl,
      'synced_at': DateTime.now().toIso8601String(),
    };

    final existing = fapCurriculumId != null
        ? await db.query(
            'curricula',
            columns: ['id'],
            where: 'fap_curriculum_id = ?',
            whereArgs: [fapCurriculumId],
            limit: 1,
          )
        : await db.query(
            'curricula',
            columns: ['id'],
            where: 'code = ?',
            whereArgs: [code],
            limit: 1,
          );

    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      await db.update('curricula', values, where: 'id = ?', whereArgs: [id]);
      return id;
    }
    return db.insert('curricula', values);
  }

  /// Thay toàn bộ PLO của một chương trình.
  ///
  /// Xoá rồi chèn lại là đủ và luôn đúng vì PLO thuần tuý đến từ FAP, người
  /// dùng không tự thêm dòng nào nên không có gì để mất.
  Future<void> replacePlos(
    int curriculumId,
    List<FapPloRow> plos, {
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await database;
    await db.delete(
      'program_learning_outcomes',
      where: 'curriculum_id = ?',
      whereArgs: [curriculumId],
    );
    for (final plo in plos) {
      await db.insert('program_learning_outcomes', {
        'curriculum_id': curriculumId,
        'code': plo.code,
        'description': plo.description,
      });
    }
  }

  /// Upsert một môn vào bảng `subjects` theo luồng FAP.
  ///
  /// Môn CHƯA tồn tại: chèn đầy đủ, lấy luôn kỳ/tín chỉ của chương trình này
  /// làm giá trị khởi tạo.
  ///
  /// Môn ĐÃ tồn tại: CHỈ cập nhật `name` (FAP là nguồn chuẩn cho tên) và
  /// `updated_at`. Tuyệt đối không đụng tới `semester`, `credits`,
  /// `description`, `note_path` — đó là thuộc tính THEO TỪNG CHƯƠNG TRÌNH và
  /// chỗ của chúng là `curriculum_subjects`. Ghi đè ở đây thì nhập chương
  /// trình thứ hai sẽ phá dữ liệu của chương trình thứ nhất trên các môn dùng
  /// chung (PRF192, MAD101, DBI202...). Xem mục 4 trong FAP_Syllabus_Schema.md.
  ///
  /// Vì vậy KHÔNG dùng [upsertSubjectByCode] cho luồng này: hàm đó ghi đè
  /// semester/credits — đúng cho Obsidian Vault, sai cho FAP.
  Future<int> upsertSubjectFromFap({
    required String code,
    required String name,
    required int semester,
    required int credits,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await database;
    final normalized = code.trim().toUpperCase();
    final now = DateTime.now().toIso8601String();

    final existing = await db.query(
      'subjects',
      columns: ['id', 'semester_is_placeholder'],
      where: 'code = ?',
      whereArgs: [normalized],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      final values = <String, Object?>{'name': name, 'updated_at': now};

      // Môn này có thể chỉ tồn tại vì được tạo tạm từ một trang Syllabus lẻ
      // (không có cột Semester nên `importFapSyllabus` phải gán tạm kỳ 1 và
      // đánh dấu `semester_is_placeholder = 1`). Trang Curriculum Details đầu
      // tiên xác nhận kỳ thật của môn thì được phép ghi đè giá trị tạm đó;
      // môn do người dùng tự thêm hoặc đã có kỳ thật từ trước thì không đụng.
      final placeholder = existing.first['semester_is_placeholder'] == 1;
      if (placeholder) {
        values['semester'] = semester > 0 ? semester : 1;
        values['credits'] = credits;
        values['semester_is_placeholder'] = 0;
      }

      await db.update(
        'subjects',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }

    return db.insert('subjects', {
      'code': normalized,
      'name': name,
      // FAP ghi kỳ 0 cho các môn chuẩn bị (OTP101, PEN, PHE...). Đồ thị và
      // thanh bên nhóm môn theo kỳ nên quy về kỳ 1, còn con số 0 nguyên bản
      // vẫn nằm ở `curriculum_subjects.semester`.
      'semester': semester > 0 ? semester : 1,
      // Ngược lại, 0 tín chỉ là sự thật về môn nên giữ nguyên.
      'credits': credits,
      'description': '',
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Upsert một dòng của bảng nối, theo UNIQUE `(curriculum_id, subject_id)`.
  Future<void> upsertCurriculumSubject({
    required int curriculumId,
    required int subjectId,
    int? semester,
    int? credits,
    String? rawPrerequisiteText,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await database;
    final values = <String, Object?>{
      'curriculum_id': curriculumId,
      'subject_id': subjectId,
      'semester': semester,
      'credits': credits,
      'raw_prerequisite_text': rawPrerequisiteText,
    };

    final existing = await db.query(
      'curriculum_subjects',
      columns: ['id'],
      where: 'curriculum_id = ? AND subject_id = ?',
      whereArgs: [curriculumId, subjectId],
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert('curriculum_subjects', values);
      return;
    }
    await db.update(
      'curriculum_subjects',
      values,
      where: 'id = ?',
      whereArgs: [existing.first['id'] as int],
    );
  }

  /// Ghi trọn một trang "Curriculum Details" đã bóc tách xuống CSDL.
  ///
  /// Tên khác [importCurriculum] vì Dart không nạp chồng được: hàm kia phục vụ
  /// luồng scraper cũ và ghi vào `curriculums`/`curriculum_courses`, hàm này
  /// ghi vào bộ bảng FAP `curricula`/`curriculum_subjects`.
  ///
  /// KHÔNG tạo cạnh tiên quyết ở bước này. `raw_prerequisite_text` chỉ được
  /// lưu nguyên văn; việc bóc mã môn ra thành cạnh `prerequisites` là Giai
  /// đoạn 5.4.
  Future<FapImportResult> importFapCurriculum(FapCurriculumImport data) async {
    final db = await database;
    var curriculumId = 0;
    var insertedSubjects = 0;
    var updatedSubjects = 0;
    var links = 0;

    await db.transaction((txn) async {
      curriculumId = await upsertCurriculum(
        fapCurriculumId: data.fapCurriculumId,
        code: data.code,
        nameEn: data.name,
        decisionNo: data.decisionNo,
        totalCredits: data.totalCredits,
        sourceUrl: data.sourceUrl,
        txn: txn,
      );

      await replacePlos(curriculumId, data.plos, txn: txn);

      // Chụp trước danh sách mã môn đang có để đếm mới/cũ bằng một truy vấn,
      // thay vì hỏi lại CSDL cho từng môn.
      final existingRows = await txn.query('subjects', columns: ['code']);
      final existingCodes = <String>{
        for (final row in existingRows)
          (row['code'] as String).trim().toUpperCase(),
      };

      // Đồng bộ sang bảng curriculums/curriculum_courses để Graph View & Demo View nhận diện được khung
      final currCode = data.code.trim().toUpperCase();
      final existingLegacy = await txn.query(
        'curriculums',
        where: 'code = ?',
        whereArgs: [currCode],
      );
      int legacyCurrId;
      final now = DateTime.now().toIso8601String();
      if (existingLegacy.isNotEmpty) {
        legacyCurrId = existingLegacy.first['id'] as int;
        await txn.update(
          'curriculums',
          {
            'name': data.name.isNotEmpty ? data.name : currCode,
            'total_credits': data.totalCredits,
            'decision_no': data.decisionNo,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [legacyCurrId],
        );
      } else {
        legacyCurrId = await txn.insert('curriculums', {
          'code': currCode,
          'name': data.name.isNotEmpty ? data.name : currCode,
          'major': data.name.isNotEmpty ? data.name : currCode,
          'total_credits': data.totalCredits,
          'decision_no': data.decisionNo,
          'description': 'Được nhập tự động từ FAP/FLM Markdown',
          'created_at': now,
          'updated_at': now,
        });
      }

      final subjectIdMap = <String, int>{};
      for (final row in data.subjects) {
        final code = row.code.trim().toUpperCase();
        if (code.isEmpty) continue;

        final isNew = !existingCodes.contains(code);
        final subjectId = await upsertSubjectFromFap(
          code: code,
          name: row.fullName,
          semester: row.semester,
          credits: row.credits,
          txn: txn,
        );
        subjectIdMap[code] = subjectId;

        if (isNew) {
          existingCodes.add(code);
          insertedSubjects++;
        } else {
          updatedSubjects++;
        }

        await upsertCurriculumSubject(
          curriculumId: curriculumId,
          subjectId: subjectId,
          semester: row.semester,
          credits: row.credits,
          rawPrerequisiteText:
              row.rawPrerequisite.isEmpty ? null : row.rawPrerequisite,
          txn: txn,
        );
        links++;

        await txn.insert(
          'curriculum_courses',
          {
            'curriculum_id': legacyCurrId,
            'subject_id': subjectId,
            'term': row.semester,
            'credits': row.credits,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // Xây dựng cạnh tiên quyết (prerequisite edges) từ rawPrerequisite
      for (final row in data.subjects) {
        if (row.rawPrerequisite.trim().isEmpty) continue;
        final sId = subjectIdMap[row.code.trim().toUpperCase()];
        if (sId == null) continue;

        final prereqCodes = FapMarkdownParser.extractPrerequisiteCodes(row.rawPrerequisite);
        for (final pCode in prereqCodes) {
          final pRows = await txn.query('subjects', columns: ['id'], where: 'code = ?', whereArgs: [pCode], limit: 1);
          if (pRows.isNotEmpty) {
            final pId = pRows.first['id'] as int;
            if (pId != sId) {
              final cycle = await _wouldCreateCycle(sId, pId, txn: txn);
              if (!cycle) {
                await txn.insert(
                  'prerequisites',
                  {
                    'subject_id': sId,
                    'prerequisite_id': pId,
                    'relation_type': 'PREREQUISITE',
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                );
              }
            }
          }
        }
      }
    });

    return FapImportResult(
      curriculumId: curriculumId,
      curriculumCode: data.code,
      insertedSubjects: insertedSubjects,
      updatedSubjects: updatedSubjects,
      plos: data.plos.length,
      curriculumSubjects: links,
    );
  }

  /// Ghi một trang Syllabus Details đã bóc tách xuống CSDL.
  Future<FapSyllabusImportResult> importFapSyllabus(FapSyllabusImport data) async {
    final db = await database;
    var syllabusId = 0;

    await db.transaction((txn) async {
      final code = data.subjectCode.trim().toUpperCase();
      if (code.isEmpty) {
        throw DbConflictException('Không tìm thấy mã môn học trong Syllabus.');
      }

      // 1. Đảm bảo môn học tồn tại trong bảng `subjects`
      final existingSub = await txn.query(
        'subjects',
        columns: ['id', 'name'],
        where: 'code = ?',
        whereArgs: [code],
        limit: 1,
      );

      int subjectId;
      final now = DateTime.now().toIso8601String();
      if (existingSub.isNotEmpty) {
        subjectId = existingSub.first['id'] as int;
        final currentName = existingSub.first['name'] as String? ?? '';
        if (currentName.isEmpty || currentName == code) {
          await txn.update(
            'subjects',
            {'name': data.fullName, 'updated_at': now},
            where: 'id = ?',
            whereArgs: [subjectId],
          );
        }
      } else {
        subjectId = await txn.insert('subjects', {
          'code': code,
          'name': data.fullName.isNotEmpty ? data.fullName : code,
          'semester': 1,
          'credits': 3,
          // Trang Syllabus Details không có cột kỳ học, nên kỳ 1 ở đây chỉ là
          // giá trị tạm. Đánh dấu để lần nhập Curriculum Details sau này (nếu
          // có) được phép ghi đè bằng kỳ thật của môn.
          'semester_is_placeholder': 1,
          'description': data.description,
          'created_at': now,
          'updated_at': now,
        });
      }

      // 2. Upsert bảng `syllabi`
      final sylValues = <String, Object?>{
        'subject_id': subjectId,
        'fap_syllabus_id': data.fapSyllabusId,
        'name_en': data.nameEn.isNotEmpty ? data.nameEn : null,
        'name_native': data.nameNative.isNotEmpty ? data.nameNative : null,
        'degree_level': data.degreeLevel.isNotEmpty ? data.degreeLevel : null,
        'learning_teaching_method': data.learningTeachingMethod.isNotEmpty ? data.learningTeachingMethod : null,
        'time_allocation': data.timeAllocation.isNotEmpty ? data.timeAllocation : null,
        'description': data.description.isNotEmpty ? data.description : null,
        'student_tasks': data.studentTasks.isNotEmpty ? data.studentTasks : null,
        'tools': data.tools.isNotEmpty ? data.tools : null,
        'scoring_scale': data.scoringScale,
        'decision_no': data.decisionNo.isNotEmpty ? data.decisionNo : null,
        'decision_date': data.decisionDate.isNotEmpty ? data.decisionDate : null,
        'is_approved': data.isApproved ? 1 : 0,
        'is_scored': data.isScored ? 1 : 0,
        'min_avg_mark_to_pass': data.minAvgMarkToPass,
        'is_active': data.isActive ? 1 : 0,
        'approved_date': data.approvedDate.isNotEmpty ? data.approvedDate : null,
        'raw_prerequisite_text': data.rawPrerequisiteText.isNotEmpty ? data.rawPrerequisiteText : null,
        'source_url': data.sourceUrl.isNotEmpty ? data.sourceUrl : null,
        'synced_at': now,
      };

      final existingSyl = data.fapSyllabusId != null
          ? await txn.query(
              'syllabi',
              columns: ['id'],
              where: 'fap_syllabus_id = ?',
              whereArgs: [data.fapSyllabusId],
              limit: 1,
            )
          : await txn.query(
              'syllabi',
              columns: ['id'],
              where: 'subject_id = ?',
              whereArgs: [subjectId],
              limit: 1,
            );

      if (existingSyl.isNotEmpty) {
        syllabusId = existingSyl.first['id'] as int;
        await txn.update('syllabi', sylValues, where: 'id = ?', whereArgs: [syllabusId]);
      } else {
        syllabusId = await txn.insert('syllabi', sylValues);
      }

      // 3. Xoá & nạp lại `materials`
      await txn.delete('materials', where: 'syllabus_id = ?', whereArgs: [syllabusId]);
      for (final m in data.materials) {
        await txn.insert('materials', {
          'syllabus_id': syllabusId,
          'seq_no': m.seqNo,
          'description': m.description,
          'author': m.author.isNotEmpty ? m.author : null,
          'publisher': m.publisher.isNotEmpty ? m.publisher : null,
          'published_date': m.publishedDate.isNotEmpty ? m.publishedDate : null,
          'edition': m.edition.isNotEmpty ? m.edition : null,
          'isbn': m.isbn.isNotEmpty ? m.isbn : null,
          'is_main': m.isMain ? 1 : 0,
          'is_hard_copy': m.isHardCopy ? 1 : 0,
          'is_online': m.isOnline ? 1 : 0,
          'note': m.note.isNotEmpty ? m.note : null,
        });
      }

      // 4. Xoá & nạp lại `learning_outcomes`
      await txn.delete('learning_outcomes', where: 'syllabus_id = ?', whereArgs: [syllabusId]);
      final cloCodeToId = <String, int>{};
      for (final clo in data.clos) {
        final cloId = await txn.insert('learning_outcomes', {
          'syllabus_id': syllabusId,
          'code': clo.code,
          'detail': clo.detail,
        });
        cloCodeToId[clo.code.toUpperCase()] = cloId;
        if (clo.code.toUpperCase().startsWith('CLO')) {
          cloCodeToId[clo.code.toUpperCase().replaceFirst('CLO', 'LO')] = cloId;
        }
      }

      // 5. Xoá & nạp lại `sessions` & `session_learning_outcomes`
      final existingSessions = await txn.query(
        'sessions',
        columns: ['id'],
        where: 'syllabus_id = ?',
        whereArgs: [syllabusId],
      );
      for (final sRow in existingSessions) {
        await txn.delete('session_learning_outcomes', where: 'session_id = ?', whereArgs: [sRow['id']]);
      }
      await txn.delete('sessions', where: 'syllabus_id = ?', whereArgs: [syllabusId]);

      for (final sess in data.sessions) {
        final sessionId = await txn.insert('sessions', {
          'syllabus_id': syllabusId,
          'session_no': sess.sessionNo,
          'topic': sess.topic,
          'teaching_type': sess.teachingType.isNotEmpty ? sess.teachingType : null,
          'itu': sess.itu.isNotEmpty ? sess.itu : null,
          'student_materials': sess.studentMaterials.isNotEmpty ? sess.studentMaterials : null,
          'download_url': sess.downloadUrl.isNotEmpty ? sess.downloadUrl : null,
          'student_tasks': sess.studentTasks.isNotEmpty ? sess.studentTasks : null,
          'urls': sess.urls.isNotEmpty ? sess.urls : null,
        });

        for (final code in sess.cloCodes) {
          final cloId = cloCodeToId[code.toUpperCase()];
          if (cloId != null) {
            await txn.insert('session_learning_outcomes', {
              'session_id': sessionId,
              'clo_id': cloId,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
      }

      // 6. Xoá & nạp lại `assessments` & `assessment_learning_outcomes`
      final existingAst = await txn.query(
        'assessments',
        columns: ['id'],
        where: 'syllabus_id = ?',
        whereArgs: [syllabusId],
      );
      for (final aRow in existingAst) {
        await txn.delete('assessment_learning_outcomes', where: 'assessment_id = ?', whereArgs: [aRow['id']]);
      }
      await txn.delete('assessments', where: 'syllabus_id = ?', whereArgs: [syllabusId]);

      for (final ast in data.assessments) {
        final astId = await txn.insert('assessments', {
          'syllabus_id': syllabusId,
          'seq_no': ast.seqNo,
          'category': ast.category,
          'type': ast.type.isNotEmpty ? ast.type : null,
          'part': ast.part,
          'weight_percent': ast.weightPercent,
          'completion_criteria': ast.completionCriteria.isNotEmpty ? ast.completionCriteria : null,
          'duration': ast.duration.isNotEmpty ? ast.duration : null,
          'question_type': ast.questionType.isNotEmpty ? ast.questionType : null,
          'no_question': ast.noQuestion,
          'knowledge_skill': ast.knowledgeSkill.isNotEmpty ? ast.knowledgeSkill : null,
          'grading_guide': ast.gradingGuide.isNotEmpty ? ast.gradingGuide : null,
          'note': ast.note.isNotEmpty ? ast.note : null,
        });

        for (final code in ast.cloCodes) {
          final cloId = cloCodeToId[code.toUpperCase()];
          if (cloId != null) {
            await txn.insert('assessment_learning_outcomes', {
              'assessment_id': astId,
              'clo_id': cloId,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
      }

      // 6. Bóc tách & tạo liên kết tiên quyết cho môn này nếu có rawPrerequisiteText
      if (data.rawPrerequisiteText.trim().isNotEmpty) {
        final pCodes = FapMarkdownParser.extractPrerequisiteCodes(data.rawPrerequisiteText);
        for (final pCode in pCodes) {
          final pSub = await txn.query('subjects', columns: ['id'], where: 'code = ?', whereArgs: [pCode], limit: 1);
          if (pSub.isNotEmpty) {
            final prereqId = pSub.first['id'] as int;
            if (prereqId != subjectId) {
              final cycle = await _wouldCreateCycle(subjectId, prereqId, txn: txn);
              if (!cycle) {
                await txn.insert(
                  'prerequisites',
                  {
                    'subject_id': subjectId,
                    'prerequisite_id': prereqId,
                    'relation_type': 'PREREQUISITE',
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                );
              }
            }
          }
        }
      }
    });

    return FapSyllabusImportResult(
      syllabusId: syllabusId,
      subjectCode: data.subjectCode,
      materialsCount: data.materials.length,
      closCount: data.clos.length,
      sessionsCount: data.sessions.length,
      assessmentsCount: data.assessments.length,
    );
  }

  /// Quét toàn bộ thông tin tiên quyết từ bảng `curriculum_subjects` và `syllabi`,
  /// bóc tách các mã môn và tạo cạnh trong bảng `prerequisites`.
  /// Trả về số lượng cạnh tiên quyết được tạo mới.
  Future<int> syncPrerequisitesFromFap({DatabaseExecutor? txn}) async {
    final db = txn ?? await database;
    var newEdges = 0;

    // 1. Quét từ curriculum_subjects
    final curSubRows = await db.rawQuery('''
      SELECT cs.subject_id, cs.raw_prerequisite_text, s.code AS subject_code
      FROM curriculum_subjects cs
      JOIN subjects s ON s.id = cs.subject_id
      WHERE cs.raw_prerequisite_text IS NOT NULL AND TRIM(cs.raw_prerequisite_text) != ''
    ''');

    // 2. Quét từ syllabi
    final sylRows = await db.rawQuery('''
      SELECT sy.subject_id, sy.raw_prerequisite_text, s.code AS subject_code
      FROM syllabi sy
      JOIN subjects s ON s.id = sy.subject_id
      WHERE sy.raw_prerequisite_text IS NOT NULL AND TRIM(sy.raw_prerequisite_text) != ''
    ''');

    final candidates = <int, Set<String>>{};
    for (final r in [...curSubRows, ...sylRows]) {
      final sId = r['subject_id'] as int;
      final raw = (r['raw_prerequisite_text'] as String?) ?? '';
      final codes = FapMarkdownParser.extractPrerequisiteCodes(raw);
      if (codes.isNotEmpty) {
        candidates.putIfAbsent(sId, () => <String>{}).addAll(codes);
      }
    }

    final allSubs = await db.query('subjects', columns: ['id', 'code']);
    final codeToId = {
      for (final s in allSubs) (s['code'] as String).trim().toUpperCase(): s['id'] as int,
    };

    for (final entry in candidates.entries) {
      final subjectId = entry.key;
      for (final pCode in entry.value) {
        final prereqId = codeToId[pCode.trim().toUpperCase()];
        if (prereqId != null && prereqId != subjectId) {
          final cycle = await _wouldCreateCycle(subjectId, prereqId, txn: db);
          if (!cycle) {
            final res = await db.insert(
              'prerequisites',
              {
                'subject_id': subjectId,
                'prerequisite_id': prereqId,
                'relation_type': 'PREREQUISITE',
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            if (res > 0) newEdges++;
          }
        }
      }
    }

    return newEdges;
  }

  /// Lấy danh sách tóm tắt tất cả các môn đã có Syllabus trong CSDL
  Future<List<Map<String, dynamic>>> getAvailableSyllabi() async {
    final db = await database;
    return db.rawQuery('''
      SELECT s.id AS subject_id,
             s.code,
             s.name,
             sb.id AS syllabus_id,
             sb.fap_syllabus_id,
             sb.name_en,
             sb.time_allocation,
             sb.degree_level,
             (SELECT COUNT(*) FROM sessions WHERE syllabus_id = sb.id) AS session_count,
             (SELECT COUNT(*) FROM learning_outcomes WHERE syllabus_id = sb.id) AS clo_count
      FROM syllabi sb
      JOIN subjects s ON s.id = sb.subject_id
      ORDER BY s.code ASC
    ''');
  }

  /// Kiểm tra xem môn học đã có Syllabus trong CSDL chưa
  Future<bool> hasSyllabus(int subjectId) async {
    final db = await database;
    final rows = await db.query(
      'syllabi',
      columns: ['id'],
      where: 'subject_id = ?',
      whereArgs: [subjectId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Kiểm tra xem mã môn học đã có Syllabus trong CSDL chưa
  Future<bool> hasSyllabusByCode(String code) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT sb.id FROM syllabi sb
      JOIN subjects s ON s.id = sb.subject_id
      WHERE UPPER(s.code) = ?
      LIMIT 1
    ''', [code.trim().toUpperCase()]);
    return rows.isNotEmpty;
  }

  /// Lấy chi tiết toàn bộ Syllabus theo subjectId hoặc subjectCode
  Future<FapSyllabusImport?> getSyllabusDetail({int? subjectId, String? subjectCode}) async {
    final db = await database;

    List<Map<String, dynamic>> sylRows;
    if (subjectId != null) {
      sylRows = await db.rawQuery('''
        SELECT sb.*, s.code AS subject_code, s.name AS subject_name
        FROM syllabi sb
        JOIN subjects s ON s.id = sb.subject_id
        WHERE sb.subject_id = ?
        LIMIT 1
      ''', [subjectId]);
    } else if (subjectCode != null && subjectCode.isNotEmpty) {
      sylRows = await db.rawQuery('''
        SELECT sb.*, s.code AS subject_code, s.name AS subject_name
        FROM syllabi sb
        JOIN subjects s ON s.id = sb.subject_id
        WHERE UPPER(s.code) = ?
        LIMIT 1
      ''', [subjectCode.trim().toUpperCase()]);
    } else {
      return null;
    }

    if (sylRows.isEmpty) return null;
    final syl = sylRows.first;
    final syllabusId = syl['id'] as int;
    final code = syl['subject_code'] as String? ?? '';

    // 1. Materials
    final matRows = await db.query(
      'materials',
      where: 'syllabus_id = ?',
      whereArgs: [syllabusId],
      orderBy: 'seq_no ASC, id ASC',
    );
    final materials = matRows.map((m) {
      return FapMaterialRow(
        seqNo: (m['seq_no'] as int?) ?? 1,
        description: (m['description'] as String?) ?? '',
        author: (m['author'] as String?) ?? '',
        publisher: (m['publisher'] as String?) ?? '',
        publishedDate: (m['published_date'] as String?) ?? '',
        edition: (m['edition'] as String?) ?? '',
        isbn: (m['isbn'] as String?) ?? '',
        isMain: (m['is_main'] as int? ?? 0) == 1,
        isHardCopy: (m['is_hard_copy'] as int? ?? 0) == 1,
        isOnline: (m['is_online'] as int? ?? 0) == 1,
        note: (m['note'] as String?) ?? '',
      );
    }).toList();

    // 2. CLOs
    final cloRows = await db.query(
      'learning_outcomes',
      where: 'syllabus_id = ?',
      whereArgs: [syllabusId],
      orderBy: 'id ASC',
    );
    final clos = cloRows.map((c) {
      return FapCloRow(
        code: (c['code'] as String?) ?? '',
        detail: (c['detail'] as String?) ?? '',
      );
    }).toList();

    // 3. Sessions & session CLOs
    final sessRows = await db.query(
      'sessions',
      where: 'syllabus_id = ?',
      whereArgs: [syllabusId],
      orderBy: 'session_no ASC, id ASC',
    );

    final sessionCloMap = <int, List<String>>{};
    final sessionCloRows = await db.rawQuery('''
      SELECT slo.session_id, lo.code
      FROM session_learning_outcomes slo
      JOIN learning_outcomes lo ON lo.id = slo.clo_id
      WHERE lo.syllabus_id = ?
    ''', [syllabusId]);

    for (final r in sessionCloRows) {
      final sId = r['session_id'] as int;
      final cloCode = r['code'] as String;
      sessionCloMap.putIfAbsent(sId, () => []).add(cloCode);
    }

    final sessions = sessRows.map((s) {
      final sId = s['id'] as int;
      return FapSessionRow(
        sessionNo: (s['session_no'] as int?) ?? 1,
        topic: (s['topic'] as String?) ?? '',
        teachingType: (s['teaching_type'] as String?) ?? '',
        itu: (s['itu'] as String?) ?? '',
        studentMaterials: (s['student_materials'] as String?) ?? '',
        downloadUrl: (s['download_url'] as String?) ?? '',
        studentTasks: (s['student_tasks'] as String?) ?? '',
        urls: (s['urls'] as String?) ?? '',
        cloCodes: sessionCloMap[sId] ?? const [],
      );
    }).toList();

    // 4. Assessments & assessment CLOs
    final astRows = await db.query(
      'assessments',
      where: 'syllabus_id = ?',
      whereArgs: [syllabusId],
      orderBy: 'seq_no ASC, id ASC',
    );

    final astCloMap = <int, List<String>>{};
    final astCloRows = await db.rawQuery('''
      SELECT alo.assessment_id, lo.code
      FROM assessment_learning_outcomes alo
      JOIN learning_outcomes lo ON lo.id = alo.clo_id
      WHERE lo.syllabus_id = ?
    ''', [syllabusId]);

    for (final r in astCloRows) {
      final aId = r['assessment_id'] as int;
      final cloCode = r['code'] as String;
      astCloMap.putIfAbsent(aId, () => []).add(cloCode);
    }

    final assessments = astRows.map((a) {
      final aId = a['id'] as int;
      return FapAssessmentRow(
        seqNo: (a['seq_no'] as int?) ?? 1,
        category: (a['category'] as String?) ?? '',
        type: (a['type'] as String?) ?? '',
        part: (a['part'] as int?) ?? 1,
        weightPercent: (a['weight_percent'] as num?)?.toDouble() ?? 0.0,
        completionCriteria: (a['completion_criteria'] as String?) ?? '',
        duration: (a['duration'] as String?) ?? '',
        questionType: (a['question_type'] as String?) ?? '',
        noQuestion: a['no_question'] as int?,
        knowledgeSkill: (a['knowledge_skill'] as String?) ?? '',
        gradingGuide: (a['grading_guide'] as String?) ?? '',
        note: (a['note'] as String?) ?? '',
        cloCodes: astCloMap[aId] ?? const [],
      );
    }).toList();

    return FapSyllabusImport(
      fapSyllabusId: syl['fap_syllabus_id'] as int?,
      subjectCode: code,
      nameEn: (syl['name_en'] as String?) ?? '',
      nameNative: (syl['name_native'] as String?) ?? '',
      degreeLevel: (syl['degree_level'] as String?) ?? '',
      learningTeachingMethod: (syl['learning_teaching_method'] as String?) ?? '',
      timeAllocation: (syl['time_allocation'] as String?) ?? '',
      description: (syl['description'] as String?) ?? '',
      studentTasks: (syl['student_tasks'] as String?) ?? '',
      tools: (syl['tools'] as String?) ?? '',
      scoringScale: syl['scoring_scale'] as int?,
      decisionNo: (syl['decision_no'] as String?) ?? '',
      decisionDate: (syl['decision_date'] as String?) ?? '',
      isApproved: (syl['is_approved'] as int? ?? 0) == 1,
      isScored: (syl['is_scored'] as int? ?? 0) == 1,
      minAvgMarkToPass: (syl['min_avg_mark_to_pass'] as num?)?.toDouble(),
      isActive: (syl['is_active'] as int? ?? 0) == 1,
      approvedDate: (syl['approved_date'] as String?) ?? '',
      rawPrerequisiteText: (syl['raw_prerequisite_text'] as String?) ?? '',
      sourceUrl: (syl['source_url'] as String?) ?? '',
      materials: materials,
      clos: clos,
      sessions: sessions,
      assessments: assessments,
    );
  }

  /// Quét và tự động nạp toàn bộ các file .md trong thư mục `fap_inbox/` vào CSDL.
  /// Ưu tiên nạp file Curriculum trước (để có khung và mã môn), sau đó nạp các file Syllabus,
  /// cuối cùng đồng bộ cạnh tiên quyết (prerequisites).
  Future<Map<String, dynamic>> batchImportFromInbox({Directory? inboxDir}) async {
    final directoriesToCheck = <Directory>[];
    if (inboxDir != null) {
      directoriesToCheck.add(inboxDir);
    } else {
      final appSupport = await getApplicationSupportDirectory();
      directoriesToCheck.add(Directory(p.join(appSupport.path, 'fap_inbox')));
      final vault = await SettingsService.instance.getVaultPath();
      if (vault != null && vault.isNotEmpty) {
        directoriesToCheck.add(Directory(p.join(vault, 'FAP')));
      }
    }

    final mdFilesMap = <String, File>{};
    for (final dir in directoriesToCheck) {
      if (!await dir.exists()) continue;
      final entities = await dir.list().toList();
      for (final e in entities) {
        if (e is File && e.path.toLowerCase().endsWith('.md')) {
          mdFilesMap[p.canonicalize(e.path)] = e;
        }
      }
    }

    final mdFiles = mdFilesMap.values.toList();
    if (mdFiles.isEmpty) {
      return {
        'totalFiles': 0,
        'curricula': 0,
        'syllabi': 0,
        'failed': 0,
        'edges': 0,
      };
    }

    var curCount = 0;
    var sylCount = 0;
    var failCount = 0;

    final curFiles = <(File, FapParseResult)>[];
    final sylFiles = <(File, FapParseResult)>[];

    for (final file in mdFiles) {
      try {
        final content = await file.readAsString();
        final parsed = FapMarkdownParser.parse(content);
        if (parsed.curriculum != null) {
          curFiles.add((file, parsed));
        } else if (parsed.syllabus != null) {
          sylFiles.add((file, parsed));
        }
      } catch (_) {
        failCount++;
      }
    }

    // 1. Nhập curricula trước
    for (final item in curFiles) {
      try {
        await importFapCurriculum(item.$2.curriculum!);
        curCount++;
      } catch (_) {
        failCount++;
      }
    }

    // 2. Nhập syllabi
    for (final item in sylFiles) {
      try {
        await importFapSyllabus(item.$2.syllabus!);
        sylCount++;
      } catch (_) {
        failCount++;
      }
    }

    // 3. Đồng bộ toàn bộ cạnh tiên quyết
    final edgesCreated = await syncPrerequisitesFromFap();

    return {
      'totalFiles': mdFiles.length,
      'curricula': curCount,
      'syllabi': sylCount,
      'failed': failCount,
      'edges': edgesCreated,
    };
  }

  /// Kích thước file .db theo byte (hiển thị trong Cài đặt).
  Future<int> databaseSizeInBytes() async {
    final path = _dbPath;
    if (path == null) return 0;
    final file = File(path);
    return await file.exists() ? file.length() : 0;
  }
}

/// Kết quả sau khi ghi một trang Syllabus Details xuống CSDL.
class FapSyllabusImportResult {
  final int syllabusId;
  final String subjectCode;
  final int materialsCount;
  final int closCount;
  final int sessionsCount;
  final int assessmentsCount;

  const FapSyllabusImportResult({
    required this.syllabusId,
    required this.subjectCode,
    required this.materialsCount,
    required this.closCount,
    required this.sessionsCount,
    required this.assessmentsCount,
  });

  @override
  String toString() =>
      'FapSyllabusImportResult($subjectCode: $materialsCount tai lieu, $closCount CLO, '
      '$sessionsCount buoi hoc, $assessmentsCount dau diem)';
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

/// Kết quả sau khi ghi một trang Curriculum Details của FAP xuống CSDL.
class FapImportResult {
  final int curriculumId;
  final String curriculumCode;

  /// Số môn lần đầu xuất hiện trong `subjects`.
  final int insertedSubjects;

  /// Số môn đã có sẵn, chỉ được làm mới phần tên.
  final int updatedSubjects;

  final int plos;

  /// Số dòng ghi vào bảng nối `curriculum_subjects`.
  final int curriculumSubjects;

  const FapImportResult({
    required this.curriculumId,
    required this.curriculumCode,
    required this.insertedSubjects,
    required this.updatedSubjects,
    required this.plos,
    required this.curriculumSubjects,
  });

  int get totalSubjects => insertedSubjects + updatedSubjects;

  @override
  String toString() =>
      'FapImportResult($curriculumCode: $insertedSubjects mon moi, '
      '$updatedSubjects mon cap nhat, $plos PLO, $curriculumSubjects lien ket)';
}

/// Một dòng sắp ghi vào `curriculum_courses`: môn nào, thuộc kỳ nào của tệp
/// môn học đó, mang bao nhiêu tín chỉ trong khung này.
class CurriculumCourseEntry {
  final int subjectId;
  final int term;
  final int credits;

  const CurriculumCourseEntry({
    required this.subjectId,
    this.term = 1,
    this.credits = 3,
  });
}

/// Lỗi nghiệp vụ từ tầng DB (trùng khoá, chu trình, ...) để UI hiển thị tử tế.
class DbConflictException implements Exception {
  final String message;
  DbConflictException(this.message);
  @override
  String toString() => message;
}
