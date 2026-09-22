import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/services/db_service.dart';
import 'package:se_knowledge/services/fap_markdown_parser.dart';
import 'package:se_knowledge/services/obsidian_service.dart';
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

  group('DbService — importFapSyllabus', () {
    test('nhập syllabus tạo môn mới, bản ghi syllabi và đủ 4 bảng chi tiết', () async {
      final res = await DbService.instance.importFapSyllabus(_sampleSyllabus());

      expect(res.subjectCode, 'CSD201');
      expect(res.materialsCount, 2);
      expect(res.closCount, 2);
      expect(res.sessionsCount, 2);
      expect(res.assessmentsCount, 2);

      final db = await DbService.instance.database;

      // Môn học được tự động tạo trong subjects
      final sub = (await db.query('subjects', where: 'code = ?', whereArgs: ['CSD201'])).single;
      expect(sub['name'], contains('Data Structures'));

      // Bản ghi syllabi
      final syl = (await db.query('syllabi', where: 'fap_syllabus_id = ?', whereArgs: [10368])).single;
      expect(syl['subject_id'], sub['id']);
      expect(syl['decision_no'], '1028/QĐ-ĐHFPT');
      expect(syl['scoring_scale'], 10);
      expect(syl['is_approved'], 1);

      // Materials
      final materials = await db.query('materials', where: 'syllabus_id = ?', whereArgs: [res.syllabusId]);
      expect(materials, hasLength(2));
      expect(materials.first['description'], 'Data Structures Book');
      expect(materials.first['is_main'], 1);
      expect(materials.first['is_online'], 1);

      // Learning outcomes
      final clos = await db.query('learning_outcomes', where: 'syllabus_id = ?', whereArgs: [res.syllabusId]);
      expect(clos, hasLength(2));
      expect(clos.map((c) => c['code']).toSet(), {'CLO1', 'CLO2'});

      // Sessions & session_learning_outcomes
      final sessions = await db.query('sessions', where: 'syllabus_id = ?', whereArgs: [res.syllabusId]);
      expect(sessions, hasLength(2));
      final sessLinks = await db.query('session_learning_outcomes');
      // Buổi 1 có 1 CLO, Buổi 2 có 2 CLO => 3 links
      expect(sessLinks, hasLength(3));

      // Assessments & assessment_learning_outcomes
      final assessments = await db.query('assessments', where: 'syllabus_id = ?', whereArgs: [res.syllabusId]);
      expect(assessments, hasLength(2));
      final astLinks = await db.query('assessment_learning_outcomes');
      // Ast 1 có 1 CLO, Ast 2 có 2 CLO => 3 links
      expect(astLinks, hasLength(3));
    });

    test('nhập lại cùng syllabus là upsert, không nhân bản', () async {
      final data = _sampleSyllabus();
      final res1 = await DbService.instance.importFapSyllabus(data);
      final res2 = await DbService.instance.importFapSyllabus(data);

      expect(res2.syllabusId, res1.syllabusId);

      final db = await DbService.instance.database;
      expect(await db.query('subjects'), hasLength(1));
      expect(await db.query('syllabi'), hasLength(1));
      expect(await db.query('materials'), hasLength(2));
      expect(await db.query('learning_outcomes'), hasLength(2));
      expect(await db.query('sessions'), hasLength(2));
      expect(await db.query('assessments'), hasLength(2));
    });

    test('môn đã có từ trước thì syllabus gắn vào môn đó', () async {
      final db = await DbService.instance.database;
      await db.insert('subjects', {
        'code': 'CSD201',
        'name': 'Môn CSD201 từ trước',
        'semester': 3,
        'credits': 3,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final res = await DbService.instance.importFapSyllabus(_sampleSyllabus());
      final syl = (await db.query('syllabi', where: 'id = ?', whereArgs: [res.syllabusId])).single;
      final sub = (await db.query('subjects', where: 'code = ?', whereArgs: ['CSD201'])).single;

      expect(syl['subject_id'], sub['id']);
      expect(await db.query('subjects'), hasLength(1));
    });

    test('importFapCurriculum tự động tạo cạnh tiên quyết và đồng bộ sang curriculums', () async {
      await DbService.instance.importFapCurriculum(
        _curriculum(
          curid: 3005,
          code: 'BIT_SE_K20B',
          subjects: [
            _row('PRO192', semester: 2, credits: 3),
            _row('CSD201', semester: 3, credits: 3, prereq: 'PRO192'),
          ],
        ),
      );

      final db = await DbService.instance.database;
      // 1. Kiểm tra đồng bộ sang curriculums & curriculum_courses
      final legacyCurrs = await db.query('curriculums', where: 'code = ?', whereArgs: ['BIT_SE_K20B']);
      expect(legacyCurrs, hasLength(1));
      final legacyCourses = await db.query('curriculum_courses');
      expect(legacyCourses, hasLength(2));

      // 2. Kiểm tra cạnh tiên quyết (PRO192 -> CSD201)
      final edges = await db.query('prerequisites');
      expect(edges, hasLength(1));
      final proSub = (await db.query('subjects', where: 'code = ?', whereArgs: ['PRO192'])).single;
      final csdSub = (await db.query('subjects', where: 'code = ?', whereArgs: ['CSD201'])).single;
      expect(edges.first['subject_id'], csdSub['id']);
      expect(edges.first['prerequisite_id'], proSub['id']);
    });

    test('importFapSyllabus tự động tạo cạnh tiên quyết nếu môn tiên quyết đã có', () async {
      final db = await DbService.instance.database;
      // Tạo trước môn PRO192
      await db.insert('subjects', {
        'code': 'PRO192',
        'name': 'Object-Oriented Programming',
        'semester': 2,
        'credits': 3,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Nhập Syllabus CSD201 có rawPrerequisiteText = 'PRO192'
      await DbService.instance.importFapSyllabus(_sampleSyllabus(code: 'CSD201'));

      final edges = await db.query('prerequisites');
      expect(edges, hasLength(1));
    });

    test('batchImportFromInbox tự động đọc và nạp toàn bộ file .md trong thư mục', () async {
      // Tạo thư mục tạm giả lập fap_inbox
      final mockInbox = await Directory.systemTemp.createTemp('mock_inbox');
      try {
        final curFile = File('${mockInbox.path}/curriculum.md');
        await curFile.writeAsString('''
Source: https://flm.fpt.edu.vn/gui/role/student/CurriculumDetails?curid=9999
CurriculumCode:
BIT_TEST_K20
Name:
Test Curriculum
Total 2 subjects, 6 credits
Subject Code
Subject Name
Semester
NoCredit
PreRequisite
PR101
[Prog 1](/gui/role/student/Syllabuses?subCode=PR101&curriculumID=9999)
1
3
PR102
[Prog 2](/gui/role/student/Syllabuses?subCode=PR102&curriculumID=9999)
2
3
PR101
''');

        final res = await DbService.instance.batchImportFromInbox(inboxDir: mockInbox);
        expect(res['totalFiles'], 1);
        expect(res['curricula'], 1);
        expect(res['failed'], 0);

        final db = await DbService.instance.database;
        expect(await db.query('curricula'), isNotEmpty);
        expect(await db.query('prerequisites'), hasLength(1));
      } finally {
        await mockInbox.delete(recursive: true);
      }
    });

    // Bản extension mới giữ nguyên bảng Markdown. Trước khi parser biết đọc
    // bảng, cả hai file dưới đây bóc ra rỗng: không môn, không syllabus, và
    // quan trọng nhất là không cạnh tiên quyết nào.
    test('batchImportFromInbox nạp được file .md dạng bảng và nối tiên quyết', () async {
      final mockInbox = await Directory.systemTemp.createTemp('mock_inbox_tbl');
      try {
        await File('${mockInbox.path}/curriculum.md')
            .writeAsString(_curriculumTableMd);
        // Nằm trong thư mục con để kiểm luôn việc quét đệ quy.
        final sub = Directory('${mockInbox.path}/BIT_SE_K19B');
        await sub.create();
        await File('${sub.path}/PRO192c_12288.md')
            .writeAsString(_syllabusTableMd);

        final res = await DbService.instance.batchImportFromInbox(inboxDir: mockInbox);
        expect(res['curricula'], 1);
        expect(res['syllabi'], 1);
        expect(res['failed'], 0);

        final db = await DbService.instance.database;
        final codes = (await db.query('subjects', columns: ['code']))
            .map((r) => r['code'] as String)
            .toList();
        expect(codes, containsAll(['PRF192', 'PRO192C', 'LAB211']));

        final edges = await db.rawQuery('''
          SELECT s.code AS subject, pre.code AS prereq
          FROM prerequisites p
          JOIN subjects s   ON s.id = p.subject_id
          JOIN subjects pre ON pre.id = p.prerequisite_id
        ''');
        final pairs = edges.map((e) => '${e['prereq']}->${e['subject']}').toSet();
        expect(pairs, contains('PRF192->PRO192C'));
        // Khung ghi tiên quyết của LAB211 là "PRO192" nhưng môn trong khung
        // mang mã biến thể "PRO192c" — vẫn phải nối được.
        expect(pairs, contains('PRO192C->LAB211'));
      } finally {
        await mockInbox.delete(recursive: true);
      }
    });

    test('nạp từ Vault: trang FAP thô không đẻ ra môn rác mang tên file', () async {
      final vault = await Directory.systemTemp.createTemp('mock_vault');
      try {
        final fapDir = Directory('${vault.path}/FAP');
        await fapDir.create();
        await File('${fapDir.path}/curriculum.md').writeAsString(_curriculumTableMd);
        await File('${fapDir.path}/PRO192c_12288.md').writeAsString(_syllabusTableMd);

        final plan = await ObsidianService.instance.planImport(vault.path);
        // Cả hai file đều là trang FAP nên không file nào được coi là ghi chú môn.
        expect(plan.fapPages, hasLength(2));
        expect(plan.toCreate, isEmpty);
        expect(plan.isEmpty, isFalse);

        final report = await ObsidianService.instance.applyPlan(plan);
        expect(report.fapPagesImported, 2);

        final db = await DbService.instance.database;
        final codes = (await db.query('subjects', columns: ['code']))
            .map((r) => r['code'] as String)
            .toList();
        expect(codes, containsAll(['PRF192', 'PRO192C']));
        expect(codes, isNot(contains('PRO192C_12288')));
        expect(await db.query('prerequisites'), isNotEmpty);
      } finally {
        await vault.delete(recursive: true);
      }
    });

    group('resolveSubjectCode — mã biến thể', () {
      const codes = {'PRF192': 1, 'PRO192C': 2, 'LAB211': 3};

      test('khớp tuyệt đối được ưu tiên', () {
        expect(DbService.resolveSubjectCode(codes, 'prf192'), 1);
      });

      test('lệch đúng một chữ cái cuối thì vẫn nối', () {
        expect(DbService.resolveSubjectCode(codes, 'PRO192'), 2);
        expect(DbService.resolveSubjectCode({'PRO192': 9}, 'PRO192c'), 9);
      });

      test('nhiều ứng viên thì thà bỏ còn hơn nối bừa', () {
        expect(
          DbService.resolveSubjectCode({'PRO192C': 2, 'PRO192X': 5}, 'PRO192'),
          isNull,
        );
      });

      test('lệch bằng chữ số thì không phải biến thể', () {
        expect(DbService.resolveSubjectCode({'CSI1041': 7}, 'CSI104'), isNull);
      });
    });

    group('Curriculum deletion', () {
      test('deleteCurriculum with deleteSubjects=false preserves subjects but removes curriculum records', () async {
        await DbService.instance.importFapCurriculum(_curriculum(
          curid: 991,
          code: 'TEST_DEL_1',
          subjects: [
            _row('SUB_DEL_1', nameEn: 'Subject 1'),
            _row('SUB_DEL_2', nameEn: 'Subject 2'),
          ],
        ));

        final currs = await DbService.instance.getCurriculums();
        final curr = currs.firstWhere((c) => c['code'] == 'TEST_DEL_1');
        final currId = curr['id'] as int;

        await DbService.instance.deleteCurriculum(currId, deleteSubjects: false);

        final currsAfter = await DbService.instance.getCurriculums();
        expect(currsAfter.any((c) => c['code'] == 'TEST_DEL_1'), isFalse);

        // Curricula FAP table is also cleared
        final db = await DbService.instance.database;
        final fapCurrs = await db.query('curricula', where: 'code = ?', whereArgs: ['TEST_DEL_1']);
        expect(fapCurrs, isEmpty);

        // Subjects still exist
        final sub1 = await db.query('subjects', where: 'code = ?', whereArgs: ['SUB_DEL_1']);
        expect(sub1, isNotEmpty);
      });

      test('deleteCurriculum with deleteSubjects=true deletes orphan subjects', () async {
        await DbService.instance.importFapCurriculum(_curriculum(
          curid: 992,
          code: 'TEST_DEL_2',
          subjects: [
            _row('SUB_ORPHAN_1', nameEn: 'Orphan 1'),
            _row('SUB_SHARED_1', nameEn: 'Shared 1'),
          ],
        ));

        await DbService.instance.importFapCurriculum(_curriculum(
          curid: 993,
          code: 'TEST_DEL_3',
          subjects: [
            _row('SUB_SHARED_1', nameEn: 'Shared 1'),
          ],
        ));

        final currs = await DbService.instance.getCurriculums();
        final curr2 = currs.firstWhere((c) => c['code'] == 'TEST_DEL_2');
        final curr2Id = curr2['id'] as int;

        await DbService.instance.deleteCurriculum(curr2Id, deleteSubjects: true);

        final db = await DbService.instance.database;
        // Orphan subject should be deleted
        final orphan = await db.query('subjects', where: 'code = ?', whereArgs: ['SUB_ORPHAN_1']);
        expect(orphan, isEmpty);

        // Shared subject should still exist
        final shared = await db.query('subjects', where: 'code = ?', whereArgs: ['SUB_SHARED_1']);
        expect(shared, isNotEmpty);
      });
    });

    group('Syllabus retrieval', () {
      test('getSyllabusDetail and getAvailableSyllabi return complete data', () async {
        await DbService.instance.importFapSyllabus(_sampleSyllabus(sylId: 7777, code: 'SWD392'));

        final available = await DbService.instance.getAvailableSyllabi();
        expect(available.any((s) => s['code'] == 'SWD392'), isTrue);

        final detail = await DbService.instance.getSyllabusDetail(subjectCode: 'SWD392');
        expect(detail, isNotNull);
        expect(detail!.subjectCode, 'SWD392');
        expect(detail.materials, hasLength(2));
        expect(detail.clos, hasLength(2));
        expect(detail.sessions, hasLength(2));
        expect(detail.assessments, hasLength(2));
      });
    });
  });
}

FapSyllabusImport _sampleSyllabus({
  int? sylId = 10368,
  String code = 'CSD201',
}) {
  return FapSyllabusImport(
    fapSyllabusId: sylId,
    subjectCode: code,
    nameEn: 'Data Structures and Algorithm',
    nameNative: 'Cấu trúc dữ liệu và giải thuật',
    degreeLevel: 'Bachelor',
    learningTeachingMethod: 'In-class',
    timeAllocation: '45h contact hours',
    description: 'Mô tả môn học $code',
    studentTasks: 'Làm bài tập',
    tools: 'NetBeans, JDK',
    scoringScale: 10,
    decisionNo: '1028/QĐ-ĐHFPT',
    decisionDate: '08/21/2026',
    isApproved: true,
    isScored: true,
    minAvgMarkToPass: 5.0,
    isActive: true,
    approvedDate: '8/21/2026',
    rawPrerequisiteText: 'PRO192',
    sourceUrl: 'https://flm.fpt.edu.vn/gui/role/student/SyllabusDetails?sylID=$sylId',
    materials: const [
      FapMaterialRow(
        seqNo: 1,
        description: 'Data Structures Book',
        author: 'Michael Goodrich',
        publisher: 'Wiley',
        isMain: true,
        isOnline: true,
      ),
      FapMaterialRow(seqNo: 2, description: 'FU slides'),
    ],
    clos: const [
      FapCloRow(code: 'CLO1', detail: 'Chi tiết CLO 1'),
      FapCloRow(code: 'CLO2', detail: 'Chi tiết CLO 2'),
    ],
    sessions: const [
      FapSessionRow(
        sessionNo: 1,
        topic: 'Buổi 1: Giới thiệu',
        teachingType: 'Offline',
        cloCodes: ['CLO1'],
      ),
      FapSessionRow(
        sessionNo: 2,
        topic: 'Buổi 2: Danh sách liên kết',
        teachingType: 'Offline',
        cloCodes: ['CLO1', 'CLO2'],
      ),
    ],
    assessments: const [
      FapAssessmentRow(
        seqNo: 1,
        category: 'Progress test 1',
        type: 'quiz',
        part: 1,
        weightPercent: 20.0,
        completionCriteria: '>0',
        cloCodes: ['CLO1'],
      ),
      FapAssessmentRow(
        seqNo: 2,
        category: 'Final Exam',
        type: 'exam',
        part: 1,
        weightPercent: 30.0,
        completionCriteria: '>0',
        cloCodes: ['CLO1', 'CLO2'],
      ),
    ],
  );
}

/// Trang Curriculum Details như bản extension turndown + plugin GFM sinh ra.
const String _curriculumTableMd = r'''
# Curriculum Details

Source: https://flm.fpt.edu.vn/gui/role/student/CurriculumDetails?curid=1074

| CurriculumCode: | BIT_SE_K19B |
| --- | --- |
| Name: | Bachelor of IT - Software Engineering |

3 subjects, 9 credits

| Subject Code | Subject Name | Semester | NoCredit | Pre-Requisite |
| --- | --- | --- | --- | --- |
| PRF192 | [Programming Fundamentals\_Nhập môn lập trình](/gui/role/student/Syllabuses?subCode=PRF192&curriculumID=1074) | 1 | 3 |  |
| PRO192c | [Object Oriented Programming\_Lập trình hướng đối tượng](/gui/role/student/Syllabuses?subCode=PRO192c&curriculumID=1074) | 2 | 3 | PRF192 |
| LAB211 | [OOP with Java Lab\_Thực hành OOP](/gui/role/student/Syllabuses?subCode=LAB211&curriculumID=1074) | 3 | 3 | PRO192 |
''';

/// Trang Syllabus Details cùng đời extension đó.
const String _syllabusTableMd = r'''
# PRO192c_12288

Source: https://flm.fpt.edu.vn/gui/role/student/SyllabusDetails?sylID=12288

# Syllabus Details

| Syllabus ID: | 12288 |
| --- | --- |
| Syllabus Name: | **Object Oriented Programming with Java\_Lập trình hướng đối tượng với Java** |
| Course Name English: | **Object Oriented Programming with Java** |
| Subject Code: | **PRO192c** |
| NoCredit: | 3 |
| Degree Level: | Bachelor |
| Pre-Requisite: | PRF192 |
| Description: | This course provides the knowledge and skills of OOP. |
| Scoring Scale: | 10 |
| IsApproved: | **True** |
| IsActive: | True |
''';
