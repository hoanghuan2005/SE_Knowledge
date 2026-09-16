import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/graph_data.dart';
import '../models/prerequisite.dart';
import '../models/subject.dart';
import 'db_service.dart';
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
  String get code =>
      (frontMatter['code']?.trim().isNotEmpty ?? false)
      ? frontMatter['code']!.trim().toUpperCase()
      : p.basenameWithoutExtension(fileName).trim().toUpperCase();

  String get name => frontMatter['name']?.trim().isNotEmpty ?? false
      ? frontMatter['name']!.trim()
      : p.basenameWithoutExtension(fileName);

  int get semester => int.tryParse(frontMatter['semester'] ?? '') ?? 1;
  int get credits => int.tryParse(frontMatter['credits'] ?? '') ?? 3;

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

/// Bản kế hoạch đồng bộ Vault -> SQLite, dựng ra **trước** khi ghi bất cứ thứ
/// gì. Giao diện đổ thẳng dữ liệu này vào hộp thoại xác nhận.
class VaultSyncPlan {
  final String vaultPath;
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

  const VaultSyncPlan({
    required this.vaultPath,
    required this.notes,
    required this.toCreate,
    required this.toUpdate,
    required this.unchanged,
    required this.edgesToAdd,
    required this.edgesToRemove,
    required this.brokenLinks,
    required this.missingInVault,
  });

  /// Không có gì thay đổi thì khỏi cần hỏi người dùng.
  bool get isEmpty =>
      toCreate.isEmpty &&
      toUpdate.isEmpty &&
      edgesToAdd.isEmpty &&
      edgesToRemove.isEmpty;

  /// Có thao tác nào gây mất dữ liệu không — dùng để tô màu cảnh báo.
  bool get hasRemovals => edgesToRemove.isNotEmpty;

  String get summary =>
      'Quét ${notes.length} file .md: thêm ${toCreate.length} môn, '
      'cập nhật ${toUpdate.length} môn, giữ nguyên ${unchanged.length} môn, '
      'thêm ${edgesToAdd.length} liên kết, gỡ ${edgesToRemove.length} liên kết.';
}

/// Kết quả một lần đồng bộ Vault -> SQLite.
class VaultSyncReport {
  final int filesScanned;
  final int subjectsCreated;
  final int subjectsUpdated;
  final int edgesCreated;
  final int edgesRemoved;
  final List<String> warnings;

