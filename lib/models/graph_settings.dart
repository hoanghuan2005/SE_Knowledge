import 'dart:convert';

/// Cấu hình tùy biến hiển thị và động lực học của Đồ thị tri thức (Graph View).
class GraphSettings {
  /// Tỷ lệ kích thước của thẻ node (0.6x đến 1.8x, mặc định 1.0)
  final double nodeScale;

  /// Khoảng cách lò xo đàn hồi giữa các node có liên kết (60px đến 300px, mặc định 130px)
  final double linkDistance;

  /// Cường độ lực đẩy Coulomb giữa các node (5,000 đến 60,000, mặc định 24,000)
  final double repulsionForce;

  /// Trọng lực kéo các node về tâm canvas (0.001 đến 0.020, mặc định 0.005)
  final double centerGravity;

  /// Độ dày nét vẽ đường liên kết (0.8px đến 3.5px, mặc định 1.5px)
  final double edgeWidth;

  /// Hiển thị nhãn kỳ học (ví dụ: "K1", "K2") trên thẻ node
  final bool showSemesterBadge;

  /// Hiển thị số tín chỉ của môn học (ví dụ: "3TC")
  final bool showCredits;

  /// Hiển thị đầu mũi tên chỉ hướng của liên kết tiên quyết
  final bool showArrows;

  /// Chế độ tô màu node: 'semester' (theo kỳ học), 'degree' (theo mức độ kết
  /// nối) hoặc 'grade' (theo điểm đã học trong bảng điểm cá nhân).
  final String colorMode;

  /// Bật/tắt mô phỏng vật lý tự động cân bằng
  final bool enablePhysics;

  const GraphSettings({
    this.nodeScale = 1.0,
    this.linkDistance = 130.0,
    this.repulsionForce = 24000.0,
    this.centerGravity = 0.005,
    this.edgeWidth = 1.5,
    this.showSemesterBadge = true,
    this.showCredits = false,
    this.showArrows = true,
    this.colorMode = 'semester',
    this.enablePhysics = true,
  });

  static const GraphSettings defaults = GraphSettings();

  GraphSettings copyWith({
    double? nodeScale,
    double? linkDistance,
    double? repulsionForce,
    double? centerGravity,
    double? edgeWidth,
    bool? showSemesterBadge,
    bool? showCredits,
    bool? showArrows,
    String? colorMode,
    bool? enablePhysics,
  }) {
    return GraphSettings(
      nodeScale: nodeScale ?? this.nodeScale,
      linkDistance: linkDistance ?? this.linkDistance,
      repulsionForce: repulsionForce ?? this.repulsionForce,
      centerGravity: centerGravity ?? this.centerGravity,
      edgeWidth: edgeWidth ?? this.edgeWidth,
      showSemesterBadge: showSemesterBadge ?? this.showSemesterBadge,
      showCredits: showCredits ?? this.showCredits,
      showArrows: showArrows ?? this.showArrows,
      colorMode: colorMode ?? this.colorMode,
      enablePhysics: enablePhysics ?? this.enablePhysics,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nodeScale': nodeScale,
      'linkDistance': linkDistance,
      'repulsionForce': repulsionForce,
      'centerGravity': centerGravity,
      'edgeWidth': edgeWidth,
      'showSemesterBadge': showSemesterBadge,
      'showCredits': showCredits,
      'showArrows': showArrows,
      'colorMode': colorMode,
      'enablePhysics': enablePhysics,
    };
  }

  factory GraphSettings.fromMap(Map<String, dynamic> map) {
    return GraphSettings(
      nodeScale: (map['nodeScale'] as num?)?.toDouble() ?? 1.0,
      linkDistance: (map['linkDistance'] as num?)?.toDouble() ?? 130.0,
      repulsionForce: (map['repulsionForce'] as num?)?.toDouble() ?? 24000.0,
      centerGravity: (map['centerGravity'] as num?)?.toDouble() ?? 0.005,
      edgeWidth: (map['edgeWidth'] as num?)?.toDouble() ?? 1.5,
      showSemesterBadge: map['showSemesterBadge'] as bool? ?? true,
      showCredits: map['showCredits'] as bool? ?? false,
      showArrows: map['showArrows'] as bool? ?? true,
      colorMode: map['colorMode'] as String? ?? 'semester',
      enablePhysics: map['enablePhysics'] as bool? ?? true,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory GraphSettings.fromJson(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) {
        return GraphSettings.fromMap(decoded);
      }
    } catch (_) {}
    return defaults;
  }
}
