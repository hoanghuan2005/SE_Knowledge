import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:se_knowledge/models/curriculum.dart';
import 'package:se_knowledge/models/subject.dart';
import 'package:se_knowledge/services/db_service.dart';
import 'package:se_knowledge/services/obsidian_service.dart';
import 'package:se_knowledge/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Kiểm thử phần "tệp môn học": mỗi khung CTĐT là một thư mục gốc riêng trên
/// thanh bên, nạp khung thứ hai không được đè lên khung thứ nhất.
void main() {
  late Directory tempDir;
  final db = DbService.instance;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();

    tempDir = await Directory.systemTemp.createTemp('se_knowledge_group_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await db.resetAll();
  });

  Future<int> addSubject(String code, {int semester = 1, int credits = 3}) {
    return db.insertSubject(
      Subject.create(
        code: code,
        name: 'Môn $code',
        semester: semester,
        credits: credits,
      ),
    );
  }

  CurriculumGroup groupOf(List<CurriculumGroup> groups, String code) =>
      groups.firstWhere((g) => g.code == code);

  group('ensureCurriculumByCode', () {
    test('tạo mới rồi trả lại đúng id đó ở lần gọi sau', () async {
      final first = await db.ensureCurriculumByCode(code: 'BIT_SE_K19B');
      final second = await db.ensureCurriculumByCode(code: 'BIT_SE_K19B');
      expect(second, first);
    });

    test('không phân biệt hoa thường — tránh đẻ ra tệp trùng tên', () async {
      final upper = await db.ensureCurriculumByCode(code: 'BIT_SE_K19B');
      final lower = await db.ensureCurriculumByCode(code: 'bit_se_k19b');
      expect(lower, upper);

      final rows = await (await db.database).query('curriculums');
      expect(rows, hasLength(1));
      expect(rows.first['code'], 'BIT_SE_K19B');
    });

    test('mã rỗng bị từ chối', () async {
      expect(
        () => db.ensureCurriculumByCode(code: '   '),
        throwsA(isA<DbConflictException>()),
      );
    });
  });

  group('gắn môn vào tệp', () {
    test('gắn lại cùng một môn không nhân đôi và GIỮ kỳ đang có', () async {
      final currId = await db.ensureCurriculumByCode(code: 'A');
      final sid = await addSubject('PRF192');

      final inserted = await db.assignSubjectsToCurriculum(
        curriculumId: currId,
        entries: [CurriculumCourseEntry(subjectId: sid, term: 1, credits: 3)],
      );
      // Người dùng đổi kỳ bằng menu chuột phải...
      await db.setTermOfSubjects(
        curriculumId: currId,
        subjectIds: [sid],
        term: 7,
      );
      // ...rồi nạp lại Vault: file .md vẫn ghi kỳ 1, nhưng không được đè.
      final again = await db.assignSubjectsToCurriculum(
        curriculumId: currId,
        entries: [CurriculumCourseEntry(subjectId: sid, term: 1, credits: 3)],
      );

      expect(inserted, 1);
      expect(again, 0, reason: 'lần hai không chèn thêm dòng nào');

      final rows = await (await db.database).query('curriculum_courses');
      expect(rows, hasLength(1));
      expect(rows.first['term'], 7, reason: 'kỳ người dùng tự sửa phải còn');
    });

    test('overwriteExisting = true thì nguồn có thẩm quyền được đè kỳ', () async {
      final currId = await db.ensureCurriculumByCode(code: 'A');
      final sid = await addSubject('PRF192');
      await db.assignSubjectsToCurriculum(
        curriculumId: currId,
        entries: [CurriculumCourseEntry(subjectId: sid, term: 1, credits: 3)],
      );

      await db.assignSubjectsToCurriculum(
        curriculumId: currId,
        entries: [CurriculumCourseEntry(subjectId: sid, term: 4, credits: 5)],
        overwriteExisting: true,
      );

      final rows = await (await db.database).query('curriculum_courses');
      expect(rows, hasLength(1));
      expect(rows.first['term'], 4);
      expect(rows.first['credits'], 5);
    });

    test(
      'cùng một môn nằm trong hai tệp với hai kỳ khác nhau, không đè nhau',
      () async {
        final a = await db.ensureCurriculumByCode(code: 'BIT_SE_K19B');
        final b = await db.ensureCurriculumByCode(code: 'BIT_IS_K20D');
        final sid = await addSubject('MAD101');

        await db.assignSubjectsToCurriculum(
          curriculumId: a,
          entries: [CurriculumCourseEntry(subjectId: sid, term: 1)],
        );
        await db.assignSubjectsToCurriculum(
          curriculumId: b,
          entries: [CurriculumCourseEntry(subjectId: sid, term: 3)],
        );

        final tree = await db.getCurriculumTreeData();
        expect(groupOf(tree, 'BIT_SE_K19B').semesters.keys, [1]);
        expect(groupOf(tree, 'BIT_IS_K20D').semesters.keys, [3]);
        // Môn gốc chỉ có một bản ghi duy nhất trong `subjects`.
        expect(await db.getSubjects(), hasLength(1));
      },
    );

    test('môn chưa gắn tệp nào rơi vào nhóm "Môn ngoài khung"', () async {
      await addSubject('LAC101', semester: 2);
      final tree = await db.getCurriculumTreeData();

      final other = groupOf(tree, 'OTHER');
      expect(other.isUnassigned, isTrue);
      expect(other.semesters[2]!.single.code, 'LAC101');
    });
  });

  group('gỡ và chuyển môn giữa các tệp', () {
    test('gỡ khỏi tệp thì môn về nhóm ngoài khung, KHÔNG bị xoá', () async {
      final currId = await db.ensureCurriculumByCode(code: 'A');
      final sid = await addSubject('CSD201', semester: 2);
      await db.assignSubjectsToCurriculum(
        curriculumId: currId,
        entries: [CurriculumCourseEntry(subjectId: sid, term: 2)],
      );

      final removed = await db.removeSubjectsFromCurriculum(
        curriculumId: currId,
        subjectIds: [sid],
      );

      expect(removed, 1);
      expect(await db.getSubjectByCode('CSD201'), isNotNull);

      final tree = await db.getCurriculumTreeData();
      expect(groupOf(tree, 'A').totalSubjects, 0);
      expect(groupOf(tree, 'OTHER').semesters[2]!.single.code, 'CSD201');
    });

    test('chuyển tệp giữ nguyên kỳ và tín chỉ của tệp nguồn', () async {
      final a = await db.ensureCurriculumByCode(code: 'A');
      final b = await db.ensureCurriculumByCode(code: 'B');
      final sid = await addSubject('DBI202');
      await db.assignSubjectsToCurriculum(
        curriculumId: a,
        entries: [CurriculumCourseEntry(subjectId: sid, term: 5, credits: 4)],
      );

      await db.moveSubjectsToCurriculum(
        fromCurriculumId: a,
        toCurriculumId: b,
        subjectIds: [sid],
      );

      final tree = await db.getCurriculumTreeData();
      expect(groupOf(tree, 'A').totalSubjects, 0);
      expect(groupOf(tree, 'B').semesters[5]!.single.code, 'DBI202');

      final rows = await (await db.database).query(
        'curriculum_courses',
        where: 'curriculum_id = ?',
        whereArgs: [b],
      );
      expect(rows.single['credits'], 4);
    });

    test('chuyển từ nhóm ngoài khung thì lấy kỳ từ bảng subjects', () async {
      final b = await db.ensureCurriculumByCode(code: 'B');
      final sid = await addSubject('PRJ301', semester: 6, credits: 2);

      await db.moveSubjectsToCurriculum(toCurriculumId: b, subjectIds: [sid]);

      final tree = await db.getCurriculumTreeData();
      expect(groupOf(tree, 'B').semesters[6]!.single.code, 'PRJ301');
    });

    test('chuyển vào tệp đã chứa môn đó thì gộp làm một dòng', () async {
      final a = await db.ensureCurriculumByCode(code: 'A');
      final b = await db.ensureCurriculumByCode(code: 'B');
      final sid = await addSubject('SWR302');
      await db.assignSubjectsToCurriculum(
        curriculumId: a,
        entries: [CurriculumCourseEntry(subjectId: sid, term: 2)],
      );
      await db.assignSubjectsToCurriculum(
        curriculumId: b,
        entries: [CurriculumCourseEntry(subjectId: sid, term: 8)],
      );

      await db.moveSubjectsToCurriculum(
        fromCurriculumId: a,
        toCurriculumId: b,
        subjectIds: [sid],
      );

      final rows = await (await db.database).query(
        'curriculum_courses',
        where: 'curriculum_id = ?',
        whereArgs: [b],
      );
      expect(rows, hasLength(1));
      expect(rows.single['term'], 2, reason: 'kỳ của tệp nguồn thắng');
    });
  });

  group('đổi kỳ', () {
    test('đổi kỳ trong một tệp không đụng tới kỳ của tệp khác', () async {
      final a = await db.ensureCurriculumByCode(code: 'A');
      final b = await db.ensureCurriculumByCode(code: 'B');
      final sid = await addSubject('MAD101', semester: 1);
      await db.assignSubjectsToCurriculum(
        curriculumId: a,
        entries: [CurriculumCourseEntry(subjectId: sid, term: 1)],
      );
      await db.assignSubjectsToCurriculum(
        curriculumId: b,
        entries: [CurriculumCourseEntry(subjectId: sid, term: 1)],
      );

      await db.setTermOfSubjects(curriculumId: a, subjectIds: [sid], term: 9);

      final tree = await db.getCurriculumTreeData();
      expect(groupOf(tree, 'A').semesters.keys, [9]);
      expect(groupOf(tree, 'B').semesters.keys, [1]);
      // Kỳ gốc trong bảng subjects không bị đụng.
      expect((await db.getSubjectByCode('MAD101'))!.semester, 1);
    });

    test('môn ngoài khung thì đổi thẳng subjects.semester', () async {
      final sid = await addSubject('OTP101', semester: 1);
      await db.setTermOfSubjects(subjectIds: [sid], term: 3);
      expect((await db.getSubjectByCode('OTP101'))!.semester, 3);
    });
  });

  group('đổi tên tệp môn học', () {
    test('đổi mã kéo theo hàng song song bên curricula, không mọc tệp ma', () async {
      // Dựng đúng trạng thái sau một lần nhập FAP: có cả hai hàng cùng mã.
      final currId = await db.ensureCurriculumByCode(code: 'BIT_SE_K19B');
      final sid = await addSubject('PRF192');
      await db.assignSubjectsToCurriculum(
        curriculumId: currId,
        entries: [CurriculumCourseEntry(subjectId: sid, term: 1)],
      );
      await db.upsertCurriculum(
        fapCurriculumId: 2951,
        code: 'BIT_SE_K19B',
        nameEn: 'SE K19B',
      );

      await db.updateCurriculum(currId, code: 'BIT_SE_K19B_V2');

      // Lần dựng cây kế tiếp là nơi tệp ma sẽ xuất hiện nếu hai bảng lệch mã.
      final tree = await db.getCurriculumTreeData();
      final codes = tree.map((g) => g.code).toList();
      expect(codes, contains('BIT_SE_K19B_V2'));
      expect(codes, isNot(contains('BIT_SE_K19B')));
      expect(groupOf(tree, 'BIT_SE_K19B_V2').totalSubjects, 1);

      final fap = await (await db.database).query('curricula');
      expect(fap.single['code'], 'BIT_SE_K19B_V2');
    });

    test('đổi sang mã đã có tệp khác dùng thì báo lỗi tử tế', () async {
      final a = await db.ensureCurriculumByCode(code: 'AAA');
      await db.ensureCurriculumByCode(code: 'BBB');

      expect(
        () => db.updateCurriculum(a, code: 'bbb'),
        throwsA(isA<DbConflictException>()),
      );
      // Không được sửa dở dang: AAA vẫn nguyên.
      expect((await db.getCurriculumById(a))!['code'], 'AAA');
    });

    test('đổi tên mà giữ nguyên mã thì không sao', () async {
      final a = await db.ensureCurriculumByCode(code: 'AAA');
      await db.updateCurriculum(a, code: 'AAA', name: 'Tên mới');
      final row = await db.getCurriculumById(a);
      expect(row!['code'], 'AAA');
      expect(row['name'], 'Tên mới');
    });
  });

  group('bộ lọc khung trên Bản đồ tri thức không được trỏ vào mã đã biến mất', () {
    // DropdownButton khẳng định có đúng một item khớp `value`; trỏ vào một mã
    // không còn trong `curriculumGroups` là cả trang Bản đồ thành ô báo lỗi.
    final state = AppState.instance;

    test('đổi mã tệp đang lọc thì bộ lọc tự hạ về "Tất cả khung"', () async {
      final id = await db.ensureCurriculumByCode(code: 'BIT_SE_K19B');
      final sid = await addSubject('PRF192');
      await db.assignSubjectsToCurriculum(
        curriculumId: id,
        entries: [CurriculumCourseEntry(subjectId: sid, term: 1)],
      );
      await state.refresh();
      state.setActiveCurriculum('BIT_SE_K19B');

      await state.updateCurriculum(id, code: 'BIT_SE_K19B_V2');

      expect(state.activeCurriculumCode, isNull);
      expect(
        state.curriculumGroups.any((g) => g.code == 'BIT_SE_K19B_V2'),
        isTrue,
      );
    });

    test('gom hết môn ngoài khung thì bộ lọc "OTHER" cũng được hạ xuống', () async {
      final id = await db.ensureCurriculumByCode(code: 'A');
      final sid = await addSubject('LAC101');
      await state.refresh();
      state.setActiveCurriculum('OTHER');
      expect(state.curriculumGroups.any((g) => g.code == 'OTHER'), isTrue);

      await state.moveSubjectsToCurriculum(
        toCurriculumId: id,
        subjectIds: [sid],
      );

      expect(state.curriculumGroups.any((g) => g.code == 'OTHER'), isFalse);
      expect(state.activeCurriculumCode, isNull);
    });

    test('xoá tệp đang lọc cũng hạ bộ lọc xuống', () async {
      final id = await db.ensureCurriculumByCode(code: 'SAPXOA');
      await state.refresh();
      state.setActiveCurriculum('SAPXOA');

      await state.deleteCurriculum(id);

      expect(state.activeCurriculumCode, isNull);
    });

    test('lọc theo nhóm ngoài khung chỉ ra đúng môn chưa xếp', () async {
      final id = await db.ensureCurriculumByCode(code: 'A');
      final inside = await addSubject('PRF192');
      await addSubject('CACHCHOIYUGIOH');
      await db.assignSubjectsToCurriculum(
        curriculumId: id,
        entries: [CurriculumCourseEntry(subjectId: inside, term: 1)],
      );
      await state.refresh();

      state.setActiveCurriculum('OTHER');
      expect(
        state.currentGraph.subjects.map((s) => s.code),
        ['CACHCHOIYUGIOH'],
      );
    });
  });

  test('tệp môn học rỗng vẫn là một nhóm trong cây', () async {
    await db.ensureCurriculumByCode(code: 'RONG');
    final tree = await db.getCurriculumTreeData();
    final group = groupOf(tree, 'RONG');
    expect(group.totalSubjects, 0);
    expect(group.semesters, isEmpty);
  });

  test('curriculumCodesBySubjectId liệt kê mọi tệp của từng môn', () async {
    final a = await db.ensureCurriculumByCode(code: 'AAA');
    final b = await db.ensureCurriculumByCode(code: 'BBB');
    final sid = await addSubject('PRF192');
    await db.assignSubjectsToCurriculum(
      curriculumId: a,
      entries: [CurriculumCourseEntry(subjectId: sid)],
    );
    await db.assignSubjectsToCurriculum(
      curriculumId: b,
      entries: [CurriculumCourseEntry(subjectId: sid)],
    );

    expect(await db.curriculumCodesBySubjectId(), {
      sid: ['AAA', 'BBB'],
    });
  });

  // ------------------------------------------------------------------
  // VAULT: phạm vi quét + tệp đích + vòng đời front matter `curriculum:`
  // ------------------------------------------------------------------

  group('nạp Vault vào một tệp môn học', () {
    late Directory vault;
    final vaultService = ObsidianService.instance;

    setUp(() async {
      vault = await Directory(p.join(tempDir.path, 'vault'))
          .create(recursive: true);
      // Xoá sạch giữa các bài test để file của bài trước không lẫn sang.
      await for (final e in vault.list()) {
        await e.delete(recursive: true);
      }
    });

    Future<void> writeNote(
      String relativePath,
      String code, {
      int semester = 1,
      String? curriculum,
    }) async {
      final file = File(p.join(vault.path, relativePath));
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '---\n'
        'code: $code\n'
        'name: "Môn $code"\n'
        'semester: $semester\n'
        'credits: 3\n'
        '${curriculum == null ? '' : 'curriculum: [$curriculum]\n'}'
        '---\n\n'
        '# $code\n',
      );
    }

    /// Một trang "Syllabus Details" như extension FAP lưu ra: không front
    /// matter, mã môn nằm trong bảng chứ không ở tên file.
    Future<void> writeSyllabus(
      String relativePath,
      String code,
      int sylId,
    ) async {
      final file = File(p.join(vault.path, relativePath));
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '# ${p.basenameWithoutExtension(relativePath)}\n\n'
        'Source: https://flm.fpt.edu.vn/gui/role/student/SyllabusDetails?sylID=$sylId\n\n'
        '# Syllabus Details\n\n'
        '| Syllabus ID: | $sylId |\n'
        '| --- | --- |\n'
        '| Syllabus Name: | **Môn $code** |\n'
        '| Course Name English: | **Môn $code** |\n'
        '| Subject Code: | **$code** |\n'
        '| NoCredit: | 3 |\n'
        '| Degree Level: | Bachelor |\n'
        '| Pre-Requisite: | None |\n'
        '| Description: | Mô tả môn $code. |\n'
        '| Scoring Scale: | 10 |\n'
        '| IsActive: | True |\n',
      );
    }

    test('quét giới hạn trong một thư mục con', () async {
      await writeNote('ghi-chu-ca-nhan.md', 'CACHCHOI');
      await writeNote('FAP/PRF192.md', 'PRF192');
      await writeNote('FAP/MAD101.md', 'MAD101');

      final all = await vaultService.planImport(vault.path);
      final scoped = await vaultService.planImport(
        vault.path,
        subFolder: 'FAP',
      );

      expect(all.notes, hasLength(3));
      expect(scoped.notes.map((n) => n.code), ['MAD101', 'PRF192']);
      expect(scoped.subFolder, 'FAP');
    });

    test('nạp kèm tệp đích thì môn vào đúng tệp đó', () async {
      await writeNote('FAP/PRF192.md', 'PRF192', semester: 1);
      await writeNote('FAP/PRJ301.md', 'PRJ301', semester: 3);

      final plan = await vaultService.planImport(vault.path, subFolder: 'FAP');
      final report = await vaultService.applyPlan(
        plan,
        target: const VaultImportTarget.create('BIT_SE_K19B'),
      );

      expect(report.curriculumCode, 'BIT_SE_K19B');
      expect(report.subjectsAssigned, 2);

      final tree = await db.getCurriculumTreeData();
      final group = groupOf(tree, 'BIT_SE_K19B');
      expect(group.totalSubjects, 2);
      expect(group.semesters[1]!.single.code, 'PRF192');
      expect(group.semesters[3]!.single.code, 'PRJ301');
    });

    test('nạp lại KHÔNG đè kỳ người dùng đã tự sửa, trừ khi tích ô ghi đè', () async {
      await writeNote('FAP/PRF192.md', 'PRF192', semester: 1);
      await vaultService.applyPlan(
        await vaultService.planImport(vault.path, subFolder: 'FAP'),
        target: const VaultImportTarget.create('BIT_SE_K19B'),
      );
      final currId = (await db.getCurriculums()).single['id'] as int;
      final sid = (await db.getSubjectByCode('PRF192'))!.id!;

      await db.setTermOfSubjects(
        curriculumId: currId,
        subjectIds: [sid],
        term: 5,
      );

      // Nạp lại: file vẫn ghi kỳ 1 nhưng kỳ 5 phải còn.
      await vaultService.applyPlan(
        await vaultService.planImport(vault.path, subFolder: 'FAP'),
        target: VaultImportTarget.existing(currId),
      );
      expect(groupOf(await db.getCurriculumTreeData(), 'BIT_SE_K19B')
          .semesters.keys, [5]);

      // Tích ô "ghi đè" thì file mới có quyền kéo về kỳ 1.
      await vaultService.applyPlan(
        await vaultService.planImport(vault.path, subFolder: 'FAP'),
        target: VaultImportTarget.existing(currId, overwriteTerms: true),
      );
      expect(groupOf(await db.getCurriculumTreeData(), 'BIT_SE_K19B')
          .semesters.keys, [1]);
    });

    test('hai lượt quét vào hai tệp thì không trộn vào nhau', () async {
      await writeNote('SE/PRF192.md', 'PRF192', semester: 1);
      await writeNote('SE/SWR302.md', 'SWR302', semester: 4);
      await writeNote('IS/PRF192.md', 'PRF192', semester: 2);
      await writeNote('IS/IOT102.md', 'IOT102', semester: 5);

      await vaultService.applyPlan(
        await vaultService.planImport(vault.path, subFolder: 'SE'),
        target: const VaultImportTarget.create('BIT_SE_K19B'),
      );
      await vaultService.applyPlan(
        await vaultService.planImport(vault.path, subFolder: 'IS'),
        target: const VaultImportTarget.create('BIT_IS_K20D'),
      );

      final tree = await db.getCurriculumTreeData();
      final se = groupOf(tree, 'BIT_SE_K19B');
      final is_ = groupOf(tree, 'BIT_IS_K20D');

      expect(se.semesters.keys.toList()..sort(), [1, 4]);
      expect(is_.semesters.keys.toList()..sort(), [2, 5]);
      // PRF192 dùng chung: một bản ghi môn, hai dòng trong bảng nối.
      expect(await db.getSubjects(), hasLength(3));
    });

    test('không chọn tệp nào thì giữ hành vi cũ: môn ngoài khung', () async {
      await writeNote('PRF192.md', 'PRF192');

      final report = await vaultService.applyPlan(
        await vaultService.planImport(vault.path),
      );

      expect(report.curriculumCode, isEmpty);
      final tree = await db.getCurriculumTreeData();
      expect(groupOf(tree, 'OTHER').totalSubjects, 1);
    });

    // Thư mục mà extension FAP lưu ra thường chỉ toàn Syllabus Details, không
    // kèm trang Curriculum Details nào. Những trang đó đi đường `fapPages` chứ
    // không thành [ObsidianNote], nên trước đây chúng rơi khỏi bước xếp môn vào
    // tệp: tệp dựng ra rỗng trơn còn môn thì dồn hết vào "Môn ngoài khung".
    test('thư mục chỉ có Syllabus Details vẫn xếp môn vào tệp đích', () async {
      await writeSyllabus('CEA201_13245.md', 'CEA201', 13245);
      await writeSyllabus('PRF192_12223.md', 'PRF192', 12223);

      final report = await vaultService.applyPlan(
        await vaultService.planImport(vault.path),
        target: const VaultImportTarget.create('BIT_SE_K17B'),
      );

      expect(report.fapPagesImported, 2);
      expect(report.curriculumCode, 'BIT_SE_K17B');
      expect(report.subjectsAssigned, 2);

      final tree = await db.getCurriculumTreeData();
      final k17b = groupOf(tree, 'BIT_SE_K17B');
      expect(k17b.totalSubjects, 2);
      expect(
        [for (final list in k17b.semesters.values) ...list.map((s) => s.code)]
          ..sort(),
        ['CEA201', 'PRF192'],
      );
      // Không còn môn nào lạc ra nhóm ngoài khung.
      expect(tree.any((g) => g.code == 'OTHER'), isFalse);
    });

    test('nạp lại cùng thư mục syllabus không nhân đôi dòng trong tệp', () async {
      await writeSyllabus('CEA201_13245.md', 'CEA201', 13245);

      for (var i = 0; i < 2; i++) {
        await vaultService.applyPlan(
          await vaultService.planImport(vault.path),
          target: const VaultImportTarget.create('BIT_SE_K17B'),
        );
      }

      final tree = await db.getCurriculumTreeData();
      expect(groupOf(tree, 'BIT_SE_K17B').totalSubjects, 1);
    });

    test(
      'lấy mã khung từ trang Curriculum Details mà extension lưu lại',
      () async {
        // Trang này là thứ extension FAP lưu kèm mỗi lượt quét; nó ghi thẳng mã
        // khung nên phải được ưu tiên hơn mọi gợi ý suy đoán khác.
        await Directory(p.join(vault.path, 'FAP')).create(recursive: true);
        await File(p.join(vault.path, 'FAP', 'Curriculum Details.md'))
            .writeAsString(
              'Source: https://flm.fpt.edu.vn/gui/role/student/CurriculumDetails?curid=2951\n\n'
              '# Curriculum Details\n\n'
              'CurriculumCode:\n\n'
              'BIT\\_SE\\_K19B\n\n'
              'Name:\n\n'
              'Software Engineering\n',
            );
        await writeNote('FAP/PRF192.md', 'PRF192', curriculum: 'CU_CU');

        final plan = await vaultService.planImport(
          vault.path,
          subFolder: 'FAP',
        );
        expect(plan.detectedCurriculumCodes.first, 'BIT_SE_K19B');
        expect(plan.detectedCurriculumCodes, contains('CU_CU'));
      },
    );

    test('ghi ra Vault đóng dấu curriculum: để lần nạp sau nhận lại', () async {
      await writeNote('FAP/PRF192.md', 'PRF192');
      await vaultService.applyPlan(
        await vaultService.planImport(vault.path, subFolder: 'FAP'),
        target: const VaultImportTarget.create('BIT_SE_K19B'),
      );

      final subject = await db.getSubjectByCode('PRF192');
      await vaultService.exportSubjects(vault.path, [subject!]);

      final raw = await File(p.join(vault.path, 'FAP', 'PRF192.md'))
          .readAsString();
      expect(raw, contains('curriculum: [BIT_SE_K19B]'));

      // Lần nạp sau đọc lại được mã đó làm gợi ý tệp đích.
      final plan = await vaultService.planImport(vault.path, subFolder: 'FAP');
      expect(plan.detectedCurriculumCodes, ['BIT_SE_K19B']);
    });

    test('ghi ra Vault chỉ một nhóm môn, không đụng môn khác', () async {
      await writeNote('PRF192.md', 'PRF192');
      await writeNote('MAD101.md', 'MAD101');
      await vaultService.applyPlan(await vaultService.planImport(vault.path));

      final prf = await db.getSubjectByCode('PRF192');
      final written = await vaultService.exportSubjects(vault.path, [prf!]);

      expect(written, 1);
      // Không sinh file chỉ mục khi ghi cục bộ.
      expect(await File(p.join(vault.path, '_INDEX.md')).exists(), isFalse);
    });
  });
}
