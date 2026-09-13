import 'dart:convert';
import 'subject.dart';

/// Đại diện cho 1 môn học trong khung chương trình
class Course {
  final String code;
  final String name;
  final int credits;
  final List<String> prerequisites;
  final int term;

  const Course({
    required this.code,
    required this.name,
    required this.credits,
    required this.prerequisites,
    required this.term,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'credits': credits,
        'prerequisites': prerequisites,
        'term': term,
      };

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        code: (json['code'] as String?)?.trim() ?? '',
        name: (json['name'] as String?)?.trim() ?? '',
        credits: json['credits'] is int
            ? json['credits'] as int
            : int.tryParse(json['credits']?.toString() ?? '0') ?? 0,
        prerequisites: (json['prerequisites'] as List<dynamic>?)
                ?.map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList() ??
            const [],
        term: json['term'] is int
            ? json['term'] as int
            : int.tryParse(json['term']?.toString() ?? '1') ?? 1,
      );

  @override
  String toString() =>
      'Course($code - $name, $credits cr, Term: $term, Prereqs: $prerequisites)';
}

/// Đại diện cho 1 học kỳ
class Semester {
  final int termNumber;
  final List<Course> courses;

  const Semester({
    required this.termNumber,
    required this.courses,
  });

  Map<String, dynamic> toJson() => {
        'termNumber': termNumber,
        'courses': courses.map((c) => c.toJson()).toList(),
      };

  factory Semester.fromJson(Map<String, dynamic> json) => Semester(
        termNumber: json['termNumber'] is int
            ? json['termNumber'] as int
            : int.tryParse(json['termNumber']?.toString() ?? '1') ?? 1,
        courses: (json['courses'] as List<dynamic>?)
                ?.map((c) => Course.fromJson(c as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  int get totalCredits => courses.fold(0, (sum, c) => sum + c.credits);
}

/// Khung chương trình đào tạo của một chuyên ngành
class Curriculum {
  final String code;
  final String name;
  final String major;
  final int totalCredits;
  final String decisionNo;
  final String description;
  final List<Semester> semesters;

  const Curriculum({
    this.code = 'SE',
    this.name = '',
    required this.major,
    this.totalCredits = 0,
    this.decisionNo = '',
    this.description = '',
    required this.semesters,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name.isEmpty ? major : name,
        'major': major,
        'totalCredits': totalCredits > 0 ? totalCredits : calculatedTotalCredits,
        'decisionNo': decisionNo,
        'description': description,
        'semesters': semesters.map((s) => s.toJson()).toList(),
      };

  factory Curriculum.fromJson(Map<String, dynamic> json) => Curriculum(
        code: (json['code'] as String?)?.trim().isNotEmpty == true
            ? (json['code'] as String).trim()
            : 'SE',
        name: (json['name'] as String?)?.trim() ?? '',
        major: (json['major'] as String?) ?? 'Software Engineering',
        totalCredits: json['totalCredits'] is int
            ? json['totalCredits'] as int
            : int.tryParse(json['totalCredits']?.toString() ?? '0') ?? 0,
        decisionNo: (json['decisionNo'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        semesters: (json['semesters'] as List<dynamic>?)
                ?.map((s) => Semester.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  String toJsonString() => jsonEncode(toJson());

  factory Curriculum.fromJsonString(String source) =>
      Curriculum.fromJson(jsonDecode(source) as Map<String, dynamic>);

  int get calculatedTotalCredits =>
      semesters.fold(0, (sum, s) => sum + s.totalCredits);

  int get totalCourses =>
      semesters.fold(0, (sum, s) => sum + s.courses.length);
}

/// Nhóm phân cấp Khung chương trình đào tạo dùng cho Cây thư mục (Sidebar Tree View)
class CurriculumGroup {
  final int? curriculumId; // null = Môn học ngoài khung / Chưa phân loại
  final String code;
  final String name;
  final String major;
  final int totalCredits;
  final Map<int, List<Subject>> semesters; // termNumber -> List<Subject>
  final int totalSubjects;

  const CurriculumGroup({
    this.curriculumId,
    required this.code,
    required this.name,
    required this.major,
    this.totalCredits = 0,
    required this.semesters,
    required this.totalSubjects,
  });

  bool get isUnassigned => curriculumId == null;

  Curriculum toCurriculum() => Curriculum(
        code: code,
        name: name,
        major: major,
        totalCredits: totalCredits,
        semesters: const [],
      );
}

