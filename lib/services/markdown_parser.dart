/// Bóc tách cú pháp Markdown kiểu Obsidian: `[[wiki link]]` và `#tag`.
///
/// File này là **thuần Dart**: không `dart:io`, không SQLite, không Flutter.
/// Nhờ vậy chạy được bằng `flutter test` mà không cần Visual Studio, và là nơi
/// duy nhất trong app chứa logic regex — mọi tầng khác chỉ gọi vào đây.
///
/// Kết quả trả về có kèm vị trí ký tự (`start`/`end`) và tên section cha, để
/// tầng giao diện vẽ được nút bấm, thẻ màu và dropdown mà không phải tự parse
/// lại chuỗi lần nữa.
library;

/// Một `[[...]]` đã bóc tách.
///
/// Cú pháp đầy đủ mà Obsidian hỗ trợ: `[[Đích#Heading|Bí danh]]`.
class WikiLink {
  /// Nguyên văn gồm cả hai cặp ngoặc, ví dụ `[[CSD201|Cấu trúc dữ liệu]]`.
  final String raw;

  /// Phần đích sau khi đã bỏ alias và heading, ví dụ `CSD201`.
  final String target;

  /// Phần sau dấu `|`, là chữ người dùng muốn hiển thị. Có thể null.
  final String? alias;

  /// Phần sau dấu `#`, trỏ tới một heading bên trong file đích. Có thể null.
  final String? heading;

  /// Vị trí trong phần body (đã bỏ front matter), dùng để tô màu / bắt click.
  final int start;
  final int end;

  /// Tên heading cấp gần nhất phía trên link, ví dụ `Môn tiên quyết`.
  /// Rỗng nếu link nằm ngoài mọi heading.
  final String section;

  const WikiLink({
    required this.raw,
    required this.target,
    required this.start,
    required this.end,
    this.alias,
    this.heading,
    this.section = '',
  });

  /// Chữ nên hiện trên nút bấm: ưu tiên bí danh, không có thì lấy đích.
  String get display =>
      (alias?.trim().isNotEmpty ?? false) ? alias!.trim() : target;

  /// Mã môn đã chuẩn hoá để tra cứu trong SQLite.
  String get code => target.trim().toUpperCase();

  /// Link này có nằm dưới mục "Môn tiên quyết" không.
  bool get isPrerequisite => MarkdownParser.isPrerequisiteHeading(section);

  @override
  String toString() => 'WikiLink($target)';
}

/// Một hashtag `#tag` đã bóc tách.
class MdTag {
  /// Nguyên văn kèm dấu thăng, ví dụ `#core/backend`.
  final String raw;

  /// Tên tag đã bỏ dấu thăng, ví dụ `core/backend`.
  final String name;

  final int start;
  final int end;

  /// `true` nếu tag lấy từ front matter `tags:` chứ không phải viết trong body.
  /// Tag front matter không có vị trí thật trong body nên `start`/`end` là -1.
  final bool fromFrontMatter;

  const MdTag({
    required this.raw,
    required this.name,
    this.start = -1,
    this.end = -1,
    this.fromFrontMatter = false,
  });

  /// Tag lồng nhau `#a/b/c` tách thành `['a', 'b', 'c']`.
  List<String> get parts => name.split('/').where((e) => e.isNotEmpty).toList();

  /// Cấp ngoài cùng, dùng để gom nhóm thẻ màu trên giao diện.
  String get root => parts.isEmpty ? name : parts.first;

  @override
  String toString() => '#$name';

  @override
  bool operator ==(Object other) =>
      other is MdTag &&
      other.name == name &&
      other.start == start &&
      other.fromFrontMatter == fromFrontMatter;

  @override
  int get hashCode => Object.hash(name, start, fromFrontMatter);
}

/// Một file `.md` đã bóc tách xong phần cú pháp (chưa gắn với môn học nào).
class ParsedNote {
  final Map<String, String> frontMatter;

  /// Nội dung sau khi đã cắt bỏ khối front matter.
  final String body;