  const VaultSyncReport({
    required this.filesScanned,
    required this.subjectsCreated,
    required this.subjectsUpdated,
    required this.edgesCreated,
    this.edgesRemoved = 0,
    required this.warnings,
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
    sb.write('.');
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
  Future<List<ObsidianNote>> scanVault(String vaultPath) async {
    final dir = Directory(vaultPath);
    if (!await dir.exists()) {
      throw ObsidianException('Không tìm thấy thư mục Vault: $vaultPath');
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

  Future<String> readNote(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw ObsidianException('File không tồn tại: $filePath');
    }
    return file.readAsString();
  }

  Future<void> saveNote(String filePath, String content) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
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
  }) {
    final sb = StringBuffer();

    sb.write(_buildFrontMatter(subject, const {}));
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
    return '${_buildFrontMatter(subject, front)}\n${mergedBody.trimLeft()}';
  }

  /// Dựng khối front matter, giữ lại mọi khoá lạ mà người dùng tự thêm.
  String _buildFrontMatter(Subject subject, Map<String, String> existing) {
    const managed = {'code', 'name', 'semester', 'credits', 'tags'};

    // Tag mặc định của app cộng với tag người dùng tự đặt.
    final tags = <String>{
      'subject',
      'semester-${subject.semester}',
      ...MarkdownParser.parseListValue(existing['tags']),
    }.toList();

    final sb = StringBuffer()
      ..writeln('---')
      ..writeln('code: ${subject.code}')
      ..writeln('name: "${subject.name.replaceAll('"', r'\"')}"')
      ..writeln('semester: ${subject.semester}')
      ..writeln('credits: ${subject.credits}')
      ..writeln('tags: [${tags.join(', ')}]');

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

  /// Tên file chuẩn cho một môn: `<MÃ MÔN>.md`.
  /// Đặt theo mã môn để `[[PRF192]]` trong Obsidian luôn resolve được.
  String fileNameFor(Subject subject) => '${subject.code}.md';

  /// Ghi (hoặc cập nhật) file `.md` của một môn ra Vault, đồng thời lưu
  /// `note_path` vào SQLite để lần sau mở lại đúng file đó.
  Future<String> exportSubject({
    required String vaultPath,
    required Subject subject,
    List<Subject>? prerequisites,
    List<Subject>? unlocks,
  }) async {
    if (subject.id == null) {
      throw ObsidianException('Môn chưa được lưu vào CSDL.');
    }
    final prereqs = prerequisites ?? await _db.getPrerequisitesOf(subject.id!);
    final opens = unlocks ?? await _db.getUnlockedBy(subject.id!);

    // Ưu tiên ghi đè đúng file cũ nếu môn này đã từng liên kết với một file.
    final target = _resolveTargetPath(vaultPath, subject);
    final existing = File(target);

    final content = await existing.exists()
        ? mergeMarkdown(
            subject: subject,
            existingContent: await existing.readAsString(),
            prerequisites: prereqs,
            unlocks: opens,
          )
        : buildMarkdown(
            subject: subject,
            prerequisites: prereqs,
            unlocks: opens,
          );

    await saveNote(target, content);

    // Chỉ ghi lại CSDL khi đường dẫn thật sự đổi, tránh N lần UPDATE thừa.
    if (subject.notePath != target) {
      await _db.updateSubject(subject.copyWith(notePath: target));
    }
    return target;
  }

  /// File đích của một môn: giữ nguyên vị trí cũ nếu file đó còn nằm trong
  /// Vault, để người dùng sắp xếp ghi chú vào thư mục con tuỳ ý mà export
  /// không kéo ngược file ra thư mục gốc.
  String _resolveTargetPath(String vaultPath, Subject subject) {
    final saved = subject.notePath;
    if (saved != null && saved.isNotEmpty && p.isWithin(vaultPath, saved)) {
      return saved;
    }
    return p.join(vaultPath, fileNameFor(subject));
  }

  /// Ghi toàn bộ đồ thị trong SQLite ra Vault. Trả về số file đã ghi.
  Future<int> exportAll(String vaultPath) async {
    final graph = await _db.loadGraph();
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

    int bySemesterThenCode(Subject a, Subject b) => a.semester != b.semester
        ? a.semester.compareTo(b.semester)
        : a.code.compareTo(b.code);

    var written = 0;
    for (final subject in graph.subjects) {
      final id = subject.id;
      if (id == null) continue;
      await exportSubject(
        vaultPath: vaultPath,
        subject: subject,
        prerequisites: (prereqsOf[id] ?? [])..sort(bySemesterThenCode),
        unlocks: (unlocksOf[id] ?? [])..sort(bySemesterThenCode),
      );
      written++;
    }
    await _writeIndexNote(vaultPath, graph);
    return written;
  }

  Future<void> _writeIndexNote(String vaultPath, GraphData graph) async {
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

    await saveNote(p.join(vaultPath, indexFileName), sb.toString());
  }

  // ------------------------------------------------------------------
  // ĐỒNG BỘ VAULT -> SQLITE
  // ------------------------------------------------------------------

  /// Dựng kế hoạch đồng bộ mà **không ghi gì** xuống CSDL.
  ///
  /// Tách khỏi [applyPlan] để giao diện hỏi người dùng trước khi ghi đè —
  /// đặc biệt quan trọng với phần gỡ liên kết, vì thao tác đó không hoàn tác
  /// được.
  Future<VaultSyncPlan> planImport(String vaultPath) async {
    final notes = (await scanVault(
      vaultPath,
    )).where((n) => n.code.isNotEmpty && n.code != indexCode).toList();

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

    final missingInVault = graph.subjects
        .where((s) => !vaultCodes.contains(s.code))
        .toList();

    return VaultSyncPlan(
      vaultPath: vaultPath,
      notes: notes,
      toCreate: toCreate,
      toUpdate: toUpdate,
      unchanged: unchanged,
      edgesToAdd: edgesToAdd,
      edgesToRemove: edgesToRemove,
      brokenLinks: brokenLinks,
      missingInVault: missingInVault,
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
  Future<VaultSyncReport> applyPlan(VaultSyncPlan plan) async {
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

    return VaultSyncReport(
      filesScanned: plan.notes.length,
      subjectsCreated: plan.toCreate.length,
      subjectsUpdated: plan.toUpdate.length,
      edgesCreated: edgesCreated,
      edgesRemoved: edgesRemoved,
      warnings: warnings,
    );
  }

  /// Quét Vault rồi nạp thẳng vào SQLite, không hỏi gì.
  /// Dùng khi không cần bước xác nhận; ngược lại thì gọi [planImport] trước.
  Future<VaultSyncReport> importVault(String vaultPath) async =>
      applyPlan(await planImport(vaultPath));
}

class ObsidianException implements Exception {
  final String message;
  ObsidianException(this.message);
  @override
  String toString() => message;
}
