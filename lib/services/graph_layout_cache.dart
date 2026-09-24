import 'dart:ui' show Offset;

/// Nhớ vị trí node của từng khung chương trình, **chỉ trong bộ nhớ**.
///
/// Graph view lớn và ô đồ thị thu nhỏ chạy hai bộ mô phỏng lực riêng. Không có
/// chỗ dùng chung này thì ô thu nhỏ luôn bắt đầu từ một vòng tròn ngẫu nhiên,
/// nên cùng một khung lại ra hai hình khác hẳn nhau — kéo tab Graph view vào
/// thanh bên giống như thu nhỏ một cửa sổ mà nội dung bên trong đổi chỗ hết.
///
/// Cố ý **không** ghi xuống đĩa: đây là bố cục tạm của một phiên làm việc, và
/// lưu lại thì mỗi lần thêm/xoá môn hình cũ sẽ lệch với đồ thị mới.
///
/// Cũng cố ý **không** phải `ChangeNotifier`: mô phỏng lực gọi [save] mỗi lần
/// cân bằng, báo thay đổi ở đó sẽ dựng lại toàn bộ cây widget liên tục.
class GraphLayoutCache {
  GraphLayoutCache._();
  static final GraphLayoutCache instance = GraphLayoutCache._();

  /// Khoá là mã khung; ô "toàn bộ môn" dùng [_allKey].
  final Map<String, Map<int, Offset>> _positions = {};

  static const String _allKey = '__ALL__';

  String _keyOf(String? curriculumCode) =>
      (curriculumCode == null || curriculumCode.isEmpty)
      ? _allKey
      : curriculumCode;

  /// Ghi đè bố cục của một khung. Bản đồ rỗng thì bỏ qua để một lần đồng bộ
  /// hụt không xoá mất hình đang có.
  void save(String? curriculumCode, Map<int, Offset> positions) {
    if (positions.isEmpty) return;
    _positions[_keyOf(curriculumCode)] = Map.of(positions);
  }

  /// Bố cục đã lưu của một khung, `null` khi chưa có.
  Map<int, Offset>? read(String? curriculumCode) {
    final saved = _positions[_keyOf(curriculumCode)];
    return saved == null ? null : Map.unmodifiable(saved);
  }

  bool has(String? curriculumCode) =>
      _positions.containsKey(_keyOf(curriculumCode));

  void remove(String? curriculumCode) =>
      _positions.remove(_keyOf(curriculumCode));

  void clear() => _positions.clear();

  /// Co bố cục đã lưu về một khung vẽ khác, giữ nguyên tỉ lệ.
  ///
  /// Hai bộ mô phỏng dùng hai hệ toạ độ khác nhau (canvas lớn 2000px, ô thu
  /// nhỏ 1200px) nên không thể chép thẳng số. Giữ đúng tỉ lệ khung hình thay
  /// vì kéo dãn theo từng trục, nếu không đồ thị sẽ bị bóp méo.
  ///
  /// Trả về `null` khi dữ liệu không đủ để dựng lại hình: thiếu quá nhiều môn
  /// thì phần còn lại chụm vào một góc, lúc đó bắt đầu từ vòng tròn còn đẹp
  /// hơn. [minCoverage] là tỉ lệ môn tối thiểu phải có trong bộ nhớ.
  static Map<int, Offset>? fit({
    required Map<int, Offset>? saved,
    required List<int> subjectIds,
    required Offset center,
    required double radius,
    double minCoverage = 0.6,
  }) {
    if (saved == null || saved.isEmpty || subjectIds.isEmpty) return null;

    final hits = <int, Offset>{
      for (final id in subjectIds)
        if (saved[id] != null) id: saved[id]!,
    };
    if (hits.length < subjectIds.length * minCoverage) return null;

    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in hits.values) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    final width = maxX - minX;
    final height = maxY - minY;
    final span = width > height ? width : height;

    // Mọi node chồng lên nhau một điểm: không có hình để co, trả null cho
    // phía gọi bung ra vòng tròn.
    if (span < 1.0) return null;

    final scale = (radius * 2) / span;
    final srcCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);

    return {
      for (final entry in hits.entries)
        entry.key: Offset(
          center.dx + (entry.value.dx - srcCenter.dx) * scale,
          center.dy + (entry.value.dy - srcCenter.dy) * scale,
        ),
    };
  }
}