  final List<WikiLink> links;
  final List<MdTag> tags;

  const ParsedNote({
    required this.frontMatter,
    required this.body,
    required this.links,
    required this.tags,
  });

  /// Chỉ những link nằm dưới mục "Môn tiên quyết".
  List<WikiLink> get prerequisiteLinks =>
      links.where((l) => l.isPrerequisite).toList();

  /// Danh sách đích không trùng lặp, giữ nguyên thứ tự xuất hiện.
  List<String> get linkTargets {
    final seen = <String>{};
    return [
      for (final l in links)
        if (seen.add(l.target)) l.target,
    ];
  }

  /// Tên tag không trùng lặp, gộp cả tag front matter lẫn tag viết trong body.
  List<String> get tagNames {
    final seen = <String>{};
    return [
      for (final t in tags)
        if (seen.add(t.name)) t.name,
    ];
  }
}

/// Toàn bộ logic regex của app gom về một chỗ.
class MarkdownParser {
  MarkdownParser._();

  /// `[[Đích]]`, `[[Đích#Heading]]`, `[[Đích|Bí danh]]`, `[[Đích#Heading|Bí danh]]`.
  ///
  /// Ba nhóm bắt: đích, heading, bí danh.
  static final RegExp wikiLinkPattern = RegExp(
    r'\[\[([^\[\]|#]+?)(?:#([^\[\]|]*?))?(?:\|([^\[\]]*?))?\]\]',
  );

  /// `#tag`, `#tag/con`, hỗ trợ chữ có dấu tiếng Việt.
  ///
  /// Lookbehind chặn ba ca dương tính giả hay gặp nhất: `## Heading` (dấu
  /// thăng thứ hai), `abc#tag` (thăng dính sau chữ), và dấu thăng thứ hai
  /// trong một chuỗi thăng liên tiếp. Ca `# Tiêu đề` tự loại vì ngay sau dấu
  /// thăng là khoảng trắng.
  static final RegExp tagPattern = RegExp(
    r'(?<![\p{L}\p{N}_/#-])#([\p{L}\p{N}_][\p{L}\p{N}_/-]*)',
    unicode: true,
  );

  static final RegExp _fencedCodePattern = RegExp(
    r'^[ \t]*(```|~~~)[\s\S]*?^[ \t]*\1[^\n]*$',
    multiLine: true,
  );
  static final RegExp _inlineCodePattern = RegExp(r'`[^`\n]*`');
  static final RegExp _urlPattern = RegExp(r'(?:https?|obsidian|file)://\S+');
  static final RegExp _headingPattern = RegExp(r'^(#{1,6})\s+(.*)$');
  static final RegExp _digitsOnly = RegExp(r'^\d+$');
  static final RegExp _trailingSeparators = RegExp(r'[/-]+$');
  static final RegExp _leadingHashes = RegExp(r'^#+');

  /// Các heading được coi là mục liệt kê môn tiên quyết.
  static const List<String> prerequisiteHeadings = [
    'môn tiên quyết',
    'tiên quyết',
    'prerequisites',
    'prerequisite',
  ];

  /// Các heading được coi là mục liệt kê môn mở ra sau.
  static const List<String> unlockHeadings = [
    'mở ra các môn',
    'mở ra',
    'unlocks',
    'leads to',
  ];

  static String _normalizeHeading(String heading) =>
      heading.replaceAll(_leadingHashes, '').trim().toLowerCase();

  static bool isPrerequisiteHeading(String heading) =>
      prerequisiteHeadings.contains(_normalizeHeading(heading));

  static bool isUnlockHeading(String heading) =>
      unlockHeadings.contains(_normalizeHeading(heading));

  static final RegExp _closingHashes = RegExp(r'\s+#+$');
  static final RegExp _emphasisEdges = RegExp(r'^[*_]+|[*_]+$');
  static final RegExp _trailingColon = RegExp(r'[:：]+$');
  static final RegExp _spaces = RegExp(r'\s+');

