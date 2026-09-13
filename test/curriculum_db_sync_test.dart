import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:se_knowledge/models/curriculum.dart';
import 'package:se_knowledge/models/prerequisite.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('Curriculum to SQLite Sync Tests (Schema v2)', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 2,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (db, version) async {
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
          },
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('Imports curriculum into curriculums, subjects, curriculum_courses and prerequisites', () async {
      const curriculum = Curriculum(
        code: 'BIT_SE_K20B',
        name: 'Bachelor Program of Information Technology, Software Engineering Major',
        major: 'Kỹ thuật phần mềm (Software Engineering - SE)',
        totalCredits: 145,
        decisionNo: '577/QĐ-ĐHFPT',
        semesters: [
          Semester(
            termNumber: 1,
            courses: [
              Course(
                code: 'PRF192',
                name: 'Programming Fundamentals',
                credits: 3,
                prerequisites: [],
                term: 1,
              ),
              Course(
                code: 'MAD101',
                name: 'Discrete Mathematics',
                credits: 3,
                prerequisites: [],
                term: 1,
              ),
            ],
          ),
          Semester(
            termNumber: 2,
            courses: [
              Course(
                code: 'PRO192',
                name: 'OOP Java',
                credits: 3,
                prerequisites: ['PRF192'],
                term: 2,
              ),
            ],
          ),
          Semester(
            termNumber: 8,
            courses: [
              Course(
                code: 'PRM393',
                name: 'Mobile Programming',
                credits: 3,
                prerequisites: ['PRO192'],
                term: 8,
              ),
            ],
          ),
        ],
      );

      final now = DateTime.now().toIso8601String();
      final codeToId = <String, int>{};

      await db.transaction((txn) async {
        // 1. Chèn curriculum
        final currId = await txn.insert('curriculums', {
          'code': curriculum.code,
          'name': curriculum.name,
          'major': curriculum.major,
          'total_credits': curriculum.totalCredits,
          'decision_no': curriculum.decisionNo,
          'description': curriculum.description,
          'created_at': now,
          'updated_at': now,
        });

        // 2. Chèn subjects và curriculum_courses
        for (final sem in curriculum.semesters) {
          for (final c in sem.courses) {
            final sId = await txn.insert('subjects', {
              'code': c.code,
              'name': c.name,
              'semester': c.term,
              'credits': c.credits,
              'description': '',
              'created_at': now,
              'updated_at': now,
            });
            codeToId[c.code] = sId;

            await txn.insert('curriculum_courses', {
              'curriculum_id': currId,
              'subject_id': sId,
              'term': c.term,
              'credits': c.credits,
            });
          }
        }

        // 3. Chèn prerequisites
        for (final sem in curriculum.semesters) {
          for (final c in sem.courses) {
            final sId = codeToId[c.code];
            if (sId == null) continue;
            for (final pCode in c.prerequisites) {
              final pId = codeToId[pCode];
              if (pId != null && pId != sId) {
                await txn.insert('prerequisites', {
                  'subject_id': sId,
                  'prerequisite_id': pId,
                  'relation_type': Prerequisite.kPrerequisite,
                });
              }
            }
          }
        }
      });

      // Kiểm tra bảng curriculums
      final currs = await db.query('curriculums');
      expect(currs.length, 1);
      expect(currs.first['code'], 'BIT_SE_K20B');
      expect(currs.first['total_credits'], 145);

      // Kiểm tra bảng subjects
      final subjects = await db.query('subjects');
      expect(subjects.length, 4);

      // Kiểm tra bảng curriculum_courses
      final currCourses = await db.query('curriculum_courses');
      expect(currCourses.length, 4);

      // Kiểm tra môn PRM393 thuộc kỳ 8 trong khung BIT_SE_K20B
      final prmRow = await db.rawQuery('''
        SELECT s.code, cc.term, cc.credits, c.code AS curr_code
        FROM curriculum_courses cc
        JOIN subjects s ON s.id = cc.subject_id
        JOIN curriculums c ON c.id = cc.curriculum_id
        WHERE s.code = 'PRM393'
      ''');
      expect(prmRow.length, 1);
      expect(prmRow.first['term'], 8);
      expect(prmRow.first['curr_code'], 'BIT_SE_K20B');

      // Kiểm tra tiên quyết của PRM393 -> PRO192
      final prereqRows = await db.rawQuery('''
        SELECT p.code AS prereq_code
        FROM prerequisites pr
        JOIN subjects s ON s.id = pr.subject_id
        JOIN subjects p ON p.id = pr.prerequisite_id
        WHERE s.code = 'PRM393'
      ''');
      expect(prereqRows.length, 1);
      expect(prereqRows.first['prereq_code'], 'PRO192');
    });
  });
}
