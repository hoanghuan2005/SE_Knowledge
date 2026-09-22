import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/graph_data.dart';
import '../models/prerequisite.dart';
import '../models/subject.dart';
import 'db_service.dart';
import 'fap_markdown_parser.dart';
import 'markdown_parser.dart';

/// Một file `.md` đã được đọc và bóc tách từ Obsidian Vault.
class ObsidianNote {
  final String filePath;
  final String fileName;
  final Map<String, String> frontMatter;
  final String body;

  /// Mọi `[[...]]` trong file, kèm vị trí và section cha.
  /// Tầng giao diện dùng trực tiếp để vẽ nút bấm và bắt sự kiện click.
  final List<WikiLink> links;

  /// Mọi `#tag`, gộp cả tag khai báo trong front matter lẫn tag viết trong body.
  final List<MdTag> tags;

  const ObsidianNote({
    required this.filePath,
    required this.fileName,
    required this.frontMatter,
    required this.body,
    required this.links,
    required this.tags,
  });

  /// Mọi `[[...]]` xuất hiện trong file, dạng danh sách chuỗi không trùng lặp.
  List<String> get allLinks {
    final seen = <String>{};
    return [
      for (final l in links)
        if (seen.add(l.target)) l.target,
    ];
  }

  /// Chỉ các `[[...]]` nằm dưới mục "Môn tiên quyết".
  List<String> get prerequisiteLinks {
    final seen = <String>{};
    return [
      for (final l in links)
        if (l.isPrerequisite && seen.add(l.target)) l.target,
    ];
  }

  /// Mã môn của các liên kết tiên quyết, đã chuẩn hoá chữ hoa.
  List<String> get prerequisiteCodes =>
      prerequisiteLinks.map((e) => e.toUpperCase()).toList();

  /// Tên tag không trùng lặp, dùng cho bộ lọc theo thẻ trên giao diện.
  List<String> get tagNames {
    final seen = <String>{};
    return [
      for (final t in tags)
        if (seen.add(t.name)) t.name,
    ];
  }

  /// Mã môn: ưu tiên front matter `code`, không có thì lấy tên file.
  String get code => (frontMatter['code']?.trim().isNotEmpty ?? false)
      ? frontMatter['code']!.trim().toUpperCase()
      : p.basenameWithoutExtension(fileName).trim().toUpperCase();

  String get name => frontMatter['name']?.trim().isNotEmpty ?? false
      ? frontMatter['name']!.trim()
      : p.basenameWithoutExtension(fileName);

  int get semester => int.tryParse(frontMatter['semester'] ?? '') ?? 1;
  int get credits => int.tryParse(frontMatter['credits'] ?? '') ?? 3;

  /// Mã các "tệp môn học" (khung CTĐT) mà file này tự khai trong front matter
  /// `curriculum: [BIT_SE_K19B]`. App ghi khoá này khi xuất ra Vault, nên nạp
  /// lại một Vault đã xuất sẽ tự rơi đúng về tệp cũ thay vì dồn hết một chỗ.
  List<String> get curriculumCodes => MarkdownParser.parseListValue(
    frontMatter['curriculum'] ?? frontMatter['curriculums'],
  ).map((e) => e.trim().toUpperCase()).where((e) => e.isNotEmpty).toList();

  /// Đoạn mô tả: dòng văn bản đầu tiên không phải heading / bullet / link.
  String get description {
    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) continue;
      if (line.startsWith('-') || line.startsWith('*')) continue;
      if (line.startsWith('>')) continue;
      return line;
    }
    return '';
  }

  /// Chuyển thành model môn học để ghi xuống SQLite.
  Subject toSubject() => Subject.create(
    code: code,
    name: name,
    semester: semester,
    credits: credits,
    description: description,
    notePath: filePath,
  );
}

/// Một cạnh sẽ được thêm hoặc gỡ khi đồng bộ, mô tả bằng mã môn.
class EdgeChange {
  final String subjectCode;
  final String prerequisiteCode;

  const EdgeChange({required this.subjectCode, required this.prerequisiteCode});

  @override
  String toString() => '$prerequisiteCode -> $subjectCode';
}

/// Một thư mục con của Vault kèm số file `.md` bên trong — dùng để người dùng
/// chọn "chỉ nạp thư mục này" thay vì nuốt trọn cả Vault.
class VaultFolderOption {
  /// Đường dẫn tương đối so với gốc Vault. Rỗng = toàn bộ Vault.
  final String relativePath;
  final int mdCount;

  const VaultFolderOption({required this.relativePath, required this.mdCount});

  bool get isRoot => relativePath.isEmpty;
  String get label => isRoot ? 'Toàn bộ Vault' : relativePath;
}

/// "Nạp vào tệp môn học nào" — lựa chọn người dùng chốt trước khi ghi xuống.
///
/// Đây là mấu chốt của việc tách nhỏ: không có nó thì mọi lần nạp đều đổ chung
/// vào một rổ và cây thư mục chỉ còn gom được theo số kỳ.
class VaultImportTarget {
  /// Gắn vào một tệp môn học đã có (`curriculums.id`).
  final int? existingCurriculumId;

  /// Tạo tệp môn học mới với mã này.
  final String? newCode;
  final String? newName;

  /// Cho phép kỳ ghi trong file `.md` ghi đè kỳ môn đang có trong tệp này.
  ///
  /// Mặc định `false`: front matter chỉ có một khoá `semester` dùng chung cho
  /// mọi tệp, nên nó không diễn tả được kỳ riêng của từng tệp — để nó ghi đè
  /// thì mọi lần sửa bằng "Đổi kỳ…" đều bị nuốt sau một lần nạp lại. Bật lên
  /// khi file `.md` mới là nguồn đáng tin (vừa quét lại khung từ FAP).
  final bool overwriteTerms;

  const VaultImportTarget._({
    this.existingCurriculumId,
    this.newCode,
    this.newName,
    this.overwriteTerms = false,
  });

  /// Không gắn vào tệp nào — môn rơi vào nhóm "Môn ngoài khung".
  const VaultImportTarget.unassigned() : this._();

  const VaultImportTarget.existing(
    int curriculumId, {
    bool overwriteTerms = false,
  }) : this._(
         existingCurriculumId: curriculumId,
         overwriteTerms: overwriteTerms,
       );

  const VaultImportTarget.create(
    String code, {
    String? name,
    bool overwriteTerms = false,
  }) : this._(newCode: code, newName: name, overwriteTerms: overwriteTerms);

  bool get isUnassigned => existingCurriculumId == null && newCode == null;
}

/// Bản kế hoạch đồng bộ Vault -> SQLite, dựng ra **trước** khi ghi bất cứ thứ
/// gì. Giao diện đổ thẳng dữ liệu này vào hộp thoại xác nhận.
class VaultSyncPlan {
  final String vaultPath;

  /// Thư mục con đang được quét (tương đối so với gốc Vault). Rỗng = cả Vault.
  final String subFolder;

  final List<ObsidianNote> notes;

  /// Môn có trong Vault nhưng chưa có trong CSDL.
  final List<ObsidianNote> toCreate;

  /// Môn đã có nhưng nội dung file khác với CSDL.
  final List<ObsidianNote> toUpdate;

  /// Môn không đổi gì, bỏ qua khi ghi.
  final List<ObsidianNote> unchanged;

  final List<EdgeChange> edgesToAdd;

  /// Cạnh còn trong CSDL nhưng người dùng đã xoá `[[...]]` khỏi file `.md`.
  final List<EdgeChange> edgesToRemove;

  /// `[[...]]` không trỏ tới file nào trong Vault.
  final List<String> brokenLinks;

  /// Môn có trong CSDL nhưng không còn file `.md` nào tương ứng.
  /// Chỉ báo cáo, không bao giờ tự xoá.
  final List<Subject> missingInVault;

  /// Mã tệp môn học đọc được từ front matter `curriculum:` của các file đang
  /// quét. Hộp thoại dùng làm gợi ý mặc định cho ô "Tạo tệp mới".
  final List<String> detectedCurriculumCodes;

  /// Trang FAP thô (Curriculum/Syllabus Details) nằm trong phạm vi quét.
  ///
  /// Chúng KHÔNG phải ghi chú môn học: không có front matter, mã môn nằm trong
  /// bảng chứ không nằm ở tên file (`PRO192c_12288.md`), và quan hệ tiên quyết
  /// nằm ở ô "Pre-Requisite" chứ không ở `[[...]]`. Nếu để lẫn vào [notes] thì
  /// mỗi file đẻ ra một môn rác mang mã bằng tên file. Vì vậy chúng được tách
  /// riêng và [ObsidianService.applyPlan] nạp bằng [FapMarkdownParser].
  final List<ObsidianNote> fapPages;

