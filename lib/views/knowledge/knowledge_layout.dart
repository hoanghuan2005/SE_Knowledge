import 'dart:math' as math;
import 'dart:ui';

/// Một nút trên mạng tri thức: môn học hoặc khái niệm.
class KnowledgeNode {
  final String id;
  final bool isSubject;
  final double width;
  final double height;

  /// Học kỳ của môn — dùng để xếp vị trí ban đầu theo trình tự học.
  final int semester;

  const KnowledgeNode({
    required this.id,
    required this.isSubject,
    required this.width,
    required this.height,
    this.semester = 0,
  });
}

class KnowledgeEdge {
  final String a;
  final String b;
  final double weight;

  const KnowledgeEdge(this.a, this.b, this.weight);
}

/// Bố cục lực đẩy (Fruchterman–Reingold) tính **một lần** rồi vẽ tĩnh.
///
/// Khác sơ đồ môn học (mô phỏng từng khung hình để kéo thả được): mạng tri
/// thức có gấp ba số nút, chạy vật lý liên tục thì tốn CPU mà không được gì
/// thêm. Tính sẵn vài trăm vòng lặp trong vài chục mili giây, kết quả xác
/// định (cùng dữ liệu cho cùng hình), nên mở lại màn hình không bị nhảy lung
/// tung.
class KnowledgeLayout {
  final Map<String, Offset> positions;
  final Size size;

  const KnowledgeLayout(this.positions, this.size);

