import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:se_knowledge/models/subject.dart';
import 'package:se_knowledge/models/transcript_entry.dart';
import 'package:se_knowledge/services/db_service.dart';
import 'package:se_knowledge/services/transcript_parser_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Kiểm thử tầng CSDL của bảng điểm: migration v5 -> v6, tính idempotent của
/// việc nhập lại, và điều quan trọng nhất — **xoá môn không được làm mất
/// điểm**.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();

    tempDir = await Directory.systemTemp.createTemp('se_knowledge_transcript');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );

    await _seedVersion5Database(p.join(tempDir.path, DbService.dbFileName));
  });

  tearDownAll(() async {
    await DbService.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('migration v5 -> v6', () {
    test('tạo được bảng transcript_entries và giữ nguyên dữ liệu cũ', () async {
      final db = await DbService.instance.database;

      final version =
          (await db.rawQuery('PRAGMA user_version')).first.values.first;
      expect(version, DbService.dbVersion);
      expect(DbService.dbVersion, 6);

      final names = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      )).map((r) => r['name'] as String).toSet();
      expect(names, contains('transcript_entries'));
      // Bảng cũ còn nguyên, migration chỉ cộng thêm.
      expect(names, containsAll(['subjects', 'prerequisites', 'curriculums']));

      final subjects = await db.query('subjects', orderBy: 'code ASC');
      expect(subjects.map((r) => r['code']).toList(), ['CSD201', 'PRF192']);
      expect(
        subjects.firstWhere((r) => r['code'] == 'PRF192')['note_path'],
        'PRF192.md',
      );
      expect(await db.query('prerequisites'), hasLength(1));
      expect(await db.query('transcript_entries'), isEmpty);
    });

    test('khoá ngoại của bảng điểm là SET NULL, không phải CASCADE', () async {
      final db = await DbService.instance.database;
      final rows = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE name='transcript_entries'",
      );
      final sql = rows.first['sql'] as String;
      expect(sql, contains('ON DELETE SET NULL'));
      expect(sql, isNot(contains('ON DELETE CASCADE')));
    });
  });

  group('nhập bảng điểm', () {
    setUp(() async {
      await DbService.instance.clearTranscript();
    });

    test('kế hoạch đếm đúng môn khớp và môn còn thiếu', () async {
      final plan = await DbService.instance.planTranscriptImport([
        _entry('PRF192', grade: 7.2),
        _entry('CSD201', grade: 6.9),
        _entry('VOV114', grade: 5.8), // không có trong đồ thị
      ]);

      expect(plan.totalCount, 3);
      expect(plan.matchedCount, 2);
      expect(plan.missingSubjectCodes, ['VOV114']);
      expect(plan.willOverwriteCount, 0);
      expect(plan.newCount, 3);

      // Kế hoạch chỉ đọc: chưa có dòng nào xuống CSDL.
      expect(await DbService.instance.transcriptCount(), 0);
    });

    test('nhập hai lần cùng một file không sinh dòng trùng', () async {
      final bytes = await File(
        'test/fixtures/transcript/StudentTranscript_SE193040.xls',
      ).readAsBytes();
      final parsed = TranscriptParserService.instance.parseBytes(bytes);
      expect(parsed.entries, hasLength(48));

      final first = await DbService.instance.applyTranscriptPlan(
        await DbService.instance.planTranscriptImport(parsed.entries),
      );
      expect(first.writtenCount, 48);
      expect(first.replacedCount, 0);
      expect(await DbService.instance.transcriptCount(), 48);

      final secondPlan = await DbService.instance.planTranscriptImport(
        parsed.entries,
      );
      // Lần hai phải nhận ra toàn bộ là ghi đè chứ không phải dòng mới.
      expect(secondPlan.willOverwriteCount, 48);
      await DbService.instance.applyTranscriptPlan(secondPlan);
      expect(await DbService.instance.transcriptCount(), 48);
    });

    test('dòng không khớp môn nào vẫn được lưu với subject_id NULL', () async {
      await DbService.instance.applyTranscriptPlan(
        await DbService.instance.planTranscriptImport([
          _entry('PRF192', grade: 7.2),
          _entry('VOV114', grade: 5.8),
        ]),
      );

      final rows = await DbService.instance.getTranscript();
      expect(rows, hasLength(2));
      expect(
        rows.firstWhere((e) => e.subjectCode == 'PRF192').subjectId,
        isNotNull,
      );
      expect(
        rows.firstWhere((e) => e.subjectCode == 'VOV114').subjectId,
        isNull,
      );
    });

    test('bật tuỳ chọn thì môn còn thiếu mới được tạo trong đồ thị', () async {
      final plan = await DbService.instance.planTranscriptImport([
        _entry('JPD113', grade: 9.3, name: 'Elementary Japanese'),
      ]);
      final result = await DbService.instance.applyTranscriptPlan(
        plan,
        createMissingSubjects: true,
      );

      expect(result.createdSubjects, 1);
      expect(result.linkedCount, 1);
      final created = await DbService.instance.getSubjectByCode('JPD113');
      expect(created, isNotNull);
      expect(created!.name, 'Elementary Japanese');

      // Dọn lại để không ảnh hưởng các bài test sau.
      await DbService.instance.deleteSubject(created.id!);
    });
  });

  group('đọc lại bảng điểm', () {
    setUp(() async {
      await DbService.instance.clearTranscript();
    });

    test('latestGradeByCode trả lần học mới nhất', () async {
      await DbService.instance.applyTranscriptPlan(
        await DbService.instance.planTranscriptImport([
          _entry(
            'CSD201',
            grade: 4.0,
            status: SubjectStatus.notPassed,
            semester: 'Spring2024',
            order: 20241,
          ),
          _entry(
            'CSD201',
            grade: 6.9,
            semester: 'Fall2024',
            order: 20243,
          ),
        ]),
      );

      // Hai lần học là hai dòng lịch sử riêng, không đè lên nhau.
      expect(await DbService.instance.transcriptCount(), 2);

      final latest = await DbService.instance.latestGradeByCode();
      expect(latest['CSD201']!.grade, 6.9);
      expect(latest['CSD201']!.status, SubjectStatus.passed);
      expect(latest['CSD201']!.semesterLabel, 'Fall2024');
    });

    test('môn chưa có điểm vẫn tra được trạng thái đang học', () async {
      await DbService.instance.applyTranscriptPlan(
        await DbService.instance.planTranscriptImport([
          _entry(
            'PRF192',
            status: SubjectStatus.studying,
            semester: '',
            order: 0,
          ),
        ]),
      );
      final latest = await DbService.instance.latestGradeByCode();
      expect(latest['PRF192']!.status, SubjectStatus.studying);
      expect(latest['PRF192']!.hasGrade, isFalse);
    });

    test('sửa tay cờ tính vào GPA được lưu lại', () async {
      await DbService.instance.applyTranscriptPlan(
        await DbService.instance.planTranscriptImport([
          _entry('PRF192', grade: 7.2),
        ]),
      );
      final row = (await DbService.instance.getTranscript()).single;
      expect(row.countsTowardGpa, isTrue);

      await DbService.instance.setCountsTowardGpa(row.id!, false);
      expect(
        (await DbService.instance.getTranscript()).single.countsTowardGpa,
        isFalse,
      );
    });
  });

  test('xoá môn giữ lại điểm, chỉ gỡ liên kết subject_id', () async {
    await DbService.instance.clearTranscript();
    await DbService.instance.applyTranscriptPlan(
      await DbService.instance.planTranscriptImport([
        _entry('CSD201', grade: 6.9),
      ]),
    );

    final subject = await DbService.instance.getSubjectByCode('CSD201');
    expect((await DbService.instance.getTranscript()).single.subjectId,
        subject!.id);

    await DbService.instance.deleteSubject(subject.id!);

    final after = await DbService.instance.getTranscript();
    // Điểm đã học là dữ liệu lịch sử không tái tạo được — xoá môn khỏi đồ thị
    // không được phép xoá nó theo.
    expect(after, hasLength(1));
    expect(after.single.subjectCode, 'CSD201');
    expect(after.single.grade, 6.9);
    expect(after.single.subjectId, isNull);
  });
}

