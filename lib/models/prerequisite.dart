/// Model dai dien cho mot EDGE trong do thi tri thuc (bang `prerequisites`).
///
/// Y nghia: mon [subjectId] yeu cau phai hoc [prerequisiteId] truoc.
/// Tren do thi, mui nhui di tu `prerequisiteId` -> `subjectId`.
class Prerequisite {
  final int? id;
  final int subjectId;
  final int prerequisiteId;

  /// 'PREREQUISITE' (mon tien quyet bat buoc) hoac 'RELATED' (lien quan / tham khao).
  final String relationType;

  const Prerequisite({
    this.id,
    required this.subjectId,
    required this.prerequisiteId,
    this.relationType = kPrerequisite,
  });

  static const String kPrerequisite = 'PREREQUISITE';
  static const String kRelated = 'RELATED';

  bool get isHardPrerequisite => relationType == kPrerequisite;

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'subject_id': subjectId,
      'prerequisite_id': prerequisiteId,
      'relation_type': relationType,
    };
  }

  factory Prerequisite.fromMap(Map<String, Object?> map) {
    return Prerequisite(
      id: map['id'] as int?,
      subjectId: map['subject_id'] as int,
      prerequisiteId: map['prerequisite_id'] as int,
      relationType: (map['relation_type'] as String?) ?? kPrerequisite,
    );
  }

  @override
  String toString() =>
      'Prerequisite($prerequisiteId -> $subjectId, $relationType)';
}
