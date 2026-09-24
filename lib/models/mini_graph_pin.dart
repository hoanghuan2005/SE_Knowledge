/// Danh sách các ô đồ thị thu nhỏ đang được ghim trên thanh bên.
///
/// Tách thành một kiểu giá trị bất biến, thuần Dart, thay vì để [AppState] tự
/// thao tác trên `List` — nhờ vậy bốn phép cơ bản (ghim, gỡ, đổi thứ tự, dọn
/// khung đã xoá) kiểm thử được mà không cần mở CSDL, đúng cách
/// `SubjectDeleteGuard.analyzeGraph()` đang làm.
library;

class MiniGraphPins {
  /// Mã khung chương trình của từng ô, theo thứ tự hiển thị.
  /// `null` nghĩa là ô "toàn bộ môn" (không lọc theo khung nào).
  final List<String?> codes;

  const MiniGraphPins(this.codes);

  static const MiniGraphPins empty = MiniGraphPins([]);

  /// Giá trị thay cho `null` khi ghi xuống SharedPreferences.
  ///
  /// `setStringList` không nhận phần tử null, mà ô "toàn bộ môn" lại là một
  /// lựa chọn hợp lệ, nên phải có một mã quy ước. Dùng ký tự `__` hai đầu để
  /// không đụng mã khung thật (FAP chỉ sinh mã kiểu `BIT_SE_K20B`).
  static const String allSentinel = '__ALL__';

  bool get isEmpty => codes.isEmpty;
  bool get isNotEmpty => codes.isNotEmpty;
  int get length => codes.length;

  bool contains(String? code) => codes.contains(code);

  /// Ghim thêm một ô. Đã có rồi thì trả về chính nó — ghim trùng chỉ tạo hai
  /// ô vẽ cùng một thứ và tốn gấp đôi CPU cho mô phỏng lực.
  MiniGraphPins pin(String? code) {
    if (contains(code)) return this;
    return MiniGraphPins([...codes, code]);
  }

  MiniGraphPins unpin(String? code) {
    if (!contains(code)) return this;
    return MiniGraphPins([
      for (final c in codes)
        if (c != code) c,
    ]);
  }

  /// Đổi thứ tự hai ô. Chỉ số ngoài khoảng thì bỏ qua thay vì ném lỗi: nguồn
  /// gọi là thao tác kéo thả trên giao diện, không đáng để làm sập cả trang.
  MiniGraphPins reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= codes.length) return this;
    if (newIndex < 0 || newIndex > codes.length) return this;

    final next = [...codes];
    final moved = next.removeAt(oldIndex);
    // ReorderableListView báo `newIndex` tính trên danh sách CHƯA gỡ phần tử,
    // nên kéo xuống phải lùi một bậc.
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    next.insert(target.clamp(0, next.length), moved);
    return MiniGraphPins(next);
  }

  /// Bỏ những ô trỏ tới khung không còn tồn tại (vừa bị xoá hoặc đổi mã).
  /// Ô "toàn bộ môn" (`null`) luôn được giữ vì nó không phụ thuộc khung nào.
  MiniGraphPins pruneTo(Set<String> availableCodes) {
    final next = [
      for (final c in codes)
        if (c == null || availableCodes.contains(c)) c,
    ];
    return next.length == codes.length ? this : MiniGraphPins(next);
  }

  List<String> encode() => [for (final c in codes) c ?? allSentinel];

  factory MiniGraphPins.decode(List<String>? raw) {
    if (raw == null || raw.isEmpty) return empty;
    return MiniGraphPins([for (final c in raw) c == allSentinel ? null : c]);
  }

  @override
  String toString() => 'MiniGraphPins(${encode().join(", ")})';
}

/// Gói dữ liệu đi kèm thao tác kéo tab "Graph view" thả vào thanh bên.
///
/// Chỉ mang mã khung đang xem; ô thu nhỏ tự dựng lại đồ thị từ mã đó qua
/// `AppState.graphFor`, nên payload không cần ôm theo cả danh sách môn.
class MiniGraphDragData {
  final String? curriculumCode;

  /// Nhãn hiển thị trên thẻ bay theo con trỏ lúc kéo.
  final String label;

  const MiniGraphDragData({required this.curriculumCode, required this.label});

  @override
  String toString() => 'MiniGraphDragData(${curriculumCode ?? "toàn bộ môn"})';
}