  static KnowledgeLayout compute(
    List<KnowledgeNode> nodes,
    List<KnowledgeEdge> edges, {
    int iterations = 320,
  }) {
    final n = nodes.length;
    if (n == 0) return const KnowledgeLayout({}, Size(800, 600));

    // Khung vẽ vừa đủ chặt: rộng quá thì lúc thu vừa khung nhìn chữ nhỏ tới
    // mức không đọc được.
    final width = math.max(1000.0, math.sqrt(n) * 150);
    final height = width * 0.66;
    final center = Offset(width / 2, height / 2);
    final k = math.sqrt(width * height / n) * 0.7;

    final index = {for (var i = 0; i < n; i++) nodes[i].id: i};
    final px = List<double>.filled(n, 0);
    final py = List<double>.filled(n, 0);

    // Vị trí ban đầu: môn xếp trên một elip theo học kỳ, khái niệm đặt ở
    // trọng tâm các môn dạy nó. Khởi đầu có trật tự thì kết quả gọn hơn
    // hẳn so với rải ngẫu nhiên.
    final subjects =
        [
          for (var i = 0; i < n; i++)
            if (nodes[i].isSubject) i,
        ]..sort((a, b) {
          final bySem = nodes[a].semester.compareTo(nodes[b].semester);
          return bySem != 0 ? bySem : nodes[a].id.compareTo(nodes[b].id);
        });
    for (var j = 0; j < subjects.length; j++) {
      final angle =
          -math.pi / 2 + 2 * math.pi * j / math.max(1, subjects.length);
      px[subjects[j]] = center.dx + width * 0.36 * math.cos(angle);
      py[subjects[j]] = center.dy + height * 0.36 * math.sin(angle);
    }
    final neighbors = List.generate(n, (_) => <int>[]);
    for (final e in edges) {
      final a = index[e.a];
      final b = index[e.b];
      if (a == null || b == null) continue;
      neighbors[a].add(b);
      neighbors[b].add(a);
    }
    for (var i = 0; i < n; i++) {
      if (nodes[i].isSubject) continue;
      final ns = neighbors[i].where((j) => nodes[j].isSubject).toList();
      final jitter = _hash(nodes[i].id);
      if (ns.isEmpty) {
        px[i] = center.dx + (jitter.dx - 0.5) * width * 0.5;
        py[i] = center.dy + (jitter.dy - 0.5) * height * 0.5;
        continue;
      }
      var sx = 0.0, sy = 0.0;
      for (final j in ns) {
        sx += px[j];
        sy += py[j];
      }
      px[i] = sx / ns.length + (jitter.dx - 0.5) * 60;
      py[i] = sy / ns.length + (jitter.dy - 0.5) * 60;
    }

    final edgeA = <int>[];
    final edgeB = <int>[];
    final edgeW = <double>[];
    for (final e in edges) {
      final a = index[e.a];
      final b = index[e.b];
      if (a == null || b == null) continue;
      edgeA.add(a);
      edgeB.add(b);
      edgeW.add(e.weight.clamp(0.3, 1.6));
    }

    final dx = List<double>.filled(n, 0);
    final dy = List<double>.filled(n, 0);
    var temperature = width / 9;

    for (var iter = 0; iter < iterations; iter++) {
      for (var i = 0; i < n; i++) {
        dx[i] = 0;
        dy[i] = 0;
      }
      // Lực đẩy giữa mọi cặp nút, tính cả kích thước nút để chữ đỡ đè nhau.
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          var ddx = px[i] - px[j];
          var ddy = py[i] - py[j];
          var dist = math.sqrt(ddx * ddx + ddy * ddy);
          if (dist < 0.01) {
            ddx = 0.01 * (i - j);
            ddy = 0.01;
            dist = 0.02;
          }
          final pad = (nodes[i].width + nodes[j].width) * 0.28;
          final force = (k * k) / math.max(1, dist - pad * 0.5);
          final fx = ddx / dist * force;
          final fy = ddy / dist * force;
          dx[i] += fx;
          dy[i] += fy;
          dx[j] -= fx;
          dy[j] -= fy;
        }
      }
      // Lực hút dọc theo cạnh môn — khái niệm.
      for (var e = 0; e < edgeA.length; e++) {
        final a = edgeA[e];
        final b = edgeB[e];
        final ddx = px[a] - px[b];
        final ddy = py[a] - py[b];
        final dist = math.max(0.01, math.sqrt(ddx * ddx + ddy * ddy));
        final force = dist * dist / k * edgeW[e];
        final fx = ddx / dist * force;
        final fy = ddy / dist * force;
        dx[a] -= fx;
        dy[a] -= fy;
        dx[b] += fx;
        dy[b] += fy;
      }
      // Trọng lực nhẹ về tâm để các cụm rời không trôi ra mép.
      for (var i = 0; i < n; i++) {
        dx[i] -= (px[i] - center.dx) * 0.9;
        dy[i] -= (py[i] - center.dy) * 0.9;
        final len = math.sqrt(dx[i] * dx[i] + dy[i] * dy[i]);
        if (len < 0.001) continue;
        final step = math.min(len, temperature);
        px[i] += dx[i] / len * step;
        py[i] += dy[i] / len * step;
        final hw = nodes[i].width / 2 + 12;
        final hh = nodes[i].height / 2 + 12;
        px[i] = px[i].clamp(hw, width - hw);
        py[i] = py[i].clamp(hh, height - hh);
      }
      temperature = math.max(1.2, temperature * 0.985);
    }

    _removeOverlaps(nodes, px, py, width, height);

    return KnowledgeLayout({
      for (var i = 0; i < n; i++) nodes[i].id: Offset(px[i], py[i]),
    }, Size(width, height));
  }

  /// Lực đẩy coi nút như một điểm nên nhãn dài vẫn có thể đè lên nhau. Vài
  /// lượt tách hình chữ nhật chồng nhau theo trục chồng ít hơn, mỗi bên lùi
  /// một nửa, là đủ để chữ không còn dính vào nhau.
  static void _removeOverlaps(
    List<KnowledgeNode> nodes,
    List<double> px,
    List<double> py,
    double width,
    double height,
  ) {
    const gap = 6.0;
    final n = nodes.length;
    for (var pass = 0; pass < 80; pass++) {
      var moved = false;
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          final ox =
              (nodes[i].width + nodes[j].width) / 2 +
              gap -
              (px[i] - px[j]).abs();
          final oy =
              (nodes[i].height + nodes[j].height) / 2 +
              gap -
              (py[i] - py[j]).abs();
          if (ox <= 0 || oy <= 0) continue;
          moved = true;
          if (ox < oy) {
            final shift = ox / 2 * (px[i] >= px[j] ? 1 : -1);
            px[i] += shift;
            px[j] -= shift;
          } else {
            final shift = oy / 2 * (py[i] >= py[j] ? 1 : -1);
            py[i] += shift;
            py[j] -= shift;
          }
        }
      }
      for (var i = 0; i < n; i++) {
        final hw = nodes[i].width / 2 + 8;
        final hh = nodes[i].height / 2 + 8;
        px[i] = px[i].clamp(hw, width - hw);
        py[i] = py[i].clamp(hh, height - hh);
      }
      if (!moved) break;
    }
  }

  /// Hai số giả ngẫu nhiên 0..1 cố định theo chuỗi, thay cho `Random` để
  /// bố cục lặp lại y hệt giữa các lần mở.
  static Offset _hash(String s) {
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    for (final c in s.codeUnits) {
      h1 = (h1 ^ c) * 16777619 & 0xffffffff;
      h2 = (h2 * 31 + c) & 0xffffffff;
    }
    return Offset((h1 % 1000) / 1000, (h2 % 1000) / 1000);
  }
}