TranscriptEntry _entry(
  String code, {
  double? grade,
  int credits = 3,
  SubjectStatus status = SubjectStatus.passed,
  String semester = 'Fall2024',
  int order = 20243,
  int? term = 1,
  String name = '',
}) {
  return TranscriptEntry(
    subjectCode: code,
    subjectName: name.isEmpty ? 'Môn $code' : name,
    term: term,
    semesterLabel: semester,
    semesterOrder: order,
    credits: credits,
    grade: grade,
    status: status,
    countsTowardGpa: TranscriptEntry.countsTowardGpaByDefault(
      status: status,
      grade: grade,
      credits: credits,
      isGraduationCondition: false,
    ),
    importedAt: DateTime(2026, 9, 1),
  );
}

/// Dựng một file `.db` đúng schema version 5 kèm dữ liệu thật, để [DbService]
/// mở lên và tự chạy nhánh `_onUpgrade` lên version 6 — đúng đường đi của file
/// trên máy người dùng, khác với `_onCreate` mà các test khác chạm tới.
Future<void> _seedVersion5Database(String path) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 5,
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
            updated_at  TEXT    NOT NULL,
            semester_is_placeholder INTEGER NOT NULL DEFAULT 0
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
        // 10 bảng FAP của v3: nhánh `oldVersion < 6` không đụng tới chúng,
        // nhưng `_onUpgrade` cần chúng tồn tại để câu vá của v5 chạy được.
        await db.execute(
          'CREATE TABLE syllabi (id INTEGER PRIMARY KEY, subject_id INTEGER)',
        );
        await db.execute(
          'CREATE TABLE curriculum_subjects (id INTEGER PRIMARY KEY, subject_id INTEGER)',
        );

        final now = DateTime(2026, 1, 1).toIso8601String();
        Future<int> addSubject(String code, {String? notePath}) => db.insert(
          'subjects',
          Subject(
            code: code,
            name: 'Môn $code',
            notePath: notePath,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ).toMap(),
        );

        final prf = await addSubject('PRF192', notePath: 'PRF192.md');
        final csd = await addSubject('CSD201');
        await db.insert('prerequisites', {
          'subject_id': csd,
          'prerequisite_id': prf,
          'relation_type': 'PREREQUISITE',
        });
        await db.insert('curriculums', {
          'code': 'BIT_SE_K20B',
          'name': 'Kỹ thuật phần mềm',
          'major': 'SE',
          'total_credits': 145,
          'decision_no': '',
          'description': '',
          'created_at': now,
          'updated_at': now,
        });
      },
    ),
  );
  await db.close();
}
