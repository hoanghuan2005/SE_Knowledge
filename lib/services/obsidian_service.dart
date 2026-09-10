import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/graph_data.dart';
import '../models/prerequisite.dart';
import '../models/subject.dart';
import 'db_service.dart';

/// Một file `.md` đã được đọc và bóc tách từ Obsidian Vault.
class ObsidianNote {
  final String filePath;
  final String fileName;
  final Map<String, String> frontMatter;
  final String body;

  /// Mọi `[[...]]` xuất hiện trong file.
  final List<String> allLinks;

  /// Chỉ các `[[...]]` nằm dưới mục "Môn tiên quyết".
  final List<String> prerequisiteLinks;

  const ObsidianNote({
    required this.filePath,
    required this.fileName,
    required this.frontMatter,
    required this.body,
    required this.allLinks,
    required this.prerequisiteLinks,
  });

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
}

/// Kết quả một lần đồng bộ Vault -> SQLite.
class VaultSyncReport {
  final int filesScanned;
  final int subjectsCreated;
  final int subjectsUpdated;
  final int edgesCreated;
  final List<String> warnings;

  const VaultSyncReport({
    required this.filesScanned,
    required this.subjectsCreated,
    required this.subjectsUpdated,
    required this.edgesCreated,
    required this.warnings,
  });

  String get summary =>
      'Đã quét $filesScanned file .md — tạo mới $subjectsCreated môn, '
      'cập nhật $subjectsUpdated môn, thêm $edgesCreated liên kết.';
}

/// Đọc / ghi Obsidian Vault bằng `dart:io` thuần.
///
/// Triết lý Local-First: file Markdown trên đĩa là nguồn sự thật của nội dung,
/// SQLite là chỉ mục (index) để truy vấn quan hệ và vẽ đồ thị.
class ObsidianService {
  ObsidianService._();
  static final ObsidianService instance = ObsidianService._();

  final DbService _db = DbService.instance;

  /// `[[Tên môn]]`, `[[Tên môn|bí danh]]`, `[[Tên môn#heading]]`.
  static final RegExp wikiLinkPattern = RegExp(r'\[\[([^\[\]]+?)\]\]');

  static const String prereqHeadingVi = '## Môn tiên quyết';
  static const String prereqHeadingEn = '## Prerequisites';
  static const String unlockHeadingVi = '## Mở ra các môn';

  // ------------------------------------------------------------------
  // PARSE
  // ------------------------------------------------------------------

  /// Bóc tách mọi wiki link trong một chuỗi Markdown.
  /// Bỏ phần alias sau `|` và phần heading sau `#`.
  static List<String> parseWikiLinks(String content) {
    final result = <String>[];
    for (final m in wikiLinkPattern.allMatches(content)) {
      final target = _normalizeLink(m.group(1) ?? '');
      if (target.isNotEmpty && !result.contains(target)) {
        result.add(target);
      }
    }
    return result;
  }

  static String _normalizeLink(String raw) {
    var target = raw.split('|').first;
    target = target.split('#').first;
    return target.trim();
  }

  /// Tách front matter YAML đơn giản (`key: value`) ra khỏi phần nội dung.
  static (Map<String, String>, String) splitFrontMatter(String content) {
    final normalized = content.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) {
      return (const {}, normalized);
    }
    final end = normalized.indexOf('\n---', 3);
    if (end == -1) {
      return (const {}, normalized);
    }