  const VaultSyncPlan({
    required this.vaultPath,
    this.subFolder = '',
    required this.notes,
    required this.toCreate,
    required this.toUpdate,
    required this.unchanged,
    required this.edgesToAdd,
    required this.edgesToRemove,
    required this.brokenLinks,
    required this.missingInVault,
    this.detectedCurriculumCodes = const [],
    this.fapPages = const [],
  });

  /// Mọi môn mà lần nạp này đụng tới — chính là tập sẽ được gắn vào tệp đích.
  List<ObsidianNote> get allNotes => [...toCreate, ...toUpdate, ...unchanged];

  /// Không có gì thay đổi thì khỏi cần hỏi người dùng.
  bool get isEmpty =>
      toCreate.isEmpty &&
      toUpdate.isEmpty &&
      edgesToAdd.isEmpty &&
      edgesToRemove.isEmpty &&
      fapPages.isEmpty;

  /// Có thao tác nào gây mất dữ liệu không — dùng để tô màu cảnh báo.
  bool get hasRemovals => edgesToRemove.isNotEmpty;

  String get summary {
    final sb = StringBuffer()
      ..write('Quét ${notes.length} file .md: thêm ${toCreate.length} môn, ')
      ..write('cập nhật ${toUpdate.length} môn, ')
      ..write('giữ nguyên ${unchanged.length} môn, ')
      ..write('thêm ${edgesToAdd.length} liên kết, ')
      ..write('gỡ ${edgesToRemove.length} liên kết.');
    if (fapPages.isNotEmpty) {
      sb.write(
        ' Kèm ${fapPages.length} trang FAP thô sẽ được nạp bằng bộ đọc FAP '
        '(môn, syllabus và cạnh tiên quyết lấy từ cột Pre-Requisite).',
      );
    }
    return sb.toString();
  }
}

/// Kết quả một lần đồng bộ Vault -> SQLite.
class VaultSyncReport {
  final int filesScanned;
  final int subjectsCreated;
  final int subjectsUpdated;
  final int edgesCreated;
  final int edgesRemoved;
  final List<String> warnings;

  /// Mã tệp môn học mà lần nạp này gắn các môn vào. Rỗng = để ngoài khung.
  final String curriculumCode;

  /// Số môn được gắn vào tệp đó.
  final int subjectsAssigned;

  /// Số trang FAP thô (Curriculum/Syllabus Details) đã nạp trong lượt này.
  final int fapPagesImported;

  const VaultSyncReport({
    required this.filesScanned,
    required this.subjectsCreated,
    required this.subjectsUpdated,
    required this.edgesCreated,
    this.edgesRemoved = 0,
    required this.warnings,
    this.curriculumCode = '',
    this.subjectsAssigned = 0,
    this.fapPagesImported = 0,
  });

  String get summary {
    final sb = StringBuffer()
      ..write('Đã quét $filesScanned file .md — ')
      ..write('tạo mới $subjectsCreated môn, ')
      ..write('cập nhật $subjectsUpdated môn, ')
      ..write('thêm $edgesCreated liên kết');
    if (edgesRemoved > 0) {
      sb.write(', gỡ $edgesRemoved liên kết không còn trong Vault');
    }
    if (curriculumCode.isNotEmpty) {
      sb.write(', xếp $subjectsAssigned môn vào tệp "$curriculumCode"');
    }
    if (fapPagesImported > 0) {
      sb.write(', nạp $fapPagesImported trang FAP');
    }
    sb.write('.');
    return sb.toString();
  }
}

/// Một file `.md` cũ sẽ được dời chỗ vì lần ghi này đổi thư mục đích.
///
/// Đổi thư mục mà KHÔNG dời file cũ thì mỗi môn thành hai file `.md` cùng mã:
/// Obsidian resolve `[[PRF192]]` một cách nhập nhằng, và mọi ghi chú tay trong
/// file cũ nằm lại ở chỗ không ai đọc nữa. Nên việc dời là một phần của lượt
/// ghi, chỉ khác là nó được liệt kê ra để người dùng duyệt trước.
class VaultExportMove {
  final int subjectId;
  final String code;

  /// Đường dẫn tuyệt đối hiện tại của file.
  final String from;

  /// Đường dẫn tuyệt đối sau khi dời.
  final String to;

  /// Đích đã có sẵn một file khác -> không dời, tránh giẫm lên nội dung đó.
  final bool blocked;

  const VaultExportMove({
    required this.subjectId,
    required this.code,
    required this.from,
    required this.to,
    this.blocked = false,
  });
}

/// Ảnh chụp mọi thứ hộp thoại "Ghi ra Vault" cần, lấy đúng MỘT lần.
///
/// Hỏi đĩa ("file này có chưa?") là việc chậm, mà hộp thoại phải tính lại con
/// số xem trước sau mỗi lần người dùng tích một ô. Nên toàn bộ trạng thái đĩa
/// được chụp sẵn ở đây, còn hộp thoại chỉ lọc trên bộ nhớ.
///
/// Ảnh chụp gắn với ĐÚNG MỘT [subFolder]: đổi thư mục đích là đổi cả đường dẫn
/// đích lẫn tập file đã tồn tại, nên hộp thoại phải xin ảnh chụp mới chứ không
/// suy ra được từ ảnh cũ.
class VaultExportPreview {
  final String vaultPath;

  /// Thư mục con trong Vault mà lần ghi này nhắm tới. Rỗng = gốc Vault.
  final String subFolder;

  /// Mọi môn trong CSDL — tập ứng viên của lần ghi này.
  final List<Subject> subjects;

  /// Môn -> file `.md` sẽ được ghi (giữ nguyên vị trí cũ nếu còn trong Vault).
  final Map<int, String> targetPathOf;

  /// Môn mà file đích đã có sẵn trên đĩa: ghi ra là **hoà vào** file cũ chứ
  /// không tạo mới, và phần người dùng tự viết trong đó được giữ lại.
  final Set<int> existingFileIds;

  /// Môn -> id các môn tiên quyết của nó.
  final Map<int, List<int>> prerequisiteIds;

  /// Môn -> id các môn mà nó mở ra.
  final Map<int, List<int>> unlockIds;

  /// File cũ sẽ phải dời chỗ nếu lần ghi này chạy với [subFolder] hiện tại.
  /// Luôn rỗng khi [subFolder] rỗng — ghi ra gốc thì không dời gì cả.
  final List<VaultExportMove> moves;

  const VaultExportPreview({
    required this.vaultPath,
    required this.subjects,
    required this.targetPathOf,
    required this.existingFileIds,
    required this.prerequisiteIds,
    required this.unlockIds,
    this.subFolder = '',
    this.moves = const [],
  });

  static const VaultExportPreview empty = VaultExportPreview(
    vaultPath: '',
    subjects: [],
    targetPathOf: {},
    existingFileIds: {},
    prerequisiteIds: {},
    unlockIds: {},
  );

  /// Các lượt dời chỉ liên quan tới [ids] — hộp thoại chỉ ghi phần được tích,
  /// nên chỉ được hứa dời đúng chừng đó file.
  List<VaultExportMove> movesFor(Set<int> ids) =>
      [for (final m in moves) if (ids.contains(m.subjectId)) m];

  /// Bổ sung vào [ids] mọi môn tiên quyết, truy ngược hết nhiều bậc.
  ///
  /// Dùng cho ô "ghi kèm các môn tiên quyết": chọn riêng kỳ 5 thì file kỳ 5
  /// đầy `[[...]]` trỏ tới môn kỳ 1-4 chưa có file. Duyệt theo ngăn xếp có
  /// [seen] chặn nên đồ thị lỡ có chu trình cũng không treo.
  Set<int> withPrerequisites(Set<int> ids) {
    final seen = <int>{...ids};
    final stack = [...ids];
    while (stack.isNotEmpty) {
      for (final parent in prerequisiteIds[stack.removeLast()] ?? const []) {
        if (seen.add(parent)) stack.add(parent);
      }
    }
    return seen;
  }