  /// Như [isPrerequisiteHeading] nhưng chịu được các biến thể người dùng hay
  /// gõ tay trong Obsidian: `## Môn tiên quyết ##`, `## Môn tiên quyết:`,
  /// `## **Môn tiên quyết**`. Chỉ dùng lúc nạp Vault; phần ghi ra Vault vẫn
  /// nhận heading theo [isPrerequisiteHeading] như cũ.
  static bool isPrerequisiteHeadingLoose(String heading) {
    var h = heading.replaceAll(_leadingHashes, '').trim();
    h = h.replaceAll(_closingHashes, '').trim();
    h = h.replaceAll(_emphasisEdges, '').trim();
    h = h.replaceAll(_trailingColon, '').trim();
    h = h.replaceAll(_emphasisEdges, '').trim();
    return prerequisiteHeadings.contains(
      h.replaceAll(_spaces, ' ').toLowerCase(),
    );
  }

  /// Các `[[...]]` thuộc mục tiên quyết, **kể cả dưới heading con** của mục
  /// đó (`## Môn tiên quyết` > `### Bắt buộc` > `- [[PRF192]]`).
  ///
  /// [WikiLink.isPrerequisite] chỉ nhìn heading gần nhất nên bỏ sót ca heading
  /// con; hàm này đi theo cấp heading. `hasSection` cho biết file có khai mục
  /// tiên quyết hay không — không khai thì lúc nạp không được suy ra "môn này
  /// không có tiên quyết" để gỡ cạnh đang có.
  static ({bool hasSection, List<WikiLink> links}) prerequisiteLinksDeep(
    String body,
  ) {
    final normalized = body.replaceAll('\r\n', '\n');
    // Heading nằm trong khối code không phải heading thật.
    final masked = maskCode(normalized);

    final ranges = <(int, int)>[];
    final stack = <(int, bool)>[]; // (cấp heading, là mục tiên quyết)
    var hasSection = false;
    var offset = 0;
    int? rangeStart;

    for (final line in masked.split('\n')) {
      final match = _headingPattern.firstMatch(line);
      if (match != null) {
        final level = match.group(1)!.length;
        while (stack.isNotEmpty && stack.last.$1 >= level) {
          stack.removeLast();
        }
        final isPrereq = isPrerequisiteHeadingLoose(match.group(2)!);
        if (isPrereq) hasSection = true;
        stack.add((level, isPrereq));

        final inside = stack.any((e) => e.$2);
        if (inside && rangeStart == null) {
          rangeStart = offset;
        } else if (!inside && rangeStart != null) {
          ranges.add((rangeStart, offset));
          rangeStart = null;
        }
      }
      offset += line.length + 1;
    }
    if (rangeStart != null) ranges.add((rangeStart, normalized.length + 1));

    final links = [
      for (final l in parseLinks(normalized))
        if (ranges.any((r) => l.start >= r.$1 && l.start < r.$2)) l,
    ];
    return (hasSection: hasSection, links: links);
  }

  // ------------------------------------------------------------------
  // FRONT MATTER
  // ------------------------------------------------------------------

  /// Tách khối front matter YAML ở đầu file ra khỏi phần nội dung.
  ///
  /// Hỗ trợ `key: value`, giá trị bọc nháy, danh sách một dòng `tags: [a, b]`
  /// và danh sách YAML nhiều dòng:
  ///
  ///     tags:
  ///       - subject
  ///       - semester-2
  ///
  /// Danh sách nhiều dòng được gộp thành `a, b` để giữ nguyên kiểu trả về
  /// `Map<String, String>` mà phần còn lại của app đang dùng.
  static (Map<String, String>, String) splitFrontMatter(String content) {
    final normalized = content.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) {
      return (const {}, normalized);
    }
    final end = normalized.indexOf('\n---', 3);
    if (end == -1) {
      return (const {}, normalized);
    }

