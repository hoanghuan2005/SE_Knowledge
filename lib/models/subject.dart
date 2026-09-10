/// Model dai dien cho mot NODE trong do thi tri thuc (bang `subjects`).
class Subject {
  final int? id;
  final String code;
  final String name;
  final int semester;
  final int credits;
  final String description;

  /// Duong dan tuong doi tro toi file .md trong Obsidian Vault (co the null).
  final String? notePath;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Subject({
    this.id,
    required this.code,
    required this.name,
    this.semester = 1,
    this.credits = 3,
    this.description = '',
    this.notePath,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Tao mot mon hoc moi (chua co id, timestamps lay theo gio hien tai).
  factory Subject.create({
    required String code,
    required String name,
    int semester = 1,
    int credits = 3,
    String description = '',
    String? notePath,
  }) {
    final now = DateTime.now();
    return Subject(
      code: code.trim().toUpperCase(),
      name: name.trim(),
      semester: semester,
      credits: credits,
      description: description,
      notePath: notePath,
      createdAt: now,
      updatedAt: now,
    );
  }

  Subject copyWith({
    int? id,
    String? code,
    String? name,
    int? semester,
    int? credits,
    String? description,
    String? notePath,
    DateTime? updatedAt,
  }) {
    return Subject(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      semester: semester ?? this.semester,
      credits: credits ?? this.credits,
      description: description ?? this.description,
      notePath: notePath ?? this.notePath,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'name': name,
      'semester': semester,
      'credits': credits,
      'description': description,
      'note_path': notePath,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Subject.fromMap(Map<String, Object?> map) {
    return Subject(
      id: map['id'] as int?,
      code: (map['code'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      semester: (map['semester'] as int?) ?? 1,
      credits: (map['credits'] as int?) ?? 3,
      description: (map['description'] as String?) ?? '',
      notePath: map['note_path'] as String?,
      createdAt:
          DateTime.tryParse((map['created_at'] as String?) ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((map['updated_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  /// Nhan hien thi tren node do thi.
  String get label => '$code\n$name';

  @override
  String toString() => '$code - $name';
}
