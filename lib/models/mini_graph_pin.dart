/// Các trang của cửa sổ đồ thị thu nhỏ trên thanh bên.
///
/// Thanh bên chỉ có **một** cửa sổ đồ thị thu nhỏ; mỗi khung đã ghim là một
/// trang trong cửa sổ đó, người dùng lật qua lại như các tab. Kiểu này giữ cả
/// danh sách trang lẫn trang đang xem ([activeIndex]).
///
/// Tách thành một kiểu giá trị bất biến, thuần Dart, thay vì để [AppState] tự
/// thao tác trên `List` — nhờ vậy các phép ghim, gỡ, đổi thứ tự, dọn khung đã
/// xoá, lật trang kiểm thử được mà không cần mở CSDL, đúng cách
/// `SubjectDeleteGuard.analyzeGraph()` đang làm.
library;

class MiniGraphPins {
  /// Mã khung chương trình của từng trang, theo thứ tự hiển thị.
  /// `null` nghĩa là trang "toàn bộ môn" (không lọc theo khung nào).
  final List<String?> codes;

  /// Trang đang xem. Luôn nằm trong `0..length-1`; danh sách rỗng thì bằng 0.
  final int activeIndex;

  /// Số trang tối đa. Mỗi trang lúc mở lại phải dựng lại mô phỏng lực, và dải
  /// chấm trang dài quá thì không còn bấm trúng được trên thanh bên hẹp.
  static const int maxPages = 8;

  const MiniGraphPins._(this.codes, this.activeIndex);

  /// Kẹp [activeIndex] vào khoảng hợp lệ ngay lúc dựng, để không phép nào
  /// (kể cả dữ liệu hỏng đọc từ đĩa) sinh ra được một chỉ số trỏ ra ngoài.
  factory MiniGraphPins(List<String?> codes, [int activeIndex = 0]) {
    final list = List<String?>.unmodifiable(codes);
    final idx = list.isEmpty ? 0 : activeIndex.clamp(0, list.length - 1);
    return MiniGraphPins._(list, idx);
  }

  static const MiniGraphPins empty = MiniGraphPins._([], 0);

  /// Giá trị thay cho `null` khi ghi xuống SharedPreferences.
  ///
  /// `setStringList` không nhận phần tử null, mà trang "toàn bộ môn" lại là
  /// một lựa chọn hợp lệ, nên phải có một mã quy ước. Dùng ký tự `__` hai đầu
  /// để không đụng mã khung thật (FAP chỉ sinh mã kiểu `BIT_SE_K20B`).
  static const String allSentinel = '__ALL__';

  bool get isEmpty => codes.isEmpty;
  bool get isNotEmpty => codes.isNotEmpty;
  int get length => codes.length;
  bool get isFull => codes.length >= maxPages;

  bool contains(String? code) => codes.contains(code);

  /// Mã khung của trang đang xem. `null` khi chưa ghim trang nào — lúc đó
  /// `null` cũng là mã của trang "toàn bộ môn", nên nơi gọi phải xét
  /// [isEmpty] trước nếu cần phân biệt hai ca.
  String? get activeCode => codes.isEmpty ? null : codes[activeIndex];

  /// Trả về chính nó khi không có gì đổi, để nơi gọi so bằng `identical` mà
  /// bỏ qua lượt ghi đĩa thừa.
  MiniGraphPins _withIndex(int index) {
    if (codes.isEmpty) return this;
    final idx = index.clamp(0, codes.length - 1);
    return idx == activeIndex ? this : MiniGraphPins._(codes, idx);
  }

  MiniGraphPins select(int index) => _withIndex(index);

  /// Trang kế tiếp; trang cuối thì vòng về trang đầu.
  MiniGraphPins next() =>
      codes.length < 2 ? this : _withIndex((activeIndex + 1) % codes.length);

  /// Trang trước; trang đầu thì vòng về trang cuối.
  MiniGraphPins previous() => codes.length < 2
      ? this
      : _withIndex((activeIndex - 1 + codes.length) % codes.length);

  /// Chuyển tới trang của [code]. Khung chưa ghim thì giữ nguyên.
  MiniGraphPins selectCode(String? code) {
    final idx = codes.indexOf(code);
    return idx == -1 ? this : _withIndex(idx);
  }