    // `---` đóng ngay sau `---` mở (khối properties rỗng) thì `end` == 3, nhỏ
    // hơn điểm bắt đầu khối — cắt thẳng sẽ ném RangeError và làm hỏng cả lượt
    // nạp Vault chỉ vì một file template.
    final rawBlock = end > 4 ? normalized.substring(4, end) : '';
    final map = <String, String>{};
    final listBuffer = <String, List<String>>{};
    String? currentListKey;

    for (final line in rawBlock.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Dòng con của một danh sách YAML nhiều dòng.
      if (trimmed.startsWith('- ') || trimmed == '-') {
        if (currentListKey != null) {
          final item = _unquote(trimmed.substring(1).trim());
          if (item.isNotEmpty) {
            listBuffer.putIfAbsent(currentListKey, () => []).add(item);
          }
        }
        continue;
      }

      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      if (key.isEmpty) continue;

      final value = _unquote(line.substring(idx + 1).trim());
      if (value.isEmpty) {
        // `tags:` rồi xuống dòng -> chờ các dòng `- ...` phía dưới.
        currentListKey = key;
        map[key] = '';
      } else {
        currentListKey = null;
        map[key] = value;
      }
    }

    for (final entry in listBuffer.entries) {
      map[entry.key] = entry.value.join(', ');
    }

