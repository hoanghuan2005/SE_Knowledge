import 'prerequisite.dart';
import 'subject.dart';

/// Goi du lieu do thi lay ra tu SQLite: danh sach node + danh sach edge.
class GraphData {
  final List<Subject> subjects;
  final List<Prerequisite> edges;

  const GraphData({required this.subjects, required this.edges});

  static const GraphData empty = GraphData(subjects: [], edges: []);

  bool get isEmpty => subjects.isEmpty;

  Map<int, Subject> get byId => {
    for (final s in subjects)
      if (s.id != null) s.id!: s,
  };

  Map<String, Subject> get byCode => {for (final s in subjects) s.code: s};

  /// Dem so mon tien quyet cua mot mon.
  int inDegree(int subjectId) =>
      edges.where((e) => e.subjectId == subjectId).length;

  /// Dem so mon phu thuoc vao mon nay.
  int outDegree(int subjectId) =>
      edges.where((e) => e.prerequisiteId == subjectId).length;
}
