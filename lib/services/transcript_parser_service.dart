import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/transcript_entry.dart';

/// Bóc tách file `StudentTranscript_<MSSV>.xls` tải từ FAP.
///
/// Thuần Dart: không `dart:io`, không `sqflite`, không widget — nhờ vậy chạy
/// được bằng `flutter test` trên máy chưa cài Visual Studio, giống
/// `markdown_parser.dart`.
///
/// Ba điều về file này khác hẳn với tên gọi của nó:
///
/// 1. Đuôi `.xls` nhưng **không phải Excel**: nội dung là HTML rời, chỉ có các
///    thẻ `<Table>`, không có `<html>`/`<head>`/`<body>`.
/// 2. Encoding **UTF-16 Little Endian có BOM**, nên `utf8.decode` cho ra rác.
/// 3. Số ô mỗi dòng **không cố định**: dòng đã học có 11 ô, dòng `Studying` /
///    `Not started` chỉ có 10 (thiếu hẳn ô cờ `*`). Vì vậy mọi ô đều được đọc
///    theo chỉ số suy từ `<thead>` chứ không đếm từ cuối dòng.
class TranscriptParserService {
  TranscriptParserService._();
  static final TranscriptParserService instance = TranscriptParserService._();

  /// Mã sinh viên nằm trong tên file: `StudentTranscript_SE193040.xls`.
  static final RegExp _studentCodePattern =
      RegExp(r'([A-Z]{2}\d{5,8})', caseSensitive: false);

  static final RegExp _semesterPattern =
      RegExp(r'^(spring|summer|fall)\s*(\d{4})$');

  /// Giải mã mảng byte thô thành chuỗi.
  ///
  /// FAP xuất transcript dưới dạng HTML UTF-16LE nhưng đặt đuôi `.xls`. Đọc
  /// bằng `utf8.decode` sẽ ra chuỗi rác, nên phải dò BOM trước.
  String decodeBytes(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16Le(bytes, 2);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      // UTF-16BE: đảo từng cặp byte rồi đọc như LE, khỏi viết hai bộ giải mã.
      final swapped = Uint8List(bytes.length);
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        swapped[i] = bytes[i + 1];
        swapped[i + 1] = bytes[i];
      }
      return _decodeUtf16Le(swapped, 2);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Đọc từng cặp byte thành một mã UTF-16.
  ///
  /// Không dùng `buffer.asUint16List` vì view đó đòi offset chia hết cho 2
  /// trên mảng nền — điều không phải lúc nào cũng đúng với [Uint8List] lấy từ
  /// một file đã được cắt sẵn.
  String _decodeUtf16Le(Uint8List bytes, int start) {
    final units = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      units.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }

  /// Đường vào tiện nhất cho tầng giao diện: nhận thẳng byte của file.
  TranscriptParseResult parseBytes(Uint8List bytes, {String? fileName}) =>
      parse(decodeBytes(bytes), fileName: fileName);

  /// Duyệt **mọi** bảng trong tài liệu: transcript có hai bảng (bảng chính 11
  /// cột và bảng môn tiếng Anh dự bị 7 cột), bỏ sót bảng nào là mất điểm của
  /// mấy môn đó.
  TranscriptParseResult parse(String html, {String? fileName}) {
    final entries = <TranscriptEntry>[];
    final warnings = <String>[];
    final importedAt = DateTime.now();

    // `package:html` tự vá cây DOM thiếu <html>/<body>, nên file rời của FAP
    // vẫn duyệt được như một tài liệu bình thường.
    final document = html_parser.parse(html);

    var tableNo = 0;
    for (final table in document.querySelectorAll('table')) {
      final columns = _readHeader(table);
      // Thẻ <Table> cuối file không đóng đúng cách nên trình phân tích sinh ra
      // vài bảng rỗng ăn theo. Bảng không có tiêu đề nhận ra được thì bỏ qua,
      // đó không phải dữ liệu bị hỏng.
      if (columns == null) continue;
      tableNo++;

      for (final row in _dataRows(table)) {
        final cells = row.querySelectorAll('td');

        // Dòng chú thích "(*) Môn điều kiện tốt nghiệp..." nằm lọt giữa hai
        // bảng và chỉ có đúng một ô gộp. Đây là ghi chú của FAP, không phải
        // dòng dữ liệu hỏng, nên bỏ qua im lặng.
        if (cells.length <= 1) continue;

        final entry = _readRow(
          cells: cells,
          columns: columns,
          importedAt: importedAt,
          warnings: warnings,
          tableNo: tableNo,
        );
        if (entry != null) entries.add(entry);
      }
    }

    return TranscriptParseResult(
      entries: entries,
      warnings: warnings,
      studentCode: _studentCodeFromFileName(fileName),
    );
  }