    final rawBlock = normalized.substring(4, end);
    final map = <String, String>{};
    for (final line in rawBlock.split('\n')) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      var value = line.substring(idx + 1).trim();
      if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        value = value.substring(1, value.length - 1);
      }
      if (key.isNotEmpty) map[key] = value;
    }

    var bodyStart = end + 4;
    if (bodyStart < normalized.length && normalized[bodyStart] == '\n') {
      bodyStart++;
    }
    if (bodyStart > normalized.length) bodyStart = normalized.length;
    return (map, normalized.substring(bodyStart));
  }

  /// Lấy các wiki link nằm trong đoạn dưới một heading cụ thể.
  static List<String> linksUnderHeading(String body, List<String> headings) {
    final lines = body.replaceAll('\r\n', '\n').split('\n');
    final collected = <String>[];
    var inside = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#')) {
        inside = headings.any(
          (h) => trimmed.toLowerCase().startsWith(h.toLowerCase()),
        );
        continue;
      }
      if (inside) collected.addAll(parseWikiLinks(line));
    }
    return collected.toSet().toList();
  }

  ObsidianNote parseNote(String filePath, String content) {
    final (front, body) = splitFrontMatter(content);
    return ObsidianNote(
      filePath: filePath,
      fileName: p.basename(filePath),
      frontMatter: front,
      body: body,
      allLinks: parseWikiLinks(body),
      prerequisiteLinks: linksUnderHeading(body, [
        prereqHeadingVi,
        prereqHeadingEn,
      ]),
    );
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

  Future<void> deleteNote(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }

  // ------------------------------------------------------------------
  // GHI FILE MARKDOWN
  // ------------------------------------------------------------------

  /// Sinh nội dung `.md` cho một môn, có front matter và các `[[...]]`.
  String buildMarkdown({
    required Subject subject,
    List<Subject> prerequisites = const [],
    List<Subject> unlocks = const [],
    String? extraBody,
  }) {
    final sb = StringBuffer();

    sb.writeln('---');
    sb.writeln('code: ${subject.code}');
    sb.writeln('name: "${subject.name.replaceAll('"', r'\"')}"');
    sb.writeln('semester: ${subject.semester}');
    sb.writeln('credits: ${subject.credits}');
    sb.writeln('tags: [subject, semester-${subject.semester}]');
    sb.writeln('---');
    sb.writeln();
    sb.writeln('# ${subject.code} — ${subject.name}');
    sb.writeln();

    if (subject.description.trim().isNotEmpty) {
      sb.writeln(subject.description.trim());
      sb.writeln();
    }

    sb.writeln(prereqHeadingVi);
    if (prerequisites.isEmpty) {
      sb.writeln('- _Không có (môn nền tảng)_');
    } else {
      for (final s in prerequisites) {
        sb.writeln('- [[${s.code}]] — ${s.name}');
      }
    }
    sb.writeln();

    sb.writeln(unlockHeadingVi);
    if (unlocks.isEmpty) {
      sb.writeln('- _Chưa có môn nào phụ thuộc_');
    } else {
      for (final s in unlocks) {
        sb.writeln('- [[${s.code}]] — ${s.name}');
      }
    }
    sb.writeln();

    sb.writeln('## Ghi chú');
    sb.writeln((extraBody ?? '').trim().isEmpty ? '' : extraBody!.trim());

    return sb.toString();
  }

  /// Tên file chuẩn cho một môn: `<MÃ MÔN>.md`.
  /// Đặt theo mã môn để `[[PRF192]]` trong Obsidian luôn resolve được.
  String fileNameFor(Subject subject) => '${subject.code}.md';

  /// Ghi (hoặc ghi đè) file `.md` của một môn ra Vault, đồng thời lưu
  /// `note_path` vào SQLite để lần sau mở lại đúng file đó.
  Future<String> exportSubject({
    required String vaultPath,
    required Subject subject,
  }) async {
    if (subject.id == null) {
      throw ObsidianException('Môn chưa được lưu vào CSDL.');
    }
    final prereqs = await _db.getPrerequisitesOf(subject.id!);
    final unlocks = await _db.getUnlockedBy(subject.id!);

    final target = p.join(vaultPath, fileNameFor(subject));
    String? extra;
    final existing = File(target);
    if (await existing.exists()) {
      final old = parseNote(target, await existing.readAsString());
      extra = _extractSection(old.body, '## Ghi chú');
    }

    final content = buildMarkdown(
      subject: subject,
      prerequisites: prereqs,
      unlocks: unlocks,
      extraBody: extra,
    );
    await saveNote(target, content);
    await _db.updateSubject(subject.copyWith(notePath: target));
    return target;
  }

  /// Ghi toàn bộ đồ thị trong SQLite ra Vault. Trả về số file đã ghi.
  Future<int> exportAll(String vaultPath) async {
    final graph = await _db.loadGraph();
    var written = 0;
    for (final subject in graph.subjects) {
      await exportSubject(vaultPath: vaultPath, subject: subject);
      written++;
    }
    await _writeIndexNote(vaultPath, graph);
    return written;
  }

  Future<void> _writeIndexNote(String vaultPath, GraphData graph) async {
    final sb = StringBuffer();
    sb.writeln('---');
    sb.writeln('code: INDEX');
    sb.writeln('name: "Bản đồ tri thức"');
    sb.writeln('tags: [index]');
    sb.writeln('---');
    sb.writeln();
    sb.writeln('# Bản đồ tri thức môn học');
    sb.writeln();

    final semesters = graph.subjects.map((s) => s.semester).toSet().toList()
      ..sort();
    for (final sem in semesters) {
      sb.writeln('## Kỳ $sem');
      for (final s in graph.subjects.where((x) => x.semester == sem)) {
        sb.writeln('- [[${s.code}]] — ${s.name} (${s.credits} tín chỉ)');
      }
      sb.writeln();
    }

    await saveNote(p.join(vaultPath, '_INDEX.md'), sb.toString());
  }

  /// Lấy nguyên văn phần nội dung dưới một heading, để không ghi đè
  /// ghi chú người dùng tự viết khi export lại.
  String? _extractSection(String body, String heading) {
    final lines = body.replaceAll('\r\n', '\n').split('\n');
    final out = <String>[];
    var inside = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#')) {
        if (inside) break;
        inside = trimmed.toLowerCase() == heading.toLowerCase();
        continue;
      }
      if (inside) out.add(line);
    }
    final text = out.join('\n').trim();
    return text.isEmpty ? null : text;
  }

  // ------------------------------------------------------------------
  // ĐỒNG BỘ VAULT -> SQLITE
  // ------------------------------------------------------------------

  /// Quét Vault rồi nạp vào SQLite: mỗi file `.md` thành một node,
  /// mỗi `[[...]]` dưới mục "Môn tiên quyết" thành một edge.
  Future<VaultSyncReport> importVault(String vaultPath) async {
    final notes = await scanVault(vaultPath);
    final warnings = <String>[];

    var created = 0;
    var updated = 0;
    var edgesCreated = 0;

    // Lượt 1: tạo/cập nhật toàn bộ node trước, để lượt 2 luôn tìm thấy đích.
    final idByCode = <String, int>{};
    for (final note in notes) {
      if (note.code.isEmpty || note.code == 'INDEX') continue;

      final existing = await _db.getSubjectByCode(note.code);
      final subject = Subject.create(
        code: note.code,
        name: note.name,
        semester: note.semester,
        credits: note.credits,
        description: note.description,
        notePath: note.filePath,
      );
      final id = await _db.upsertSubjectByCode(subject);
      idByCode[note.code] = id;
      if (existing == null) {
        created++;
      } else {
        updated++;
      }
    }

    // Lượt 2: dựng các liên kết nơ-ron giữa những node đã có.
    for (final note in notes) {
      final subjectId = idByCode[note.code];
      if (subjectId == null) continue;

      for (final link in note.prerequisiteLinks) {
        final targetCode = link.toUpperCase();
        final prereqId = idByCode[targetCode];
        if (prereqId == null) {
          warnings.add(
            '${note.code}: liên kết [[$link]] không trỏ tới file .md nào.',
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
            warnings.add('${note.code} -> $targetCode: ${e.message}');
          }
        }
      }
    }

    return VaultSyncReport(
      filesScanned: notes.length,
      subjectsCreated: created,
      subjectsUpdated: updated,
      edgesCreated: edgesCreated,
      warnings: warnings,
    );
  }
}

class ObsidianException implements Exception {
  final String message;
  ObsidianException(this.message);
  @override
  String toString() => message;
}