  /// Các liên kết `[[...]]` sẽ trỏ tới file chưa tồn tại nếu chỉ ghi [ids].
  ///
  /// Một liên kết chỉ gãy khi môn đích vừa KHÔNG được chọn lần này, vừa chưa
  /// có file sẵn trong Vault từ lần ghi trước.
  List<String> danglingLinks(Set<int> ids) {
    final byId = {
      for (final s in subjects)
        if (s.id != null) s.id!: s,
    };
    final out = <String>[];
    for (final id in ids) {
      final from = byId[id];
      if (from == null) continue;
      for (final targets in [prerequisiteIds[id], unlockIds[id]]) {
        for (final target in targets ?? const <int>[]) {
          if (ids.contains(target) || existingFileIds.contains(target)) {
            continue;
          }
          final to = byId[target];
          if (to != null) out.add('${from.code} -> [[${to.code}]]');
        }
      }
    }
    out.sort();
    return out;
  }
}

/// Kết quả một lần ghi ra Vault.
class VaultExportReport {
  /// File chưa có trong Vault, lần này mới tạo.
  final int created;

  /// File đã có, lần này hoà nội dung mới vào (giữ phần người dùng tự viết).
  final int overwritten;

  final bool indexWritten;

  /// File cũ đã được dời sang thư mục đích mới.
  final int moved;

  /// Việc không làm được, mỗi dòng một việc kèm lý do — môn ghi hỏng hoặc file
  /// không dời được. Lượt ghi vẫn chạy tiếp qua phần còn lại thay vì chết ngang.
  final List<String> warnings;

  const VaultExportReport({
    this.created = 0,
    this.overwritten = 0,
    this.indexWritten = false,
    this.moved = 0,
    this.warnings = const [],
  });

  int get total => created + overwritten;

  String get summary {
    if (total == 0 && warnings.isEmpty) return 'Không có môn nào để ghi.';
    final sb = StringBuffer('Đã ghi $total file .md');
    if (created > 0 && overwritten > 0) {
      sb.write(' ($created tạo mới, $overwritten hoà vào file cũ)');
    } else if (overwritten > 0) {
      sb.write(' (hoà vào file đã có, giữ nguyên ghi chú bạn tự viết)');
    }
    if (moved > 0) sb.write(', dời $moved file cũ sang thư mục mới');
    if (indexWritten) sb.write(', kèm _INDEX.md');
    sb.write('.');
    if (warnings.isNotEmpty) {
      sb.write(
        ' Bỏ qua ${warnings.length} việc: ${warnings.take(3).join(' ')}',
      );
      if (warnings.length > 3) sb.write(' …');
    }
    return sb.toString();
  }
}

/// Đọc / ghi Obsidian Vault bằng `dart:io` thuần.
///
/// Triết lý Local-First: file Markdown trên đĩa là nguồn sự thật của nội dung,
/// SQLite là chỉ mục (index) để truy vấn quan hệ và vẽ đồ thị.
///
/// Toàn bộ logic regex nằm ở [MarkdownParser]; lớp này chỉ lo phần đĩa và
/// phần đồng bộ với cơ sở dữ liệu.
class ObsidianService {
  ObsidianService._();
  static final ObsidianService instance = ObsidianService._();

  final DbService _db = DbService.instance;

  /// `[[Tên môn]]`, `[[Tên môn|bí danh]]`, `[[Tên môn#heading]]`.
  static final RegExp wikiLinkPattern = MarkdownParser.wikiLinkPattern;

  /// `#tag`, `#tag/con`.
  static final RegExp tagPattern = MarkdownParser.tagPattern;

  static const String prereqHeadingVi = '## Môn tiên quyết';
  static const String prereqHeadingEn = '## Prerequisites';
  static const String unlockHeadingVi = '## Mở ra các môn';
  static const String noteHeadingVi = '## Ghi chú';

  static const String indexFileName = '_INDEX.md';
  static const String indexCode = 'INDEX';

  // ------------------------------------------------------------------
  // PARSE — giữ nguyên API cũ, phần việc thật do MarkdownParser làm
  // ------------------------------------------------------------------

  /// Bóc tách mọi wiki link trong một chuỗi Markdown.
  /// Bỏ phần alias sau `|` và phần heading sau `#`.
  static List<String> parseWikiLinks(String content) {
    final seen = <String>{};
    return [
      for (final l in MarkdownParser.parseLinks(content))
        if (seen.add(l.target)) l.target,
    ];
  }

  /// Bóc tách mọi `#tag` trong một chuỗi Markdown.
  static List<String> parseTags(String content) {
    final seen = <String>{};
    return [
      for (final t in MarkdownParser.parseTags(content))
        if (seen.add(t.name)) t.name,
    ];
  }

  /// Tách front matter YAML đơn giản (`key: value`) ra khỏi phần nội dung.
  static (Map<String, String>, String) splitFrontMatter(String content) =>
      MarkdownParser.splitFrontMatter(content);

  /// Lấy các wiki link nằm trong đoạn dưới một heading cụ thể.
  static List<String> linksUnderHeading(String body, List<String> headings) {
    final wanted = headings
        .map((h) => h.replaceAll(RegExp(r'^#+'), '').trim().toLowerCase())
        .toSet();

    final seen = <String>{};
    return [
      for (final l in MarkdownParser.parseLinks(body))
        if (wanted.contains(l.section.toLowerCase()) && seen.add(l.target))
          l.target,
    ];
  }

  ObsidianNote parseNote(String filePath, String content) {
    final parsed = MarkdownParser.parse(content);
    return ObsidianNote(
      filePath: filePath,
      fileName: p.basename(filePath),
      frontMatter: parsed.frontMatter,
      body: parsed.body,
      links: parsed.links,
      tags: parsed.tags,
    );
  }

  // ------------------------------------------------------------------
  // CHỈ MỤC CHO GIAO DIỆN
  // ------------------------------------------------------------------

  /// Môn nào đang trỏ tới môn nào: `{mã môn đích: [mã môn nguồn, ...]}`.
  /// Dùng để dựng panel Backlinks kiểu Obsidian.
  Map<String, List<String>> buildBacklinkIndex(List<ObsidianNote> notes) {
    final index = <String, List<String>>{};
    for (final note in notes) {
      for (final target in note.allLinks) {
        final key = target.toUpperCase();
        final list = index.putIfAbsent(key, () => []);
        if (!list.contains(note.code)) list.add(note.code);
      }
    }
    for (final list in index.values) {
      list.sort();
    }
    return index;
  }

  /// Thẻ nào gắn với môn nào: `{tên tag: [mã môn, ...]}`.
  /// Dùng để dựng bộ lọc theo thẻ màu.
  Map<String, List<String>> buildTagIndex(List<ObsidianNote> notes) {
    final index = <String, List<String>>{};
    for (final note in notes) {
      for (final tag in note.tagNames) {
        final list = index.putIfAbsent(tag, () => []);
        if (!list.contains(note.code)) list.add(note.code);
      }
    }
    for (final list in index.values) {
      list.sort();
    }
    return index;
  }

  // ------------------------------------------------------------------
  // ĐỌC FILE
  // ------------------------------------------------------------------

  /// Quét đệ quy một thư mục Vault, trả về mọi file `.md` đã bóc tách.
  /// Bỏ qua thư mục cấu hình `.obsidian` và các thư mục ẩn khác.
  ///
  /// [subFolder] khác rỗng thì chỉ quét trong thư mục con đó (đường dẫn tương
  /// đối so với gốc Vault). Dùng khi người dùng chỉ muốn nạp riêng một lượt
  /// quét — ví dụ `FAP/BIT_SE_K19B` — thay vì nuốt trọn mọi ghi chú cá nhân
  /// đang nằm rải rác trong Vault.
  Future<List<ObsidianNote>> scanVault(
    String vaultPath, {
    String subFolder = '',
  }) async {
    if (!await Directory(vaultPath).exists()) {
      throw ObsidianException('Không tìm thấy thư mục Vault: $vaultPath');
    }
    final scanRoot = subFolder.trim().isEmpty
        ? vaultPath
        : p.join(vaultPath, subFolder.trim());
    final dir = Directory(scanRoot);
    if (!await dir.exists()) {
      throw ObsidianException('Không tìm thấy thư mục: $scanRoot');
    }

    final notes = <ObsidianNote>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.md') continue;

      final relative = p.relative(entity.path, from: vaultPath);
      final hidden = p
          .split(relative)
          .any((segment) => segment.startsWith('.'));
      if (hidden) continue;

      try {
        final content = await entity.readAsString();
        notes.add(parseNote(entity.path, content));
      } on FileSystemException {
        // File đang bị khoá hoặc không phải UTF-8 -> bỏ qua, không làm sập app.
        continue;
      }
    }