  /// Ánh xạ tên cột -> chỉ số, lấy từ `<thead>`.
  ///
  /// Trả `null` khi bảng không có cột `Subject Code` — khi đó nó không phải
  /// bảng điểm.
  _ColumnMap? _readHeader(dom.Element table) {
    var headerCells = table.querySelectorAll('thead th');
    if (headerCells.isEmpty) headerCells = table.querySelectorAll('tr th');
    if (headerCells.isEmpty) return null;

    final map = _ColumnMap();
    for (var i = 0; i < headerCells.length; i++) {
      final key = _normalizeHeader(headerCells[i].text);
      switch (key) {
        case 'term':
          map.term = i;
        case 'semester':
          map.semester = i;
        case 'subjectcode':
          map.code = i;
        case 'prerequisite':
          map.prerequisite = i;
        case 'replacedsubject':
          map.replaced = i;
        case 'subjectname':
          map.name = i;
        case 'credit':
        case 'credits':
          map.credits = i;
        case 'grade':
          map.grade = i;
        case 'status':
          map.status = i;
        case '':
          // Cột cuối không có tiêu đề chính là cột cờ `*` (môn điều kiện tốt
          // nghiệp). Cột `No` cũng có tiêu đề nên không lẫn vào đây.
          if (i > 0) map.graduationFlag = i;
      }
    }
    return map.code == null ? null : map;
  }

