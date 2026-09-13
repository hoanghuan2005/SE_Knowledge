import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/services/db_service.dart';
import 'package:se_knowledge/services/fap_markdown_parser.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 10 bảng FAP mà migration v3 phải tạo ra.
const List<String> _fapTables = [
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
];

FapSubjectRow _row(
  String code, {
  String nameEn = 'Name',
  String nameVn = '',
  int semester = 1,
  int credits = 3,
  String prereq = '',
}) {
  return FapSubjectRow(
    code: code,
    nameEn: nameEn,
    nameVn: nameVn,
    rawPrerequisite: prereq,
    semester: semester,
    credits: credits,
  );
}

FapCurriculumImport _curriculum({
  required int curid,
  required String code,
  required List<FapSubjectRow> subjects,
  List<FapPloRow> plos = const [],
}) {
  return FapCurriculumImport(
    fapCurriculumId: curid,
    code: code,
    name: 'Chương trình $code',
    decisionNo: '577/QĐ-ĐHFPT',
    sourceUrl: 'https://flm.fpt.edu.vn/gui/role/student/CurriculumDetails?curid=$curid',
    totalCredits: 145,
    subjects: subjects,
    plos: plos,
  );
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();

    // path_provider trong unit test rơi về MethodChannel, nên trỏ nó vào một
    // thư mục tạm để DbService mở được file .db thật.
    tempDir = await Directory.systemTemp.createTemp('se_knowledge_fap_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  tearDownAll(() async {
    await DbService.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await DbService.instance.resetAll();
  });

  test('migration tạo đủ 10 bảng FAP mà không đụng 2 bảng lõi', () async {
    final db = await DbService.instance.database;
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final names = rows.map((r) => r['name'] as String).toSet();

    for (final table in _fapTables) {
      expect(names, contains(table), reason: 'thiếu bảng $table');
    }
    // Hai bảng lõi và hai bảng khung CTĐT cũ vẫn còn nguyên.
    expect(names, containsAll(['subjects', 'prerequisites']));
    expect(names, containsAll(['curriculums', 'curriculum_courses']));
  });

  test('nhập lần đầu tạo curriculum, môn, PLO và bảng nối', () async {
    final result = await DbService.instance.importFapCurriculum(
      _curriculum(
        curid: 2951,
        code: 'BIT_IS_K20D',
        subjects: [
          _row('FAP001', semester: 1, credits: 3, prereq: 'None'),
          _row('FAP002', semester: 2, credits: 2),
        ],
        plos: const [
          FapPloRow(code: 'PLO1', description: 'Mô tả 1'),
          FapPloRow(code: 'PLO2', description: 'Mô tả 2'),
        ],
      ),
    );

    expect(result.insertedSubjects, 2);
    expect(result.updatedSubjects, 0);
    expect(result.plos, 2);
    expect(result.curriculumSubjects, 2);

    final db = await DbService.instance.database;
    final links = await db.query('curriculum_subjects');
    expect(links, hasLength(2));
    // Tiên quyết chỉ được lưu nguyên văn, chưa dựng thành cạnh (Giai đoạn 5.4).
    expect(links.first['raw_prerequisite_text'], 'None');
    expect(await db.query('prerequisites'), isEmpty);
  });

  test('nhập lại cùng curid là upsert, không nhân bản', () async {
    final data = _curriculum(
      curid: 2951,
      code: 'BIT_IS_K20D',
      subjects: [_row('FAP001')],
      plos: const [FapPloRow(code: 'PLO1', description: 'Mô tả 1')],
    );

    final first = await DbService.instance.importFapCurriculum(data);
    final second = await DbService.instance.importFapCurriculum(data);

    expect(second.curriculumId, first.curriculumId);
    expect(second.insertedSubjects, 0);
    expect(second.updatedSubjects, 1);

    final db = await DbService.instance.database;
    expect(await db.query('curricula'), hasLength(1));
    expect(await db.query('curriculum_subjects'), hasLength(1));
    expect(await db.query('program_learning_outcomes'), hasLength(1));
  });

  test(
    'chương trình thứ hai KHÔNG ghi đè kỳ/tín chỉ của môn dùng chung',
    () async {
      // Môn FAP001 nằm ở kỳ 1 (3 tín chỉ) bên chương trình IS...
      await DbService.instance.importFapCurriculum(
        _curriculum(
          curid: 2951,
          code: 'BIT_IS_K20D',
          subjects: [_row('FAP001', nameEn: 'Ten cu', semester: 1, credits: 3)],
        ),
      );

      // ...nhưng ở kỳ 4 (4 tín chỉ) bên chương trình SE.
      await DbService.instance.importFapCurriculum(
        _curriculum(
          curid: 3005,
          code: 'BIT_SE_K20D',
          subjects: [_row('FAP001', nameEn: 'Ten moi', semester: 4, credits: 4)],
        ),
      );

      final db = await DbService.instance.database;
      final subject = (await db.query(
        'subjects',
        where: 'code = ?',
        whereArgs: ['FAP001'],
      )).single;

      // `subjects` chỉ nhận giá trị khởi tạo của lần nhập đầu; tên thì FAP là
      // nguồn chuẩn nên được làm mới.
      expect(subject['semester'], 1);
      expect(subject['credits'], 3);
      expect(subject['name'], 'Ten moi');

      // Kỳ/tín chỉ riêng của từng chương trình nằm ở bảng nối.
      final links = await db.rawQuery('''
        SELECT c.code AS curriculum, cs.semester, cs.credits
        FROM curriculum_subjects cs
        INNER JOIN curricula c ON c.id = cs.curriculum_id
        ORDER BY c.code
      ''');
      expect(links, hasLength(2));
      expect(links[0]['curriculum'], 'BIT_IS_K20D');
      expect(links[0]['semester'], 1);
      expect(links[1]['curriculum'], 'BIT_SE_K20D');
      expect(links[1]['semester'], 4);
      expect(links[1]['credits'], 4);
    },
  );

  test('không đụng tới ghi chú và mô tả người dùng đã có', () async {
    final db = await DbService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('subjects', {
      'code': 'FAP001',
      'name': 'Tên cũ',
      'semester': 7,
      'credits': 9,
      'description': 'Ghi chú của tôi',
      'note_path': 'FAP001.md',
      'created_at': now,
      'updated_at': now,
    });

    await DbService.instance.importFapCurriculum(
      _curriculum(
        curid: 2951,
        code: 'BIT_IS_K20D',
        subjects: [_row('FAP001', nameEn: 'Tên từ FAP', semester: 1, credits: 3)],
      ),
    );

    final subject = (await db.query(
      'subjects',
      where: 'code = ?',
      whereArgs: ['FAP001'],
    )).single;
    expect(subject['description'], 'Ghi chú của tôi');
    expect(subject['note_path'], 'FAP001.md');
    expect(subject['semester'], 7);
    expect(subject['credits'], 9);
    expect(subject['name'], 'Tên từ FAP');
  });

  test('kỳ 0 của FAP quy về kỳ 1 trong subjects nhưng giữ 0 ở bảng nối', () async {
    await DbService.instance.importFapCurriculum(
      _curriculum(
        curid: 2951,
        code: 'BIT_IS_K20D',
        subjects: [_row('OTP101', semester: 0, credits: 0)],
      ),
    );

    final db = await DbService.instance.database;
    final subject = (await db.query(
      'subjects',
      where: 'code = ?',
      whereArgs: ['OTP101'],
    )).single;
    expect(subject['semester'], 1);
    expect(subject['credits'], 0);

    final link = (await db.query('curriculum_subjects')).single;
    expect(link['semester'], 0);
    expect(link['credits'], 0);
  });

  test('xoá curriculum thì PLO và bảng nối tự dọn theo CASCADE', () async {
    final result = await DbService.instance.importFapCurriculum(
      _curriculum(
        curid: 2951,
        code: 'BIT_IS_K20D',
        subjects: [_row('FAP001')],
        plos: const [FapPloRow(code: 'PLO1', description: 'Mô tả 1')],
      ),
    );

    final db = await DbService.instance.database;
    await db.delete('curricula', where: 'id = ?', whereArgs: [result.curriculumId]);

    expect(await db.query('program_learning_outcomes'), isEmpty);
    expect(await db.query('curriculum_subjects'), isEmpty);
    // Môn học là node toàn cục, không bị xoá theo chương trình.
    expect(await db.query('subjects'), hasLength(1));
  });
}
