import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/curriculum.dart';
import 'curriculum_cache_manager.dart';
import 'curriculum_mock_data.dart';

/// Dịch vụ cào và chuẩn hóa chương trình học FLM
class CurriculumParserService {
  CurriculumParserService._();
  static final CurriculumParserService instance = CurriculumParserService._();

  /// Gửi HTTP request lấy mã nguồn HTML từ FLM nếu có session cookie
  Future<String?> fetchHtmlFromFlm({
    required String url,
    Map<String, String>? headers,
    String? sessionCookie,
  }) async {
    try {
      String? cookieHeader = sessionCookie?.trim();
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        // Nếu người dùng chỉ copy phần Value mà chưa có Name=
        if (!cookieHeader.contains('=')) {
          cookieHeader = '.AspNet.cookies=$cookieHeader';
        }
      }

      final requestHeaders = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Accept-Language': 'vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7',
        if (cookieHeader != null && cookieHeader.isNotEmpty)
          'Cookie': cookieHeader,
        ...?headers,
      };

      final response = await http
          .get(Uri.parse(url), headers: requestHeaders)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return response.body;
      } else {
        dev.log('HTTP fetch failed with code: ${response.statusCode}');
        return null;
      }
    } catch (e, stack) {
      dev.log('Lỗi khi fetch HTML từ FLM: $e', stackTrace: stack);
      return null;
    }
  }

  /// Phương thức Offline-First lấy dữ liệu Curriculum:
  /// 1. Nếu rawHtml có dữ liệu: Parse qua compute(), lưu cache và trả về.
  /// 2. Nếu không có rawHtml hoặc parse lỗi: Nạp từ file cache cục bộ.
  /// 3. Nếu chưa có file cache: Trả về MockData chuẩn cho demo.
  Future<Curriculum> getCurriculum({
    String? rawHtml,
    bool forceRefresh = false,
  }) async {
    // 1. Kiểm tra cache trước nếu không forceRefresh và không truyền rawHtml mới
    if (!forceRefresh && (rawHtml == null || rawHtml.trim().isEmpty)) {
      final cached = await CurriculumCacheManager.readCache();
      if (cached != null && cached.semesters.isNotEmpty) {
        dev.log('Lấy Curriculum từ LOCAL CACHE thành công.');
        return cached;
      }
    }

    // 2. Thử bóc tách từ rawHtml nếu có
    if (rawHtml != null && rawHtml.trim().isNotEmpty) {
      try {
        dev.log('Bắt đầu parse HTML qua Isolate compute()...');
        final parsed = await compute(parseCurriculumWorker, rawHtml);

        if (parsed.semesters.isNotEmpty) {
          // Lưu vào cache để dùng cho các lần sau
          await CurriculumCacheManager.writeCache(parsed);
          dev.log('Parse HTML thành công và đã cập nhật cache!');
          return parsed;
        } else {
          dev.log('HTML không chứa bảng môn học hợp lệ.');
        }
      } catch (e, stack) {
        dev.log('Lỗi trong quá trình parse HTML: $e', stackTrace: stack);
      }
    }

    // 3. Fallback cấp 2: Đọc file cache đã lưu trước đó
    final cached = await CurriculumCacheManager.readCache();
    if (cached != null && cached.semesters.isNotEmpty) {
      dev.log('Fallback: Sử dụng dữ liệu LOCAL CACHE cũ.');
      return cached;
    }

    // 4. Fallback cấp 3: Trả về MockData chuẩn demo để không bị crash/trống giao diện
    dev.log('Fallback: Sử dụng MOCK DATA cho buổi Demo.');
    return CurriculumMockData.defaultCurriculum;
  }
}

// =============================================================================
// ISOLATE WORKER (Top-Level Function để truyền vào compute)
// =============================================================================