  /// Bỏ khoảng trắng, dấu câu và chữ hoa để `Subject Code` và `SubjectCode`
  /// (hai bảng viết khác nhau) quy về cùng một khoá.
  String _normalizeHeader(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  /// Các `<tr>` chứa dữ liệu: ưu tiên `<tbody>`, không có thì lấy mọi `<tr>`
  /// không nằm trong `<thead>`.
  List<dom.Element> _dataRows(dom.Element table) {
    final body = table.querySelectorAll('tbody tr');
    if (body.isNotEmpty) return body;
    return table
        .querySelectorAll('tr')
        .where((tr) => tr.querySelectorAll('th').isEmpty)
        .toList();
  }

  /// Đọc một dòng. Luôn kiểm tra độ dài trước khi truy cập vì dòng `Studying`
  /// và `Not started` thiếu ô cuối.
  TranscriptEntry? _readRow({
    required List<dom.Element> cells,
    required _ColumnMap columns,
    required DateTime importedAt,
    required List<String> warnings,
    required int tableNo,
  }) {
    String cell(int? index) {
      if (index == null || index < 0 || index >= cells.length) return '';
      // Điểm và trạng thái nằm trong <span class='label ...'>, nên phải lấy
      // textContent của cả ô chứ không đọc thô innerHTML.
      return cells[index].text.trim();
    }

    final rawCode = cell(columns.code);
    if (rawCode.isEmpty) {
      warnings.add(
        'Bảng $tableNo: bỏ qua một dòng vì ô mã môn để trống.',
      );
      return null;
    }

    final semesterLabel = cell(columns.semester);
    final parsedSemester = parseSemester(semesterLabel);

    final rawStatus = cell(columns.status);
    final status = parseStatus(rawStatus);
    if (status == SubjectStatus.unknown && rawStatus.isNotEmpty) {
      warnings.add(
        'Bảng $tableNo, môn $rawCode: không hiểu trạng thái "$rawStatus", '
        'dòng này không được tính vào GPA.',
      );
    }

    // Môn chưa học để trống ô Credit -> 0, không được ném lỗi.
    final credits = int.tryParse(cell(columns.credits)) ?? 0;
    // Điểm có thể là số nguyên ("10") nên phải dùng double.tryParse.
    final grade = double.tryParse(cell(columns.grade).replaceAll(',', '.'));

    final isGraduationCondition = cell(columns.graduationFlag).contains('*');

    return TranscriptEntry(
      subjectCode: rawCode.toUpperCase(),
      subjectName: cell(columns.name),
      term: int.tryParse(cell(columns.term)),
      semesterLabel: semesterLabel,
      semesterYear: parsedSemester?.year,
      season: parsedSemester?.season,
      semesterOrder: parsedSemester?.order ?? 0,
      credits: credits,
      grade: grade,
      status: status,
      isGraduationCondition: isGraduationCondition,
      countsTowardGpa: TranscriptEntry.countsTowardGpaByDefault(
        status: status,
        grade: grade,
        credits: credits,
        isGraduationCondition: isGraduationCondition,
      ),
      rawPrerequisite: cell(columns.prerequisite),
      replacedSubject: cell(columns.replaced),
      importedAt: importedAt,
    );
  }

  /// `Fall2023` -> năm 2023, [Season.fall], khoá sắp xếp `20233`.
  ///
  /// Trả `null` khi ô kỳ để trống (môn chưa học) — đó là trạng thái bình
  /// thường chứ không phải dữ liệu hỏng.
  ParsedSemester? parseSemester(String raw) {
    final match = _semesterPattern.firstMatch(raw.trim().toLowerCase());
    if (match == null) return null;

    final season = switch (match.group(1)) {
      'spring' => Season.spring,
      'summer' => Season.summer,
      _ => Season.fall,
    };
    final year = int.parse(match.group(2)!);
    return ParsedSemester(
      year: year,
      season: season,
      order: year * 10 + season.rank,
    );
  }

  /// Chuỗi trạng thái của FAP -> enum. Không nhận ra thì trả
  /// [SubjectStatus.unknown] để phía gọi ghi cảnh báo.
  SubjectStatus parseStatus(String raw) {
    final key = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return switch (key) {
      'passed' => SubjectStatus.passed,
      'not passed' || 'failed' || 'fail' => SubjectStatus.notPassed,
      'studying' || 'in progress' => SubjectStatus.studying,
      'not started' || 'notstarted' => SubjectStatus.notStarted,
      _ => SubjectStatus.unknown,
    };
  }

  String? _studentCodeFromFileName(String? fileName) {
    if (fileName == null || fileName.isEmpty) return null;
    final match = _studentCodePattern.firstMatch(fileName);
    return match?.group(1)?.toUpperCase();
  }
}

/// Chỉ số cột đọc được từ `<thead>`. Bảng phụ (môn tiếng Anh dự bị) thiếu
/// `Term`, `prerequisite`, `Replaced Subject` và cột cờ, nên các trường đó để
/// null là chuyện bình thường.
class _ColumnMap {
  int? term;
  int? semester;
  int? code;
  int? prerequisite;
  int? replaced;
  int? name;
  int? credits;
  int? grade;
  int? status;
  int? graduationFlag;
}

/// Kết quả bóc tách một nhãn kỳ.
class ParsedSemester {
  final int year;
  final Season season;

  /// `year * 10 + season.rank`, xem [TranscriptEntry.semesterOrder].
  final int order;

  const ParsedSemester({
    required this.year,
    required this.season,
    required this.order,
  });

  @override
  String toString() => '${season.label}$year (order $order)';
}

/// Kết quả một lần bóc tách transcript.
class TranscriptParseResult {
  final List<TranscriptEntry> entries;

  /// Mỗi dòng bị bỏ qua kèm lý do. Hiện thẳng lên màn hình xem trước — người
  /// dùng cần biết mình mất dòng nào chứ không chỉ thấy một con số tổng.
  final List<String> warnings;

  /// Mã sinh viên bóc từ tên file, nếu có.
  final String? studentCode;

  const TranscriptParseResult({
    required this.entries,
    this.warnings = const [],
    this.studentCode,
  });

  bool get isEmpty => entries.isEmpty;

  int countByStatus(SubjectStatus status) =>
      entries.where((e) => e.status == status).length;

  @override
  String toString() =>
      'TranscriptParseResult(${entries.length} dòng, '
      '${warnings.length} cảnh báo)';
}