    var bodyStart = end + 4;
    if (bodyStart < normalized.length && normalized[bodyStart] == '\n') {
      bodyStart++;
    }
    if (bodyStart > normalized.length) bodyStart = normalized.length;
    return (map, normalized.substring(bodyStart));
  }

  static String _unquote(String raw) {
    var value = raw.trim();
    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      final quoted =
          (first == '"' && last == '"') || (first == "'" && last == "'");
      if (quoted) value = value.substring(1, value.length - 1);
      // Lúc xuất, `"` trong chuỗi nháy kép được escape thành `\"`. Không bỏ
      // escape thì mỗi vòng xuất -> nạp lại dài thêm một dấu `\`.
      if (first == '"' && last == '"') value = value.replaceAll(r'\"', '"');
    }
    return value;
  }

  /// Đọc một giá trị front matter dạng danh sách: `[a, b]` hoặc `a, b`.
  static List<String> parseListValue(String? raw) {
    if (raw == null) return const [];
    var value = raw.trim();
    if (value.isEmpty) return const [];
    if (value.startsWith('[') && value.endsWith(']')) {
      value = value.substring(1, value.length - 1);
    }
    return value
        .split(',')
        .map((e) => _unquote(e).replaceFirst(_leadingHashes, '').trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  // ------------------------------------------------------------------
  // CHE NGỮ CẢNH GIẢ
  // ------------------------------------------------------------------

  /// Thay một đoạn bằng khoảng trắng **cùng độ dài**, giữ nguyên ký tự xuống
  /// dòng. Giữ nguyên độ dài là điều kiện bắt buộc để `start`/`end` vẫn khớp
  /// với chuỗi gốc sau khi che.
  static String _blankOut(String source, Iterable<Match> matches) {
    final list = matches.toList();
    if (list.isEmpty) return source;

    final chars = source.split('');
    for (final m in list) {
      for (var i = m.start; i < m.end; i++) {
        if (chars[i] != '\n') chars[i] = ' ';
      }
    }
    return chars.join();
  }

  /// Che khối code ba dấu huyền và code inline một dấu huyền.
  /// Dùng trước khi dò `[[...]]` để link trong ví dụ code không bị tính.
  static String maskCode(String body) {
    var masked = _blankOut(body, _fencedCodePattern.allMatches(body));
    masked = _blankOut(masked, _inlineCodePattern.allMatches(masked));
    return masked;
  }

  // ------------------------------------------------------------------
  // SECTION
  // ------------------------------------------------------------------

  /// Chia body thành các khoảng ký tự theo heading cấp gần nhất phía trên.
  static List<HeadingSpan> sectionSpans(String body) {
    final spans = <HeadingSpan>[];
    var offset = 0;
    var currentTitle = '';
    var currentStart = 0;

    for (final line in body.split('\n')) {
      final match = _headingPattern.firstMatch(line);
      if (match != null) {
        spans.add(HeadingSpan(currentTitle, currentStart, offset));
        currentTitle = match.group(2)!.trim();
        currentStart = offset + line.length;
      }
      offset += line.length + 1;
    }
    spans.add(HeadingSpan(currentTitle, currentStart, body.length + 1));
    return spans;
  }

  static String _sectionAt(int offset, List<HeadingSpan> spans) {
    for (final s in spans) {
      if (offset >= s.start && offset < s.end) return s.title;
    }
    return '';
  }

  // ------------------------------------------------------------------
  // BÓC TÁCH
  // ------------------------------------------------------------------

  /// Dò mọi `[[...]]` trong body, kèm vị trí và section cha.
  /// Link nằm trong khối code bị bỏ qua.
  static List<WikiLink> parseLinks(String body) {
    final normalized = body.replaceAll('\r\n', '\n');
    final masked = maskCode(normalized);
    // Chia section trên bản đã che code: một dòng `## Môn tiên quyết` nằm
    // trong ví dụ code không được tính là heading thật, nếu không mọi link
    // phía sau bị gán nhầm section và lúc nhập Vault sẽ sinh cạnh tiên quyết
    // không có thật. Che giữ nguyên độ dài nên chỉ số vẫn khớp chuỗi gốc.
    final spans = sectionSpans(masked);
    final result = <WikiLink>[];

    for (final m in wikiLinkPattern.allMatches(masked)) {
      final target = (m.group(1) ?? '').trim();
      if (target.isEmpty) continue;

      final heading = m.group(2)?.trim();
      final alias = m.group(3)?.trim();

      result.add(
        WikiLink(
          raw: normalized.substring(m.start, m.end),
          target: target,
          heading: (heading == null || heading.isEmpty) ? null : heading,
          alias: (alias == null || alias.isEmpty) ? null : alias,
          start: m.start,
          end: m.end,
          section: _sectionAt(m.start, spans),
        ),
      );
    }
    return result;
  }

  /// Dò mọi `#tag` trong body, kèm vị trí.
  ///
  /// Bỏ qua: khối code, code inline, URL, phần `#heading` bên trong `[[...]]`,
  /// và dấu thăng mở đầu heading Markdown.
  static List<MdTag> parseTags(String body) {
    final normalized = body.replaceAll('\r\n', '\n');

    // Che theo đúng thứ tự: code trước, rồi wiki link, rồi URL.
    var masked = maskCode(normalized);
    masked = _blankOut(masked, wikiLinkPattern.allMatches(masked));
    masked = _blankOut(masked, _urlPattern.allMatches(masked));

    final result = <MdTag>[];
    for (final m in tagPattern.allMatches(masked)) {
      // Bỏ dấu phân cách thừa ở đuôi, ví dụ `#tag/` hay `#tag-`.
      final name = (m.group(1) ?? '').replaceAll(_trailingSeparators, '');
      if (name.isEmpty) continue;

      // `#1` trong một danh sách đánh số không phải tag.
      if (_digitsOnly.hasMatch(name)) continue;

      result.add(
        MdTag(
          raw: '#$name',
          name: name,
          start: m.start,
          end: m.start + name.length + 1,
        ),
      );
    }
    return result;
  }

  /// Bóc tách trọn vẹn một file `.md`.
  static ParsedNote parse(String content) {
    final (front, body) = splitFrontMatter(content);

    final tags = <MdTag>[
      for (final name in parseListValue(front['tags']))
        MdTag(raw: '#$name', name: name, fromFrontMatter: true),
      ...parseTags(body),
    ];

    return ParsedNote(
      frontMatter: front,
      body: body,
      links: parseLinks(body),
      tags: tags,
    );
  }
}

/// Khoảng ký tự thuộc về một heading trong body.
class HeadingSpan {
  final String title;
  final int start;
  final int end;
  const HeadingSpan(this.title, this.start, this.end);
}