/// Hàm thực thi tách biệt trong Isolate để không block UI thread
Curriculum parseCurriculumWorker(String htmlString) {
  final document = html_parser.parse(htmlString);

  // 1. Tìm thông tin Khung chương trình (Major, Code, Decision, Credits)
  String major = 'Kỹ thuật phần mềm (Software Engineering)';
  String curriculumCode = 'SE';
  String decisionNo = '';
  int parsedTotalCredits = 0;
  String description = '';

  final titleElement = document.querySelector(
      '.curriculum-title, h1, h2, #ctl00_mainContent_lblCurriculum');
  if (titleElement != null && titleElement.text.trim().isNotEmpty) {
    final titleText = titleElement.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (titleText.length > 3 &&
        !titleText.toLowerCase().contains('curriculum details') &&
        !titleText.toLowerCase().contains('learning materials')) {
      major = titleText;
    }
  }

  // Quét các hàng Field / Value trong bảng chi tiết của FLM (VD: Name: Bachelor Program...)
  for (final tr in document.querySelectorAll('tr')) {
    final tds = tr.querySelectorAll('td');
    if (tds.length >= 2) {
      final label = cleanCurriculumText(tds[0].text).toLowerCase();
      final val = cleanCurriculumText(tds[1].text);
      if (val.isEmpty) continue;

      if (label == 'name:' ||
          label == 'curriculum name:' ||
          label == 'tên chương trình:' ||
          label == 'chuyên ngành:') {
        major = val;
      } else if (label == 'code:' ||
          label == 'curriculum code:' ||
          label == 'curriculumcode:' ||
          label == 'mã khung:' ||
          label == 'mã chương trình:') {
        curriculumCode = val;
      } else if (label.contains('decision') || label.contains('quyết định')) {
        decisionNo = val;
      } else if (label.contains('total credit') || label.contains('tổng tín chỉ')) {
        parsedTotalCredits = int.tryParse(val) ?? 0;
      } else if (label.contains('description') || label.contains('mô tả')) {
        description = val;
      }
    }
  }

  // Nhận diện mã khung dạng BIT_SE_K20B, BIT_SE_K21C nếu label chưa có
  if (curriculumCode == 'SE') {
    final codeMatch =
        RegExp(r'\b[A-Z]{2,4}_[A-Z]{2,4}_[A-Za-z0-9_]+\b').firstMatch(htmlString);
    if (codeMatch != null) {
      curriculumCode = codeMatch.group(0)!;
    }
  }

  // 2. Tìm bảng danh sách môn học
  final tables = document.querySelectorAll('table');
  if (tables.isEmpty) {
    return Curriculum(
      code: curriculumCode,
      name: major,
      major: major,
      totalCredits: parsedTotalCredits,
      decisionNo: decisionNo,
      description: description,
      semesters: const [],
    );
  }

  final Map<int, List<Course>> semesterMap = {};
  int currentTerm = 1;

  // Regex nhận diện dòng phân tách học kỳ: "Semester 1", "Học kỳ 2", "Term 3", "Kỳ 4"
  final termHeaderRegex = RegExp(
    r'(?:Semester|Học\s*kỳ|Kỳ|Term)\s*([0-9]{1,2})',
    caseSensitive: false,
  );

  for (final table in tables) {
    int headerCodeCol = -1;
    int headerNameCol = -1;
    int headerTermCol = -1;
    int headerCreditCol = -1;
    int headerPrereqCol = -1;

    // 1. Quét tìm header từ <th> nếu có
    final thCells = table.querySelectorAll('th');
    for (int i = 0; i < thCells.length; i++) {
      final hText = cleanCurriculumText(thCells[i].text).toLowerCase();
      if (hText.contains('code') || hText.contains('mã môn')) {
        headerCodeCol = i;
      } else if (hText.contains('name') || hText.contains('tên môn') || hText.contains('subject')) {
        headerNameCol = i;
      } else if (hText.contains('term') || hText.contains('semester') || hText.contains('kỳ') || hText.contains('học kỳ')) {
        headerTermCol = i;
      } else if (hText.contains('credit') || hText.contains('tín chỉ') || hText.contains('tc')) {
        headerCreditCol = i;
      } else if (hText.contains('prereq') || hText.contains('tiên quyết')) {
        headerPrereqCol = i;
      }
    }

    final rows = table.querySelectorAll('tr');

    for (final row in rows) {
      // Bỏ qua hàng header cột (chứa các thẻ <th>)
      if (row.querySelectorAll('th').isNotEmpty &&
          row.querySelectorAll('td').isEmpty) {
        continue;
      }

      final cells = row.querySelectorAll('td');
      if (cells.isEmpty) continue;

      final fullRowText = row.text.trim().replaceAll(RegExp(r'\s+'), ' ');

      // Kiểm tra xem hàng này có phải là hàng tiêu đề phân tách kỳ hay không
      final termMatch = termHeaderRegex.firstMatch(fullRowText);
      if (termMatch != null &&
          (cells.length <= 2 ||
              (row.attributes['class']?.contains('semester') ?? false) ||
              cells.any((c) => c.attributes.containsKey('colspan')))) {
        final parsedTerm = int.tryParse(termMatch.group(1) ?? '');
        if (parsedTerm != null) {
          currentTerm = parsedTerm;
          semesterMap.putIfAbsent(currentTerm, () => []);
          continue;
        }
      }

      // Bỏ qua hàng tiêu đề nếu các ô td chứa các từ khoá tiêu đề
      if (cells.any((c) {
        final txt = cleanCurriculumText(c.text).toLowerCase();
        return txt == 'code' ||
            txt == 'mã môn' ||
            txt == 'subject code' ||
            txt == 'course code';
      })) {
        continue;
      }

      // Xử lý các dòng dữ liệu môn học
      if (cells.length >= 3) {
        int codeIdx = headerCodeCol;
        int nameIdx = headerNameCol;
        int termIdx = headerTermCol;
        int creditIdx = headerCreditCol;
        int prereqIdx = headerPrereqCol;

        // Nếu bảng không có <th>, nhận diện thông minh theo cấu trúc các cột
        if (codeIdx == -1 || creditIdx == -1) {
          final firstColText = cleanCurriculumText(cells[0].text);
          final isFirstColNumber = RegExp(r'^\d+$').hasMatch(firstColText);

          if (cells.length >= 5) {
            if (isFirstColNumber) {
              // Bảng dạng: [STT, Code, Name, Credits, Prereq]
              codeIdx = 1;
              nameIdx = 2;
              creditIdx = 3;
              prereqIdx = 4;
            } else {
              // BẢNG CHUẨN THỰC TẾ FLM:
              // Col 0: Mã môn (EXE201, PRM393, SE_COM*4_ELE, SE_GRA_ELE...)
              // Col 1: Tên môn (Mobile Programming_Lập trình di động...)
              // Col 2: Kỳ học (7, 8, 9...)
              // Col 3: Số tín chỉ (3, 2, 10...)
              // Col 4: Môn tiên quyết (PRO192, SWE201c or SWE202c, MLN111, MLN122...)
              codeIdx = 0;
              nameIdx = 1;
              termIdx = 2;
              creditIdx = 3;
              prereqIdx = 4;
            }
          } else if (cells.length == 4) {
            if (isFirstColNumber) {
              // [STT, Code, Name, Credits]
              codeIdx = 1;
              nameIdx = 2;
              creditIdx = 3;
            } else {
              // [Code, Name, Credits, Prereq]
              codeIdx = 0;
              nameIdx = 1;
              creditIdx = 2;
              prereqIdx = 3;
            }
          } else if (cells.length == 3) {
            codeIdx = 0;
            nameIdx = 1;
            creditIdx = 2;
          }
        }

        if (codeIdx != -1 && codeIdx < cells.length) {
          final code = cleanCurriculumText(cells[codeIdx].text);

          // Bỏ qua nếu là chuỗi rỗng hoặc rác
          if (code.isEmpty ||
              code.toLowerCase() == 'code' ||
              code.toLowerCase() == 'field' ||
              code.toLowerCase().contains('curriculum')) {
            continue;
          }

          final name = (nameIdx != -1 && nameIdx < cells.length)
              ? cleanCurriculumText(cells[nameIdx].text)
              : '';

          // Lấy chính xác số tín chỉ
          final creditStr = (creditIdx != -1 && creditIdx < cells.length)
              ? cleanCurriculumText(cells[creditIdx].text)
              : '0';
          final credits = int.tryParse(creditStr) ?? 0;

          // Lấy chính xác môn tiên quyết
          final prereqStr = (prereqIdx != -1 && prereqIdx < cells.length)
              ? cleanCurriculumText(cells[prereqIdx].text)
              : '';
          final prerequisites = parsePrerequisites(prereqStr);

          // Xác định học kỳ (term):
          // Ưu tiên lấy từ termIdx nếu cột đó chứa số kỳ (1-15)
          int term = currentTerm;
          if (termIdx != -1 && termIdx < cells.length) {
            final parsedTerm =
                int.tryParse(cleanCurriculumText(cells[termIdx].text));
            if (parsedTerm != null && parsedTerm > 0 && parsedTerm <= 15) {
              term = parsedTerm;
            }
          }

          final course = Course(
            code: code,
            name: name,
            credits: credits,
            prerequisites: prerequisites,
            term: term,
          );

          semesterMap.putIfAbsent(term, () => []);
          // Tránh thêm trùng mã môn trong cùng 1 kỳ
          if (!semesterMap[term]!.any((c) => c.code == course.code)) {
            semesterMap[term]!.add(course);
          }
        }
      }
    }
  }

  // Chuyển Map thành List<Semester> sắp xếp theo thứ tự kỳ
  final sortedKeys = semesterMap.keys.toList()..sort();
  final semesters = sortedKeys
      .map((term) => Semester(termNumber: term, courses: semesterMap[term]!))
      .where((s) => s.courses.isNotEmpty)
      .toList();

  return Curriculum(
    code: curriculumCode,
    name: major,
    major: major,
    totalCredits: parsedTotalCredits,
    decisionNo: decisionNo,
    description: description,
    semesters: semesters,
  );
}

/// Làm sạch văn bản: bỏ khoảng trắng thừa, tab, xuống dòng
String cleanCurriculumText(String? raw) {
  if (raw == null) return '';
  return raw
      .replaceAll('\r', '')
      .replaceAll('\n', ' ')
      .replaceAll('\t', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Bóc tách chuỗi môn tiên quyết thành danh sách code chuẩn
List<String> parsePrerequisites(String raw) {
  final clean = cleanCurriculumText(raw);
  if (clean.isEmpty ||
      clean == '-' ||
      clean.toLowerCase() == 'none' ||
      clean.toLowerCase() == 'không' ||
      clean.toLowerCase() == 'không có') {
    return const [];
  }

  final results = <String>[];
  // Tìm tất cả các mẫu mã môn học (VD: PRF192, SWE201c, PRO192, MLN111, MLN122, EXE101)
  final matches =
      RegExp(r'[A-Za-z]{2,4}\s*[0-9]{3}[a-zA-Z]?').allMatches(clean);

  for (final match in matches) {
    final formatted = match.group(0)!.replaceAll(' ', '').toUpperCase();
    if (!results.contains(formatted)) {
      results.add(formatted);
    }
  }

  return results;
}