    notes.sort((a, b) => a.code.compareTo(b.code));
    return notes;
  }

  /// Liệt kê các thư mục con của Vault (tối đa 2 cấp) kèm số file `.md`, để
  /// hộp thoại nạp hỏi "chỉ nạp thư mục nào". Luôn có mục đầu là cả Vault.
  Future<List<VaultFolderOption>> listImportableFolders(
    String vaultPath,
  ) async {
    final root = Directory(vaultPath);
    if (!await root.exists()) {
      throw ObsidianException('Không tìm thấy thư mục Vault: $vaultPath');
    }

    Future<int> countMd(Directory dir) async {
      var n = 0;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        if (p.extension(e.path).toLowerCase() != '.md') continue;
        final rel = p.relative(e.path, from: vaultPath);
        if (p.split(rel).any((s) => s.startsWith('.'))) continue;
        n++;
      }
      return n;
    }

    final options = <VaultFolderOption>[
      VaultFolderOption(relativePath: '', mdCount: await countMd(root)),
    ];

    Future<void> walk(Directory dir, int depth) async {
      if (depth > 2) return;
      final children = <Directory>[];
      await for (final e in dir.list(followLinks: false)) {
        if (e is Directory && !p.basename(e.path).startsWith('.')) {
          children.add(e);
        }
      }
      children.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      for (final child in children) {
        final count = await countMd(child);
        if (count == 0) continue;
        options.add(
          VaultFolderOption(
            relativePath: p
                .relative(child.path, from: vaultPath)
                .replaceAll(r'\', '/'),
            mdCount: count,
          ),
        );
        await walk(child, depth + 1);
      }
    }

    await walk(root, 1);
    return options;
  }

  Future<String> readNote(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw ObsidianException('File không tồn tại: $filePath');
    }
    return file.readAsString();
  }

  Future<void> saveNote(String filePath, String content) async {
    final file = File(filePath);
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(content, flush: true);
    } on FileSystemException catch (e) {
      // Lỗi hệ thống của Windows nói bằng tiếng Anh về "volume label", chẳng
      // giúp gì cho người đang bấm nút "Ghi ra Vault". Nói thẳng file nào.
      throw ObsidianException(
        'Không ghi được file "$filePath": ${e.osError?.message ?? e.message}',
      );
    }
  }

  /// Trả `true` nếu file có thật và đã bị xoá, `false` nếu vốn không tồn tại.
  /// Phân biệt hai ca để lớp gọi không báo "đã xoá file" khi chẳng xoá gì.
  Future<bool> deleteNote(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  // ------------------------------------------------------------------
  // GHI FILE MARKDOWN
  // ------------------------------------------------------------------

  /// Sinh nội dung `.md` hoàn toàn mới cho một môn.
  /// Chỉ dùng khi file chưa tồn tại — file đã có thì đi đường [mergeMarkdown].
  String buildMarkdown({
    required Subject subject,
    List<Subject> prerequisites = const [],
    List<Subject> unlocks = const [],
    String? extraBody,
    List<String> curriculumCodes = const [],
  }) {
    final sb = StringBuffer();

    sb.write(_buildFrontMatter(subject, const {}, curriculumCodes));
    sb.writeln();
    sb.writeln('# ${subject.code} — ${subject.name}');
    sb.writeln();

    if (subject.description.trim().isNotEmpty) {
      sb.writeln(subject.description.trim());
      sb.writeln();
    }

    sb.writeln(prereqHeadingVi);
    sb.writeln(_buildLinkList(prerequisites, '_Không có (môn nền tảng)_'));
    sb.writeln();

    sb.writeln(unlockHeadingVi);
    sb.writeln(_buildLinkList(unlocks, '_Chưa có môn nào phụ thuộc_'));
    sb.writeln();

    sb.writeln(noteHeadingVi);
    sb.writeln((extraBody ?? '').trim());

    return sb.toString();
  }

  /// Cập nhật một file `.md` đã có mà **không đụng tới phần người dùng tự viết**.
  ///
  /// App chỉ sở hữu ba khối: front matter, mục "Môn tiên quyết" và mục
  /// "Mở ra các môn". Mọi heading khác — "Tài liệu", "Bài tập", "Đề thi" —
  /// được giữ nguyên từng dòng. Cách làm cũ là sinh lại cả file rồi chép về
  /// đúng một mục "Ghi chú", nên mọi mục khác người dùng thêm vào đều bị xoá
  /// sạch sau mỗi lần export.
  String mergeMarkdown({
    required Subject subject,
    required String existingContent,
    List<Subject> prerequisites = const [],
    List<Subject> unlocks = const [],
    List<String> curriculumCodes = const [],
  }) {
    final (front, body) = MarkdownParser.splitFrontMatter(existingContent);

    final lines = body.split('\n');
    final out = <String>[];
    var seenPrereq = false;
    var seenUnlock = false;

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final heading = _headingTitleOf(line);

      if (heading != null && MarkdownParser.isPrerequisiteHeading(heading)) {
        seenPrereq = true;
        out.add(line); // giữ nguyên cách người dùng viết heading
        out.add(_buildLinkList(prerequisites, '_Không có (môn nền tảng)_'));
        out.add('');
        i = _skipSectionBody(lines, i + 1);
        continue;
      }

      if (heading != null && MarkdownParser.isUnlockHeading(heading)) {
        seenUnlock = true;
        out.add(line);
        out.add(_buildLinkList(unlocks, '_Chưa có môn nào phụ thuộc_'));
        out.add('');
        i = _skipSectionBody(lines, i + 1);
        continue;
      }

      out.add(line);
      i++;
    }

    // File người dùng tự tạo có thể chưa có hai mục này -> thêm vào cuối.
    if (!seenPrereq) {
      out
        ..add('')
        ..add(prereqHeadingVi)
        ..add(_buildLinkList(prerequisites, '_Không có (môn nền tảng)_'))
        ..add('');
    }
    if (!seenUnlock) {
      out
        ..add('')
        ..add(unlockHeadingVi)
        ..add(_buildLinkList(unlocks, '_Chưa có môn nào phụ thuộc_'))
        ..add('');
    }

    final mergedBody = out.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return '${_buildFrontMatter(subject, front, curriculumCodes)}'
        '\n${mergedBody.trimLeft()}';
  }

  /// Dựng khối front matter, giữ lại mọi khoá lạ mà người dùng tự thêm.
  String _buildFrontMatter(
    Subject subject,
    Map<String, String> existing, [
    List<String> curriculumCodes = const [],
  ]) {
    const managed = {
      'code',
      'name',
      'semester',
      'credits',
      'tags',
      'aliases',
      'curriculum',
      'curriculums',
    };

    // Mã có ký tự cấm thì tên file đã bị gọt (`PHE_COM*1` -> `PHE_COM-1.md`),
    // trong khi mọi `[[...]]` vẫn viết mã thật. Bí danh là thứ nối hai bên lại
    // để Obsidian resolve được liên kết. Giữ cả bí danh người dùng tự thêm.
    final aliases = <String>{
      if (sanitizeFileStem(subject.code) != subject.code) subject.code,
      ...MarkdownParser.parseListValue(existing['aliases']),
    }.where((e) => e.trim().isNotEmpty).toList();

    // Tag mặc định của app cộng với tag người dùng tự đặt.
    final tags = <String>{
      'subject',
      'semester-${subject.semester}',
      ...MarkdownParser.parseListValue(existing['tags']),
    }.toList();

    // Giữ lại mã tệp cũ ghi trong file khi lần xuất này không biết tệp nào —
    // tránh làm mất thông tin phân nhóm của một file người dùng tự sửa.
    final currs = <String>{
      ...curriculumCodes.map((e) => e.trim().toUpperCase()),
      if (curriculumCodes.isEmpty)
        ...MarkdownParser.parseListValue(
          existing['curriculum'] ?? existing['curriculums'],
        ).map((e) => e.trim().toUpperCase()),
    }.where((e) => e.isNotEmpty).toList()..sort();

    final sb = StringBuffer()
      ..writeln('---')
      ..writeln('code: ${subject.code}')
      ..writeln('name: "${subject.name.replaceAll('"', r'\"')}"')
      ..writeln('semester: ${subject.semester}')
      ..writeln('credits: ${subject.credits}')
      ..writeln('tags: [${tags.join(', ')}]');

    if (aliases.isNotEmpty) {
      // Nháy kép vì một bí danh mở đầu bằng `*` là node alias trong YAML.
      sb.writeln(
        'aliases: [${aliases.map((e) => '"${e.replaceAll('"', r'\"')}"').join(', ')}]',
      );
    }

    if (currs.isNotEmpty) {
      sb.writeln('curriculum: [${currs.join(', ')}]');
    }

    for (final entry in existing.entries) {
      if (managed.contains(entry.key)) continue;
      if (entry.value.trim().isEmpty) continue;
      sb.writeln('${entry.key}: ${entry.value}');
    }

    sb.writeln('---');
    return sb.toString();
  }

  String _buildLinkList(List<Subject> subjects, String emptyLabel) {
    if (subjects.isEmpty) return '- $emptyLabel';
    return subjects.map((s) => '- [[${s.code}]] — ${s.name}').join('\n');
  }

  /// Tên heading của một dòng, hoặc null nếu dòng đó không phải heading.
  String? _headingTitleOf(String line) {
    final match = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    return match?.group(2)?.trim();
  }

  /// Nhảy qua phần thân của section hiện tại, dừng ngay trước heading kế tiếp.
  int _skipSectionBody(List<String> lines, int from) {
    var i = from;
    while (i < lines.length && _headingTitleOf(lines[i]) == null) {
      i++;
    }
    return i;
  }

  /// Ký tự Windows cấm trong tên file, cộng nhóm ký tự điều khiển.
  static final RegExp _forbiddenInFileName = RegExp(r'[<>:"/\\|?*\x00-\x1f]');

  /// Windows cắt cụt dấu chấm và khoảng trắng ở cuối tên file.
  static final RegExp _trailingDotsOrSpaces = RegExp(r'[. ]+$');

  /// Tên thiết bị Windows chiếm chỗ: `CON.md` không tạo được dù đuôi là gì.
  static final RegExp _reservedDeviceName = RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$',
    caseSensitive: false,
  );

  /// Gọt một mã môn thành phần tên file hợp lệ trên Windows.
  ///
  /// FAP có thật những mã chứa dấu `*` — `PHE_COM*1`, `SE_COM*4_ELE` là các ô
  /// "combo" trong khung. Ghép thẳng vào đường dẫn thì `File.writeAsString`
  /// ném `PathNotFoundException` kèm lỗi hệ thống 123 ("The filename,
  /// directory name, or volume label syntax is incorrect"), và cả lượt ghi
  /// chết giữa chừng.
  ///
  /// Chỉ tên file bị đổi. Mã thật vẫn nằm nguyên ở `code:` trong front matter
  /// và trong mọi `[[...]]`, nên nạp ngược lại vẫn khớp đúng môn.
  static String sanitizeFileStem(String raw) {
    final stem = raw
        .trim()
        .replaceAll(_forbiddenInFileName, '-')
        .replaceAll(_trailingDotsOrSpaces, '');
    if (stem.isEmpty) return 'mon-khong-ma';
    if (_reservedDeviceName.hasMatch(stem)) return '_$stem';
    return stem;
  }

  /// Tên file chuẩn cho một môn: `<MÃ MÔN>.md`.
  /// Đặt theo mã môn để `[[PRF192]]` trong Obsidian luôn resolve được; mã có
  /// ký tự cấm thì tên file được gọt và front matter mang thêm `aliases` để
  /// liên kết vẫn trỏ đúng.
  String fileNameFor(Subject subject) => '${sanitizeFileStem(subject.code)}.md';

  /// Ghi (hoặc cập nhật) file `.md` của một môn ra Vault, đồng thời lưu
  /// `note_path` vào SQLite để lần sau mở lại đúng file đó.
  Future<String> exportSubject({
    required String vaultPath,
    required Subject subject,
    List<Subject>? prerequisites,
    List<Subject>? unlocks,
    List<String>? curriculumCodes,
    String subFolder = '',
    bool keepExistingLocation = false,
  }) async {
    if (subject.id == null) {
      throw ObsidianException('Môn chưa được lưu vào CSDL.');
    }
    final prereqs = prerequisites ?? await _db.getPrerequisitesOf(subject.id!);
    final opens = unlocks ?? await _db.getUnlockedBy(subject.id!);
    final currs =
        curriculumCodes ??
        (await _db.curriculumCodesBySubjectId())[subject.id!] ??
        const <String>[];

    // Ưu tiên ghi đè đúng file cũ nếu môn này đã từng liên kết với một file.
    final target = _resolveTargetPath(
      vaultPath,
      subject,
      subFolder,
      keepExistingLocation,
    );
    final existing = File(target);

    final content = await existing.exists()
        ? mergeMarkdown(
            subject: subject,
            existingContent: await existing.readAsString(),
            prerequisites: prereqs,
            unlocks: opens,
            curriculumCodes: currs,
          )
        : buildMarkdown(
            subject: subject,
            prerequisites: prereqs,
            unlocks: opens,
            curriculumCodes: currs,
          );

    await saveNote(target, content);

    // Chỉ ghi lại CSDL khi đường dẫn thật sự đổi, tránh N lần UPDATE thừa.
    if (subject.notePath != target) {
      await _db.updateSubject(subject.copyWith(notePath: target));
    }
    return target;
  }

  /// Thư mục gốc của lần ghi: gốc Vault, hoặc thư mục con người dùng chỉ định.
  String _exportRoot(String vaultPath, String subFolder) {
    final clean = subFolder.trim().replaceAll(r'\', '/');
    if (clean.isEmpty) return vaultPath;
    // Gọt từng đoạn để một ô nhập lỡ tay ("/SE Knowledge/", "a//b") không đẻ ra
    // đường dẫn lạ, và chặn `..` leo ra ngoài Vault.
    final parts = clean
        .split('/')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != '.' && e != '..')
        .map(sanitizeFileStem)
        .toList();
    if (parts.isEmpty) return vaultPath;
    return p.joinAll([vaultPath, ...parts]);
  }

  /// Dạng chuẩn hoá của [subFolder] để hiển thị và so sánh (`SE Knowledge`).
  /// Rỗng nghĩa là ghi thẳng ra gốc Vault.
  String normalizeSubFolder(String vaultPath, String subFolder) {
    final root = _exportRoot(vaultPath, subFolder);
    if (p.equals(root, vaultPath)) return '';
    return p.relative(root, from: vaultPath).replaceAll(r'\', '/');
  }

  /// Đổi đường dẫn tuyệt đối vừa chọn trong hộp thoại hệ điều hành thành
  /// [subFolder] tương đối so với Vault.
  ///
  /// Trả `null` khi thư mục đó nằm NGOÀI Vault. Obsidian chỉ resolve `[[...]]`
  /// trong phạm vi Vault, nên ghi ra ngoài là ghi vào chỗ Obsidian không nhìn
  /// thấy: file có đó mà đồ thị vẫn trống. Thà chặn còn hơn để người dùng ngồi
  /// đoán tại sao ghi xong chẳng thấy gì.
  String? subFolderFromAbsolute(String vaultPath, String absolute) {
    final target = p.normalize(absolute.trim());
    if (target.isEmpty) return null;
    if (p.equals(target, vaultPath)) return '';
    if (!p.isWithin(vaultPath, target)) return null;
    return p.relative(target, from: vaultPath).replaceAll(r'\', '/');
  }

  /// File đích của một môn: giữ nguyên vị trí cũ nếu file đó còn nằm trong
  /// thư mục đích, để người dùng sắp xếp ghi chú vào thư mục con tuỳ ý mà
  /// export không kéo ngược file ra ngoài.
  ///
  /// Đổi [subFolder] thì file cũ ở gốc Vault KHÔNG còn nằm trong thư mục đích
  /// nữa, nên đích của nó dịch sang thư mục mới — và [planExportMoves] lo phần
  /// dời file thật để không sót lại một bản trùng ở chỗ cũ.
  /// [keepExistingLocation] nới lỏng phép so: file cũ nằm BẤT KỲ đâu trong
  /// Vault đều được giữ. Dành cho lối ghi nhanh (menu chuột phải) — lối đó
  /// không có hộp thoại nào để hỏi "dời file cũ chứ?", nên nó chỉ được dùng
  /// [subFolder] cho môn chưa có file, tuyệt đối không tự đẻ bản trùng.
  String _resolveTargetPath(
    String vaultPath,
    Subject subject, [
    String subFolder = '',
    bool keepExistingLocation = false,
  ]) {
    final root = _exportRoot(vaultPath, subFolder);
    final saved = subject.notePath;
    final anchor = keepExistingLocation ? vaultPath : root;
    if (saved != null && saved.isNotEmpty && p.isWithin(anchor, saved)) {
      return saved;
    }
    return p.join(root, fileNameFor(subject));
  }

  /// Liệt kê các file `.md` sẽ phải dời chỗ khi ghi [subjects] vào [subFolder].
  ///
  /// Chỉ liệt kê, KHÔNG đụng đĩa — hộp thoại cần con số này để hỏi người dùng
  /// trước, vì dời file là thao tác không hoàn tác được từ trong app.
  Future<List<VaultExportMove>> planExportMoves(
    String vaultPath, {
    required List<Subject> subjects,
    required String subFolder,
  }) async {
    final root = _exportRoot(vaultPath, subFolder);
    if (p.equals(root, vaultPath)) return const [];

    final moves = <VaultExportMove>[];
    for (final subject in subjects) {
      final id = subject.id;
      final saved = subject.notePath;
      if (id == null || saved == null || saved.isEmpty) continue;
      // File ngoài Vault (Vault cũ đã đổi chỗ) không phải việc của lượt này.
      if (!p.isWithin(vaultPath, saved)) continue;
      if (p.isWithin(root, saved)) continue;
      if (!await File(saved).exists()) continue;

      final to = p.join(root, fileNameFor(subject));
      if (p.equals(saved, to)) continue;
      moves.add(
        VaultExportMove(
          subjectId: id,
          code: subject.code,
          from: saved,
          to: to,
          blocked: await File(to).exists(),
        ),
      );
    }
    moves.sort((a, b) => a.code.compareTo(b.code));
    return moves;
  }

  /// Thực hiện các lượt dời, cập nhật luôn `note_path` trong SQLite.
  ///
  /// Trả về số file đã dời. Lượt nào hỏng chỉ rơi vào [warnings] rồi bỏ qua:
  /// một file đang bị Obsidian khoá không đáng làm chết cả lượt ghi.
  Future<int> _applyMoves(
    List<VaultExportMove> moves,
    List<String> warnings,
    Map<int, Subject> byId,
  ) async {
    var done = 0;
    for (final move in moves) {
      if (move.blocked) {
        warnings.add(
          '${move.code}: không dời được vì "${p.basename(move.to)}" đã có sẵn '
          'trong thư mục đích.',
        );
        continue;
      }
      try {
        final file = File(move.from);
        if (!await file.exists()) continue;
        await Directory(p.dirname(move.to)).create(recursive: true);
        await file.rename(move.to);
        final subject = byId[move.subjectId];
        if (subject != null) {
          await _db.updateSubject(subject.copyWith(notePath: move.to));
        }
        done++;
      } on FileSystemException catch (e) {
        warnings.add(
          '${move.code}: không dời được file — ${e.osError?.message ?? e.message}',
        );
      }
    }
    return done;
  }

  /// Ghi ra Vault đúng một nhóm môn (một tệp môn học, hoặc một kỳ trong tệp).
  /// Không đụng tới `_INDEX.md` vì đây là thao tác cục bộ.
  ///
  /// [subFolder] chỉ áp cho môn CHƯA có file — lối này không hỏi gì người dùng
  /// nên không được phép dời file cũ hay tạo bản trùng sau lưng họ.
  Future<int> exportSubjects(
    String vaultPath,
    List<Subject> subjects, {
    String subFolder = '',
  }) async {
    if (subjects.isEmpty) return 0;
    return _exportSubjects(
      vaultPath,
      subjects,
      await _db.loadGraph(),
      subFolder: subFolder,
      keepExistingLocation: true,
    );
  }

  /// Ghi ra Vault đúng nhóm môn người dùng đã tích trong hộp thoại.
  ///
  /// Khác [exportSubjects] ở hai điểm: trả về [VaultExportReport] tách bạch
  /// "file tạo mới" với "file hoà vào file cũ" để báo cho đúng, và cho phép
  /// ghi kèm `_INDEX.md`.
  ///
  /// [writeIndex] mặc định tắt: `_INDEX.md` liệt kê **toàn bộ** đồ thị trong
  /// CSDL, nên ghi nó sau một lượt export cục bộ sẽ tạo ra một mục lục trỏ
  /// tới hàng loạt file chưa hề tồn tại trong Vault.
  Future<VaultExportReport> exportSelection(
    String vaultPath, {
    required List<Subject> subjects,
    bool writeIndex = false,
    String subFolder = '',
    bool moveExisting = true,
  }) async {
    final warnings = <String>[];

    // Dời TRƯỚC khi ghi: dời sau thì file vừa ghi ra ở chỗ mới lại bị bản cũ
    // đè lên, và `note_path` trong CSDL trỏ vào chỗ đã rỗng.
    var moved = 0;
    if (moveExisting) {
      final before = await _db.loadGraph();
      final moves = await planExportMoves(
        vaultPath,
        subjects: subjects,
        subFolder: subFolder,
      );
      moved = await _applyMoves(moves, warnings, before.byId);
    }

    // Nạp lại sau khi dời để `note_path` trong bộ nhớ khớp với đĩa.
    final graph = await _db.loadGraph();
    final byId = graph.byId;
    final fresh = [
      for (final s in subjects)
        if (s.id != null) byId[s.id!] ?? s,
    ];

    // Phải hỏi đĩa TRƯỚC khi ghi, không thì file nào cũng "đã tồn tại".
    var created = 0;
    for (final subject in fresh) {
      if (!await File(
        _resolveTargetPath(vaultPath, subject, subFolder),
      ).exists()) {
        created++;
      }
    }

    final written = await _exportSubjects(
      vaultPath,
      fresh,
      graph,
      warnings: warnings,
      subFolder: subFolder,
    );
    if (writeIndex) await _writeIndexNote(vaultPath, graph, subFolder);

    // `created` đếm trên tập được chọn; môn ghi hỏng phải trừ ra khỏi đó trước
    // rồi mới suy ra số file hoà vào, không thì hai con số lệch nhau.
    final createdWritten = created.clamp(0, written);
    return VaultExportReport(
      created: createdWritten,
      overwritten: written - createdWritten,
      indexWritten: writeIndex,
      moved: moved,
      warnings: warnings,
    );
  }

  /// Chụp mọi thứ hộp thoại "Ghi ra Vault" cần để tính toán **tại chỗ**, không
  /// phải hỏi lại đĩa mỗi lần người dùng tích một ô.
  Future<VaultExportPreview> buildExportPreview(
    String vaultPath, {
    String subFolder = '',
  }) async {
    final graph = await _db.loadGraph();

    final targetPathOf = <int, String>{};
    final existingFileIds = <int>{};
    for (final subject in graph.subjects) {
      final id = subject.id;
      if (id == null) continue;
      final target = _resolveTargetPath(vaultPath, subject, subFolder);
      targetPathOf[id] = target;
      if (await File(target).exists()) existingFileIds.add(id);
    }

    final prerequisiteIds = <int, List<int>>{};
    final unlockIds = <int, List<int>>{};
    for (final e in graph.edges) {
      prerequisiteIds.putIfAbsent(e.subjectId, () => []).add(e.prerequisiteId);
      unlockIds.putIfAbsent(e.prerequisiteId, () => []).add(e.subjectId);
    }

    return VaultExportPreview(
      vaultPath: vaultPath,
      subFolder: normalizeSubFolder(vaultPath, subFolder),
      subjects: graph.subjects,
      targetPathOf: targetPathOf,
      existingFileIds: existingFileIds,
      prerequisiteIds: prerequisiteIds,
      unlockIds: unlockIds,
      moves: await planExportMoves(
        vaultPath,
        subjects: graph.subjects,
        subFolder: subFolder,
      ),
    );
  }

  /// [warnings] khác `null` thì một môn ghi hỏng chỉ bị ghi vào đó rồi bỏ qua,
  /// thay vì làm chết cả lượt ghi. Lượt ghi 57 môn mà môn thứ 3 trục trặc thì
  /// 54 môn còn lại vẫn đáng được ghi ra.
  Future<int> _exportSubjects(
    String vaultPath,
    List<Subject> subjects,
    GraphData graph, {
    List<String>? warnings,
    String subFolder = '',
    bool keepExistingLocation = false,
  }) async {
    final byId = graph.byId;

    // Gom sẵn quan hệ trong bộ nhớ, thay vì 2 truy vấn cho mỗi môn.
    final prereqsOf = <int, List<Subject>>{};
    final unlocksOf = <int, List<Subject>>{};
    for (final e in graph.edges) {
      final child = byId[e.subjectId];
      final parent = byId[e.prerequisiteId];
      if (child == null || parent == null) continue;
      prereqsOf.putIfAbsent(e.subjectId, () => []).add(parent);
      unlocksOf.putIfAbsent(e.prerequisiteId, () => []).add(child);
    }

    final currsOf = await _db.curriculumCodesBySubjectId();

    int bySemesterThenCode(Subject a, Subject b) => a.semester != b.semester
        ? a.semester.compareTo(b.semester)
        : a.code.compareTo(b.code);

    var written = 0;
    for (final subject in subjects) {
      final id = subject.id;
      if (id == null) continue;
      // Môn trong cây thư mục mang `semester` = term của tệp; ghi ra file thì
      // phải dùng bản gốc trong CSDL để không đè kỳ của tệp khác.
      final canonical = byId[id] ?? subject;
      try {
        await exportSubject(
          vaultPath: vaultPath,
          subject: canonical,
          prerequisites: (prereqsOf[id] ?? [])..sort(bySemesterThenCode),
          unlocks: (unlocksOf[id] ?? [])..sort(bySemesterThenCode),
          curriculumCodes: currsOf[id] ?? const [],
          subFolder: subFolder,
          keepExistingLocation: keepExistingLocation,
        );
        written++;
      } on ObsidianException catch (e) {
        if (warnings == null) rethrow;
        warnings.add('${canonical.code}: ${e.message}');
      }
    }
    return written;
  }

  Future<void> _writeIndexNote(
    String vaultPath,
    GraphData graph, [
    String subFolder = '',
  ]) async {
    final sb = StringBuffer()
      ..writeln('---')
      ..writeln('code: $indexCode')
      ..writeln('name: "Bản đồ tri thức"')
      ..writeln('tags: [index]')
      ..writeln('---')
      ..writeln()
      ..writeln('# Bản đồ tri thức môn học')
      ..writeln();

    final semesters = graph.subjects.map((s) => s.semester).toSet().toList()
      ..sort();
    for (final sem in semesters) {
      sb.writeln('## Kỳ $sem');
      for (final s in graph.subjects.where((x) => x.semester == sem)) {
        sb.writeln('- [[${s.code}]] — ${s.name} (${s.credits} tín chỉ)');
      }
      sb.writeln();
    }

    // Mục lục nằm cạnh các file môn: `[[PRF192]]` Obsidian resolve theo tên
    // file trên toàn Vault nên thư mục nào cũng trỏ đúng, nhưng để chung chỗ
    // thì mở ra là thấy ngay.
    await saveNote(
      p.join(_exportRoot(vaultPath, subFolder), indexFileName),
      sb.toString(),
    );
  }

  // ------------------------------------------------------------------
  // ĐỒNG BỘ VAULT -> SQLITE
  // ------------------------------------------------------------------

  /// Dựng kế hoạch đồng bộ mà **không ghi gì** xuống CSDL.
  ///
  /// Tách khỏi [applyPlan] để giao diện hỏi người dùng trước khi ghi đè —
  /// đặc biệt quan trọng với phần gỡ liên kết, vì thao tác đó không hoàn tác
  /// được.
  Future<VaultSyncPlan> planImport(
    String vaultPath, {
    String subFolder = '',
  }) async {
    final scanned = (await scanVault(
      vaultPath,
      subFolder: subFolder,
    )).where((n) => n.code.isNotEmpty && n.code != indexCode).toList();

    // Trang FAP thô đi đường riêng — xem chú thích ở [VaultSyncPlan.fapPages].
    final fapPages = <ObsidianNote>[];
    final notes = <ObsidianNote>[];
    for (final note in scanned) {
      if (FapMarkdownParser.looksLikeFapPage(note.body)) {
        fapPages.add(note);
      } else {
        notes.add(note);
      }
    }

    final graph = await _db.loadGraph();
    final byCode = graph.byCode;
    final byId = graph.byId;

    final vaultCodes = notes.map((n) => n.code).toSet();

    final toCreate = <ObsidianNote>[];
    final toUpdate = <ObsidianNote>[];
    final unchanged = <ObsidianNote>[];

    for (final note in notes) {
      final existing = byCode[note.code];
      if (existing == null) {
        toCreate.add(note);
      } else if (_hasChanged(existing, note)) {
        toUpdate.add(note);
      } else {
        unchanged.add(note);
      }
    }

    // Quan hệ hiện có trong CSDL, quy về mã môn cho dễ so sánh.
    final currentEdges = <String, Set<String>>{};
    for (final e in graph.edges) {
      final child = byId[e.subjectId];
      final parent = byId[e.prerequisiteId];
      if (child == null || parent == null) continue;
      currentEdges.putIfAbsent(child.code, () => {}).add(parent.code);
    }

    final edgesToAdd = <EdgeChange>[];
    final edgesToRemove = <EdgeChange>[];
    final brokenLinks = <String>[];

    for (final note in notes) {
      final desired = <String>{};
      for (final code in note.prerequisiteCodes) {
        if (vaultCodes.contains(code) || byCode.containsKey(code)) {
          desired.add(code);
        } else {
          brokenLinks.add(
            '${note.code}: liên kết [[$code]] không trỏ tới file .md nào.',
          );
        }
      }

      final current = currentEdges[note.code] ?? const <String>{};

      for (final code in desired.difference(current)) {
        edgesToAdd.add(
          EdgeChange(subjectCode: note.code, prerequisiteCode: code),
        );
      }
      // Chỉ gỡ cạnh của những môn thật sự có file trong Vault. Môn chỉ tồn tại
      // trong CSDL thì Vault không có quyền phát biểu gì về quan hệ của nó.
      for (final code in current.difference(desired)) {
        edgesToRemove.add(
          EdgeChange(subjectCode: note.code, prerequisiteCode: code),
        );
      }
    }

    // Chỉ có nghĩa khi quét cả Vault. Quét một thư mục con thì đương nhiên
    // mọi môn ngoài thư mục đó đều "không thấy file", báo ra chỉ tổ gây nhiễu.
    final missingInVault = subFolder.trim().isEmpty
        ? graph.subjects.where((s) => !vaultCodes.contains(s.code)).toList()
        : <Subject>[];

    // Mã tệp môn học các file tự khai, xếp theo số file khai nhiều nhất trước
    // để gợi ý mặc định trúng cái người dùng đang định nạp.
    final codeHits = <String, int>{};
    for (final note in notes) {
      for (final code in note.curriculumCodes) {
        codeHits[code] = (codeHits[code] ?? 0) + 1;
      }
    }
    final detected = codeHits.keys.toList()
      ..sort((a, b) => codeHits[b]!.compareTo(codeHits[a]!));

    // Một lượt quét FAP thường kèm luôn trang "Curriculum Details" — trang đó
    // ghi thẳng `CurriculumCode: BIT_SE_K19B`, đáng tin hơn mọi suy đoán khác
    // nên được xếp lên đầu danh sách gợi ý.
    final fromFap = <String>[];
    for (final note in [...fapPages, ...notes]) {
      final code = FapMarkdownParser.curriculumCodeOf(note.body);
      if (code != null && !fromFap.contains(code)) fromFap.add(code);
    }
    detected.removeWhere(fromFap.contains);
    detected.insertAll(0, fromFap);

    return VaultSyncPlan(
      vaultPath: vaultPath,
      subFolder: subFolder.trim(),
      notes: notes,
      toCreate: toCreate,
      toUpdate: toUpdate,
      unchanged: unchanged,
      edgesToAdd: edgesToAdd,
      edgesToRemove: edgesToRemove,
      brokenLinks: brokenLinks,
      missingInVault: missingInVault,
      detectedCurriculumCodes: detected,
      fapPages: fapPages,
    );
  }

  /// Nội dung file có khác với bản ghi trong CSDL không.
  /// Dùng để đếm đúng số môn thật sự được cập nhật.
  bool _hasChanged(Subject existing, ObsidianNote note) =>
      existing.name != note.name ||
      existing.semester != note.semester ||
      existing.credits != note.credits ||
      existing.description != note.description ||
      existing.notePath != note.filePath;

  /// Ghi kế hoạch xuống CSDL.
  ///
  /// [target] quyết định các môn vừa nạp rơi vào "tệp môn học" nào trên thanh
  /// bên. Bỏ trống thì giữ nguyên hành vi cũ: môn nằm ở nhóm ngoài khung.
  Future<VaultSyncReport> applyPlan(
    VaultSyncPlan plan, {
    VaultImportTarget? target,
  }) async {
    final warnings = <String>[...plan.brokenLinks];

    // Lượt 1: tạo/cập nhật toàn bộ node trước, để lượt 2 luôn tìm thấy đích.
    final idByCode = <String, int>{};
    for (final note in [...plan.toCreate, ...plan.toUpdate]) {
      idByCode[note.code] = await _db.upsertSubjectByCode(note.toSubject());
    }
    for (final note in plan.unchanged) {
      final existing = await _db.getSubjectByCode(note.code);
      if (existing?.id != null) idByCode[note.code] = existing!.id!;
    }

    Future<int?> idOf(String code) async {
      final cached = idByCode[code];
      if (cached != null) return cached;
      final found = await _db.getSubjectByCode(code);
      if (found?.id != null) idByCode[code] = found!.id!;
      return found?.id;
    }

    // Lượt 2: gỡ trước rồi mới thêm, để chỗ vừa trống không chặn cạnh mới.
    var edgesRemoved = 0;
    for (final change in plan.edgesToRemove) {
      final subjectId = await idOf(change.subjectCode);
      final prereqId = await idOf(change.prerequisiteCode);
      if (subjectId == null || prereqId == null) continue;
      await _db.removeEdge(subjectId: subjectId, prerequisiteId: prereqId);
      edgesRemoved++;
    }

    var edgesCreated = 0;
    for (final change in plan.edgesToAdd) {
      final subjectId = await idOf(change.subjectCode);
      final prereqId = await idOf(change.prerequisiteCode);
      if (subjectId == null || prereqId == null) {
        warnings.add(
          '${change.subjectCode}: không tìm thấy môn ${change.prerequisiteCode}.',
        );
        continue;
      }
      try {
        await _db.addEdge(
          subjectId: subjectId,
          prerequisiteId: prereqId,
          relationType: Prerequisite.kPrerequisite,
        );
        edgesCreated++;
      } on DbConflictException catch (e) {
        // Trùng liên kết là bình thường khi đồng bộ lại; chu trình thì cảnh báo.
        if (!e.message.contains('đã tồn tại')) {
          warnings.add(
            '${change.prerequisiteCode} -> ${change.subjectCode}: ${e.message}',
          );
        }
      }
    }

    for (final subject in plan.missingInVault) {
      warnings.add(
        '${subject.code} có trong CSDL nhưng không còn file .md trong Vault.',
      );
    }

    // Lượt 2b: nạp các trang FAP thô bằng bộ đọc riêng của chúng. Khung CTĐT
    // đi trước để bảng môn có sẵn khi syllabus tìm mã môn tiên quyết.
    final fapReport = await _importFapPages(plan.fapPages, warnings);
    edgesCreated += fapReport.$2;

    // Lượt 3: xếp toàn bộ môn vừa nạp vào đúng tệp môn học người dùng chọn.
    var curriculumCode = '';
    var assigned = 0;
    if (target != null && !target.isUnassigned) {
      try {
        final curriculumId =
            target.existingCurriculumId ??
            await _db.ensureCurriculumByCode(
              code: target.newCode!,
              name: target.newName,
            );
        final row = await _db.getCurriculumById(curriculumId);
        curriculumCode = (row?['code'] as String?) ?? (target.newCode ?? '');

        final entries = <CurriculumCourseEntry>[];
        final seen = <int>{};
        for (final note in plan.allNotes) {
          final id = await idOf(note.code);
          if (id == null || !seen.add(id)) continue;
          entries.add(
            CurriculumCourseEntry(
              subjectId: id,
              term: note.semester,
              credits: note.credits,
            ),
          );
        }

        // Môn đến từ trang FAP không có [ObsidianNote] nào đại diện nên không
        // nằm trong [plan.allNotes]. Bỏ qua chúng ở đây thì nạp một thư mục
        // toàn Syllabus Details sẽ dựng ra một tệp môn học RỖNG: môn vẫn vào
        // bảng `subjects` nhưng không có dòng `curriculum_courses` nào, nên cây
        // bên trái dồn hết chúng vào nhóm "Môn ngoài khung".
        //
        // Kỳ và tín chỉ lấy từ chính hàng `subjects` vừa ghi — trang Curriculum
        // Details có sẵn hai cột đó, còn trang Syllabus Details thì không nên
        // rơi về giá trị mặc định của môn.
        for (final code in fapReport.$3) {
          final subject = await _db.getSubjectByCode(code);
          final id = subject?.id;
          if (id == null || !seen.add(id)) continue;
          entries.add(
            CurriculumCourseEntry(
              subjectId: id,
              term: subject!.semester,
              credits: subject.credits,
            ),
          );
        }
        await _db.assignSubjectsToCurriculum(
          curriculumId: curriculumId,
          entries: entries,
          overwriteExisting: target.overwriteTerms,
        );
        assigned = entries.length;
      } catch (e) {
        warnings.add('Không xếp được các môn vào tệp môn học: $e');
      }
    }

    return VaultSyncReport(
      filesScanned: plan.notes.length + plan.fapPages.length,
      subjectsCreated: plan.toCreate.length,
      subjectsUpdated: plan.toUpdate.length,
      edgesCreated: edgesCreated,
      edgesRemoved: edgesRemoved,
      warnings: warnings,
      curriculumCode: curriculumCode,
      subjectsAssigned: assigned,
      fapPagesImported: fapReport.$1,
    );
  }

  /// Nạp các trang FAP thô có trong Vault.
  ///
  /// Trả về `(số trang nạp được, số cạnh tiên quyết dựng thêm, mã các môn đã
  /// ghi xuống)`. Cạnh được dựng bởi [DbService.syncPrerequisitesFromFap] từ
  /// cột "Pre-Requisite" đã lưu vào `curriculum_subjects`/`syllabi`, nên một
  /// môn tiên quyết được nhắc ở file này mà mãi file sau mới xuất hiện thì vẫn
  /// nối được.
  ///
  /// Danh sách mã môn là thứ [applyPlan] cần để xếp chúng vào tệp môn học
  /// người dùng chọn — không trả ra thì những môn này biến mất khỏi mọi tệp.
  Future<(int, int, List<String>)> _importFapPages(
    List<ObsidianNote> pages,
    List<String> warnings,
  ) async {
    if (pages.isEmpty) return (0, 0, const <String>[]);

    final curricula = <(ObsidianNote, FapParseResult)>[];
    final syllabi = <(ObsidianNote, FapParseResult)>[];
    for (final note in pages) {
      final parsed = FapMarkdownParser.parse(note.body);
      if (parsed.curriculum != null) {
        curricula.add((note, parsed));
      } else if (parsed.syllabus != null) {
        syllabi.add((note, parsed));
      } else {
        warnings.add('${note.fileName}: ${parsed.message}');
      }
    }

    var imported = 0;
    // Chỉ gom mã của những trang ghi xuống THÀNH CÔNG: trang ném lỗi thì môn
    // của nó chưa chắc có trong `subjects`, xếp vào tệp chỉ tổ sai.
    final subjectCodes = <String>[];
    final seenCodes = <String>{};
    void collect(String raw) {
      final code = raw.trim().toUpperCase();
      if (code.isNotEmpty && seenCodes.add(code)) subjectCodes.add(code);
    }

    for (final item in curricula) {
      final data = item.$2.curriculum!;
      try {
        await _db.importFapCurriculum(data);
        imported++;
        for (final row in data.subjects) {
          collect(row.code);
        }
      } catch (e) {
        warnings.add('${item.$1.fileName}: không nạp được khung CTĐT — $e');
      }
    }
    for (final item in syllabi) {
      final data = item.$2.syllabus!;
      try {
        await _db.importFapSyllabus(data);
        imported++;
        collect(data.subjectCode);
      } catch (e) {
        warnings.add('${item.$1.fileName}: không nạp được syllabus — $e');
      }
    }

    final edges = imported > 0 ? await _db.syncPrerequisitesFromFap() : 0;
    return (imported, edges, subjectCodes);
  }

  /// Quét Vault rồi nạp thẳng vào SQLite, không hỏi gì.
  /// Dùng khi không cần bước xác nhận; ngược lại thì gọi [planImport] trước.
  Future<VaultSyncReport> importVault(
    String vaultPath, {
    String subFolder = '',
    VaultImportTarget? target,
  }) async => applyPlan(
    await planImport(vaultPath, subFolder: subFolder),
    target: target,
  );
}

class ObsidianException implements Exception {
  final String message;
  ObsidianException(this.message);
  @override
  String toString() => message;
}
