import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:se_knowledge/services/db_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Kiểm tra nhánh `_onUpgrade` — đường đi của file `se_knowledge.db` THẬT trên
/// máy người dùng, khác với `_onCreate` mà các test khác chạm tới.
///
/// Dựng sẵn một file .db ở version 2 có dữ liệu (kể cả `note_path` trỏ sang
/// Obsidian Vault), để DbService mở lên và tự nâng cấp lên version 3.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();

    tempDir = await Directory.systemTemp.createTemp('se_knowledge_migration');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );

    await _seedVersion2Database(p.join(tempDir.path, DbService.dbFileName));
  });

  tearDownAll(() async {
    await DbService.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('nâng v2 -> v3 giữ nguyên 100% dữ liệu cũ', () async {
    final db = await DbService.instance.database;

    final version = (await db.rawQuery('PRAGMA user_version')).first.values.first;
    expect(version, 3);

    final subjects = await db.query('subjects', orderBy: 'code ASC');
    expect(subjects.map((r) => r['code']).toList(), ['MAD101', 'PRF192']);

    // note_path là thứ dễ mất nhất nếu migration lỡ tạo lại bảng.
    final prf = subjects.firstWhere((r) => r['code'] == 'PRF192');
    expect(prf['note_path'], 'PRF192.md');
    expect(prf['description'], 'Ghi chú tự viết');
    expect(prf['semester'], 1);

    expect(await db.query('prerequisites'), hasLength(1));
    expect(await db.query('curriculums'), hasLength(1));
  });

  test('nâng v2 -> v3 tạo thêm đủ 10 bảng FAP', () async {
    final db = await DbService.instance.database;
    final names = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((r) => r['name'] as String).toSet();

    expect(
      names,
      containsAll([
        'curricula',
        'program_learning_outcomes',
        'curriculum_subjects',
        'syllabi',
        'materials',
        'learning_outcomes',
        'sessions',
        'session_learning_outcomes',
        'assessments',
        'assessment_learning_outcomes',
      ]),
    );
  });

  test('bảng FAP mới rỗng — migration không seed lại dữ liệu mẫu', () async {
    final db = await DbService.instance.database;
    expect(await db.query('curricula'), isEmpty);
    expect(await db.query('syllabi'), isEmpty);
    // 7 môn mẫu của `_seed` KHÔNG được chèn đè lên dữ liệu thật.
    expect(await db.query('subjects'), hasLength(2));
  });
}

/// Dựng một file .db đúng như schema version 2 hiện hành, kèm dữ liệu thật.
Future<void> _seedVersion2Database(String path) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 2,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
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

        final now = DateTime.now().toIso8601String();
        final prf = await db.insert('subjects', {
          'code': 'PRF192',
          'name': 'Programming Fundamentals',
          'semester': 1,
          'credits': 3,
          'description': 'Ghi chú tự viết',
          'note_path': 'PRF192.md',
          'created_at': now,
          'updated_at': now,
        });
        final mad = await db.insert('subjects', {
          'code': 'MAD101',
          'name': 'Discrete Mathematics',
          'semester': 1,
          'credits': 3,
          'description': '',
          'note_path': 'MAD101.md',
          'created_at': now,
          'updated_at': now,
        });
        await db.insert('prerequisites', {
          'subject_id': mad,
          'prerequisite_id': prf,
          'relation_type': 'PREREQUISITE',
        });
        await db.insert('curriculums', {
          'code': 'BIT_SE',
          'name': 'Software Engineering',
          'major': 'SE',
          'total_credits': 145,
          'decision_no': '577',
          'description': '',
          'created_at': now,
          'updated_at': now,
        });
      },
    ),
  );
  await db.close();
}
