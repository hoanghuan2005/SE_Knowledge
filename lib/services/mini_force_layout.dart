import 'dart:math' as math;

/// Mô phỏng lực cho ô đồ thị thu nhỏ trên thanh bên.
///
/// Dart thuần, không `dart:io`, không `sqflite`, không `package:flutter` — tách
/// khỏi widget để kiểm thử được từng bước một. Đây không phải chuyện thừa: lỗi
/// nặng nhất của ô thu nhỏ là một dấu cộng lẽ ra phải là dấu trừ trong bước lực
/// lò xo, thứ mà nhìn mắt thường không ra nhưng chạy vài trăm bước là lộ.
///
/// Graph view lớn giữ bản mô phỏng riêng của nó (có thêm liên kết khái niệm và
/// các tham số chỉnh được trong cài đặt); ở đây cố ý không gộp hai bên làm một.
class ForceNode {
  double x;
  double y;
  double vx = 0;
  double vy = 0;

  /// Node đang bị người dùng giữ chuột: mọi lực đều bỏ qua nó.
  bool isDragging = false;

  ForceNode({required this.x, required this.y});
}

/// Một cạnh trong mô phỏng. Widget tự cài lên lớp cạnh sẵn có của mình để khỏi
/// dựng lại danh sách cạnh ở mỗi khung hình.
abstract class ForceLink {
  ForceNode get source;
  ForceNode get target;
}

class MiniForceLayout {
  const MiniForceLayout._();

  /// Độ mạnh lực đẩy giữa hai node bất kỳ (giảm theo bình phương khoảng cách).
  static const double repulsion = 1200.0;

  /// Xa hơn mức này thì thôi không đẩy nữa — vừa đỡ tốn, vừa để các cụm rời
  /// nhau không bị thổi ra mép.
  static const double repulsionRange = 180.0;

  static const double springK = 0.035;
  static const double desiredDistance = 55.0;
  static const double centerPull = 0.003;
  static const double damping = 0.88;

  /// Dưới ngưỡng này coi như đồ thị đã cân bằng, dừng ticker cho đỡ tốn CPU.
  static const double sleepVelocity = 0.05;

  /// Chạy đúng một bước, cập nhật thẳng vào [nodes]. Trả về vận tốc lớn nhất
  /// còn lại để bên gọi biết khi nào nên ngủ.
  static double step(
    List<ForceNode> nodes,
    List<ForceLink> links, {
    required double centerX,
    required double centerY,
  }) {
    // 1. Lực đẩy giữa các node.
    for (int i = 0; i < nodes.length; i++) {
      final a = nodes[i];
      for (int j = i + 1; j < nodes.length; j++) {
        final b = nodes[j];
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        double dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 1.0) dist = 1.0;
        if (dist >= repulsionRange) continue;

        final force = repulsion / (dist * dist);
        final fx = (dx / dist) * force;
        final fy = (dy / dist) * force;
        if (!a.isDragging) {
          a.vx -= fx;
          a.vy -= fy;
        }
        if (!b.isDragging) {
          b.vx += fx;
          b.vy += fy;
        }
      }
    }

    // 2. Lực lò xo dọc theo cạnh.
    //
    // Hai đầu phải nhận lực **ngược chiều** nhau. Cùng dấu thì khoảng cách giữa
    // chúng không đổi (lực triệt tiêu trong chuyển động tương đối) mà cả cặp
    // cùng trôi về một phía, mỗi khung hình một ít: một chuỗi vài môn nối nhau
    // sẽ tự bơm vận tốc cho nhau tới vô cực và bay khỏi ô.
    for (final link in links) {
      final a = link.source;
      final b = link.target;
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      double dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 1.0) dist = 1.0;

      final force = (dist - desiredDistance) * springK;
      final fx = (dx / dist) * force;
      final fy = (dy / dist) * force;
      if (!a.isDragging) {
        a.vx += fx;
        a.vy += fy;
      }
      if (!b.isDragging) {
        b.vx -= fx;
        b.vy -= fy;
      }
    }

    // 3. Kéo về tâm, giảm chấn, rồi mới dời toạ độ.
    double maxVelocity = 0.0;
    for (final n in nodes) {
      if (n.isDragging) continue;

      n.vx += (centerX - n.x) * centerPull;
      n.vy += (centerY - n.y) * centerPull;

      n.vx *= damping;
      n.vy *= damping;

      n.x += n.vx;
      n.y += n.vy;

      final v = math.sqrt(n.vx * n.vx + n.vy * n.vy);
      if (v > maxVelocity) maxVelocity = v;
    }
    return maxVelocity;
  }
}