  /// Ghim một khung. Đã có rồi thì chỉ chuyển sang trang đó — ghim trùng chỉ
  /// tạo hai trang vẽ cùng một thứ. Chưa có thì thêm vào cuối và chuyển tới.
  ///
  /// Đã đủ [maxPages] mà khung còn mới thì trả về chính nó; nơi gọi xét
  /// [isFull] để báo cho người dùng.
  MiniGraphPins pin(String? code) {
    if (contains(code)) return selectCode(code);
    if (isFull) return this;
    return MiniGraphPins._(
      List.unmodifiable([...codes, code]),
      codes.length,
    );
  }

  /// Gỡ một trang. Gỡ đúng trang đang xem thì chuyển sang trang liền kề, ưu
  /// tiên bên trái (trang vừa xem trước đó theo chiều đọc). Gỡ trang khác thì
  /// vẫn xem đúng khung cũ, dù chỉ số của nó có lùi đi một bậc.
  MiniGraphPins unpin(String? code) {
    final removed = codes.indexOf(code);
    if (removed == -1) return this;
    final next = [...codes]..removeAt(removed);
    if (next.isEmpty) return empty;

    final int idx;
    if (removed == activeIndex) {
      idx = removed > 0 ? removed - 1 : 0;
    } else if (removed < activeIndex) {
      idx = activeIndex - 1;
    } else {
      idx = activeIndex;
    }
    return MiniGraphPins(next, idx);
  }

  /// Đổi thứ tự hai trang. Chỉ số ngoài khoảng thì bỏ qua thay vì ném lỗi:
  /// nguồn gọi là thao tác kéo thả trên giao diện, không đáng để làm sập cả
  /// trang.
  ///
  /// Trang đang xem đi theo **mã khung** chứ không theo chỉ số: kéo trang
  /// khác chen lên trước thì người dùng vẫn phải thấy đúng đồ thị cũ.
  MiniGraphPins reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= codes.length) return this;
    if (newIndex < 0 || newIndex > codes.length) return this;

    final active = activeCode;
    final next = [...codes];
    final moved = next.removeAt(oldIndex);
    // ReorderableListView báo `newIndex` tính trên danh sách CHƯA gỡ phần tử,
    // nên kéo xuống phải lùi một bậc.
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    next.insert(target.clamp(0, next.length), moved);
    return MiniGraphPins(next, next.indexOf(active));
  }

  /// Bỏ những trang trỏ tới khung không còn tồn tại (vừa bị xoá hoặc đổi mã).
  /// Trang "toàn bộ môn" (`null`) luôn được giữ vì nó không phụ thuộc khung
  /// nào. Trang đang xem còn sống thì vẫn xem nó; bị dọn thì lùi về trang
  /// liền kề như khi gỡ tay.
  MiniGraphPins pruneTo(Set<String> availableCodes) {
    bool keep(String? c) => c == null || availableCodes.contains(c);
    if (codes.every(keep)) return this;

    var result = this;
    for (final c in codes) {
      if (!keep(c)) result = result.unpin(c);
    }
    return result;
  }

  List<String> encode() => [for (final c in codes) c ?? allSentinel];

  /// [activeIndex] nằm ở khoá riêng trong SharedPreferences; dữ liệu của bản
  /// cũ chưa có khoá đó thì mở trang đầu.
  factory MiniGraphPins.decode(List<String>? raw, [int? activeIndex]) {
    if (raw == null || raw.isEmpty) return empty;
    return MiniGraphPins(
      [for (final c in raw) c == allSentinel ? null : c],
      activeIndex ?? 0,
    );
  }

  @override
  String toString() =>
      'MiniGraphPins(${encode().join(", ")} @ $activeIndex)';
}

/// Kết quả của một lần ghim, để giao diện báo đúng điều vừa xảy ra.
enum MiniGraphPinResult {
  /// Thêm trang mới và đã chuyển tới trang đó.
  added,

  /// Khung đã ghim từ trước — chỉ chuyển sang trang của nó.
  switched,

  /// Đã đủ [MiniGraphPins.maxPages] trang, không thêm được.
  full,
}

/// Gói dữ liệu đi kèm thao tác kéo tab "Graph view" thả vào thanh bên.
///
/// Chỉ mang mã khung đang xem; cửa sổ thu nhỏ tự dựng lại đồ thị từ mã đó qua
/// `AppState.graphFor`, nên payload không cần ôm theo cả danh sách môn.
class MiniGraphDragData {
  final String? curriculumCode;

  /// Nhãn hiển thị trên thẻ bay theo con trỏ lúc kéo.
  final String label;

  const MiniGraphDragData({required this.curriculumCode, required this.label});

  @override
  String toString() => 'MiniGraphDragData(${curriculumCode ?? "toàn bộ môn"})';
}
