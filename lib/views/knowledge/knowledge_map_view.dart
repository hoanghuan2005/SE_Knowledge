import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/graph_data.dart';
import '../../models/knowledge.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';
import 'knowledge_layout.dart';

/// Góc nhìn thứ ba: **mạng tri thức** — sâu hơn môn học một cấp.
///
/// Nút chữ nhật là môn, nút viên thuốc là khái niệm trích từ syllabus; môn
/// nối với khái niệm nó dạy. Hai môn nằm gần nhau khi chúng dạy chung nhiều
/// khái niệm, nên các cụm hiện ra chính là các mảng tri thức của chương
/// trình, và bảng bên phải chỉ ra cụ thể **tri thức môn này tương quan với
/// tri thức môn kia ở chỗ nào**, kèm câu trích từ CLO/buổi học làm bằng chứng.
///
/// Tô màu theo lối nhấn mạnh: một màu nhấn cho phần đang xem, còn lại xám.
/// Tám nhóm tri thức mà mỗi nhóm một màu thì trên một mạng dày đặc (bất kỳ
/// hai nút nào cũng có thể nằm cạnh nhau) không ai phân biệt nổi — nhóm của
/// khái niệm được ghi bằng chữ ở bảng chi tiết và ở bộ lọc.
class KnowledgeMapView extends StatefulWidget {
  final GraphData data;

  /// Chuyển sang sơ đồ môn học với môn đang xem được chọn sẵn.
  final VoidCallback? onShowSubjectGraph;

  const KnowledgeMapView({
    super.key,
    required this.data,
    this.onShowSubjectGraph,
  });

  @override
  State<KnowledgeMapView> createState() => _KnowledgeMapViewState();
}

/// Đang xem gì trên bảng bên phải.
sealed class _Focus {
  const _Focus();
}

class _NoFocus extends _Focus {
  const _NoFocus();
}

class _ConceptFocus extends _Focus {
  final String id;
  const _ConceptFocus(this.id);
}

class _SubjectFocus extends _Focus {
  final String code;
  const _SubjectFocus(this.code);
}

class _CompareFocus extends _Focus {
  final String a;
  final String b;
  const _CompareFocus(this.a, this.b);
}

class _KnowledgeMapViewState extends State<KnowledgeMapView> {
  final TransformationController _viewer = TransformationController();

  _Focus _focus = const _NoFocus();
  String? _category;
  bool _sharedOnly = true;
  bool _showGeneric = false;

  KnowledgeLayout? _layout;
  String _layoutKey = '';
  List<KnowledgeNode> _nodes = const [];
  List<KnowledgeEdge> _edges = const [];
  Size _viewport = Size.zero;

  /// Trần số khái niệm vẽ cùng lúc. Nhiều hơn thế thì mạng thành búi rối và
  /// chữ nhỏ tới mức không đọc được khi thu vừa khung nhìn.
  static const int maxConcepts = 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppState.instance.ensureKnowledge();
    });
  }

  @override
  void dispose() {
    _viewer.dispose();
    super.dispose();
  }

  void _setFocus(_Focus focus) => setState(() => _focus = focus);

  // ------------------------------------------------------------------
  // CHỌN PHẦN ĐỒ THỊ SẼ VẼ
  // ------------------------------------------------------------------

  /// Môn trong phạm vi đang xem (khung đang lọc) có dữ liệu tri thức.
  Map<String, SubjectKnowledge> _scopeSubjects(KnowledgeIndex index) => {
    for (final s in widget.data.subjects)
      if (index.subjects[s.code.toUpperCase()] != null)
        s.code.toUpperCase(): index.subjects[s.code.toUpperCase()]!,
  };

  /// Học kỳ theo **khung đang xem** (khác kỳ mặc định lưu trong bảng môn).
  Map<String, int> get _semesterOf => {
    for (final s in widget.data.subjects) s.code.toUpperCase(): s.semester,
  };

  List<KnowledgeConcept> _visibleConcepts(
    KnowledgeIndex index,
    Map<String, SubjectKnowledge> scope,
  ) {
    final minSubjects = _sharedOnly ? 2 : 1;
    final list = <(KnowledgeConcept, int)>[];
    for (final c in index.concepts.values) {
      if (c.generic && !_showGeneric) continue;
      final n = c.bySubject.keys.where(scope.containsKey).length;
      if (n < minSubjects) continue;
      list.add((c, n));
    }
    list.sort((a, b) {
      final byCount = b.$2.compareTo(a.$2);
      return byCount != 0 ? byCount : a.$1.label.compareTo(b.$1.label);
    });
    return [for (final e in list.take(maxConcepts)) e.$1];
  }

  void _ensureLayout(
    BuildContext context,
    KnowledgeIndex index,
    Map<String, SubjectKnowledge> scope,
    List<KnowledgeConcept> concepts,
  ) {
    final baseStyle = DefaultTextStyle.of(context).style;
    final key = [
      identityHashCode(index),
      scope.keys.join(','),
      concepts.map((c) => c.id).join(','),
    ].join('|');
    if (key == _layoutKey && _layout != null) return;

    final semesters = _semesterOf;
    final conceptIds = {for (final c in concepts) c.id};
    final nodes = <KnowledgeNode>[];
    final edges = <KnowledgeEdge>[];
    final linkedSubjects = <String>{};
    for (final c in concepts) {
      for (final entry in c.bySubject.entries) {
        if (!scope.containsKey(entry.key)) continue;
        linkedSubjects.add(entry.key);
        edges.add(KnowledgeEdge(entry.key, c.id, 0.4 + entry.value.weight / 3));
      }
    }
    for (final code in linkedSubjects) {
      nodes.add(
        KnowledgeNode(
          id: code,
          isSubject: true,
          width: 20 + _textWidth(baseStyle, code, 13, FontWeight.w800),
          height: 30,
          semester: semesters[code] ?? 0,
        ),
      );
    }
    for (final c in concepts) {
      if (!conceptIds.contains(c.id)) continue;
      nodes.add(
        KnowledgeNode(
          id: c.id,
          isSubject: false,
          width:
              18 +
              _textWidth(
                baseStyle,
                c.label,
                _conceptFont(_countIn(c, scope)),
                _countIn(c, scope) >= 3 ? FontWeight.w700 : FontWeight.w500,
              ),
          height: 26,
        ),
      );
    }

    _nodes = nodes;
    _edges = edges;
    _layout = KnowledgeLayout.compute(nodes, edges);
    _layoutKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
  }

  double _conceptFont(int subjects) =>
      (12.0 + math.min(4, subjects - 1) * 0.9).toDouble();

  int _countIn(KnowledgeConcept c, Map<String, SubjectKnowledge> scope) =>
      c.bySubject.keys.where(scope.containsKey).length;

  /// Đo đúng bề ngang chữ để viên thuốc ôm vừa nhãn — ước lượng theo số ký tự
  /// thì chữ tiếng Việt có dấu hay tràn ra ngoài.
  static double _textWidth(
    TextStyle base,
    String text,
    double size,
    FontWeight weight,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: base.copyWith(fontSize: size, fontWeight: weight),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width.ceilToDouble();
  }

  /// Thu phóng để thấy trọn mạng trong khung nhìn.
  void _fit() {
    final layout = _layout;
    if (!mounted || layout == null || _viewport == Size.zero) return;
    // Không thu nhỏ quá 0.6 để chữ còn đọc được; phần tràn ra thì kéo/cuộn.
    final scale = math
        .min(
          _viewport.width / layout.size.width,
          _viewport.height / layout.size.height,
        )
        .clamp(0.6, 1.4);
    final dx = (_viewport.width - layout.size.width * scale) / 2;
    final dy = (_viewport.height - layout.size.height * scale) / 2;
    _viewer.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(dx, dy, 0);
  }

  // ------------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        if (state.knowledgeStale && !state.knowledgeBusy) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => state.ensureKnowledge(),
          );
        }
        final index = state.knowledge;
        if (index == null) {
          if (state.knowledgeError != null) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Không dựng được mạng tri thức',
              message: state.knowledgeError!,
            );
          }
          return const Center(child: CircularProgressIndicator());
        }

        final scope = _scopeSubjects(index);
        final concepts = _visibleConcepts(index, scope);
        final withSyllabus = scope.values.where((s) => s.hasSyllabus).length;
        if (withSyllabus == 0) {
          return const EmptyState(
            icon: Icons.psychology_outlined,
            title: 'Chưa có syllabus để trích tri thức',
            message:
                'Tải các trang "Syllabus Details" trên FLM bằng extension rồi '
                'bấm "Nhập từ fap_inbox". Mỗi syllabus cho biết môn học dạy '
                'những khái niệm nào qua CLO và từng buổi học.',
          );
        }
        _ensureLayout(context, index, scope, concepts);

        return Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  _toolbar(
                    context,
                    index,
                    scope,
                    concepts,
                    withSyllabus,
                    state,
                  ),
                  Expanded(child: _canvas(index, scope)),
                  _hintBar(),
                ],
              ),
            ),
            SizedBox(
              width: 360,
              child: _KnowledgePanel(
                index: index,
                scope: scope,
                semesterOf: _semesterOf,
                focus: _focus,
                onFocus: _setFocus,
                onShowSubjectGraph: widget.onShowSubjectGraph,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _toolbar(
    BuildContext context,
    KnowledgeIndex index,
    Map<String, SubjectKnowledge> scope,
    List<KnowledgeConcept> concepts,
    int withSyllabus,
    AppState state,
  ) {
    final categories = [
      for (final c in KnowledgeCategory.ordered)
        if (concepts.any((k) => k.category == c)) c,
      if (concepts.any((k) => k.extracted)) KnowledgeCategory.extracted,
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cụm công cụ bên trái, số liệu bên phải; hẹp thì số liệu xuống hàng.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 220,
                    height: 30,
                    child: Autocomplete<String>(
                      optionsBuilder: (value) {
                        final q = value.text.trim().toLowerCase();
                        if (q.isEmpty) return const Iterable<String>.empty();
                        return [
                          for (final code in scope.keys)
                            if (code.toLowerCase().contains(q)) 'môn:$code',
                          for (final c in index.concepts.values)
                            if (c.label.toLowerCase().contains(q)) 'kn:${c.id}',
                        ].take(12);
                      },
                      displayStringForOption: (o) => o.startsWith('môn:')
                          ? o.substring(4)
                          : index.concepts[o.substring(3)]?.label ?? o,
                      onSelected: (o) {
                        _setFocus(
                          o.startsWith('môn:')
                              ? _SubjectFocus(o.substring(4))
                              : _ConceptFocus(o.substring(3)),
                        );
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, submit) => TextField(
                            controller: controller,
                            focusNode: focusNode,
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Tìm môn hoặc khái niệm…',
                              hintStyle: TextStyle(
                                fontSize: 12,
                                color: AppColors.textHint,
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 30,
                              ),
                              contentPadding: EdgeInsets.zero,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilterChip(
                    label: const Text('Chỉ tri thức chung ≥ 2 môn'),
                    labelStyle: _chipStyle(context),
                    visualDensity: VisualDensity.compact,
                    selected: _sharedOnly,
                    onSelected: (v) => setState(() => _sharedOnly = v),
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('Hiện kỹ năng chung'),
                    labelStyle: _chipStyle(context),
                    visualDensity: VisualDensity.compact,
                    tooltip:
                        'Làm việc nhóm, thuyết trình, dùng công cụ AI… xuất hiện ở '
                        'rất nhiều môn nên mặc định bị ẩn để các cụm tri thức '
                        'chuyên môn hiện rõ.',
                    selected: _showGeneric,
                    onSelected: (v) => setState(() => _showGeneric = v),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message:
                        'Trích từ tên môn, mô tả, CLO và chủ đề từng buổi của '
                        '$withSyllabus syllabus trong '
                        '${index.elapsed.inMilliseconds} ms',
                    child: Text(
                      '${concepts.length} khái niệm · ${scope.length} môn',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Vừa khung nhìn',
                    icon: const Icon(Icons.fit_screen_outlined, size: 18),
                    color: AppColors.textSecondary,
                    onPressed: _fit,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  'Làm nổi nhóm:',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                for (final c in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        '$c (${concepts.where((k) => k.category == c).length})',
                      ),
                      labelStyle: _chipStyle(context),
                      visualDensity: VisualDensity.compact,
                      selected: _category == c,
                      onSelected: (v) =>
                          setState(() => _category = v ? c : null),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Nhãn chip lấy từ typography của theme để cùng font với phần còn lại.
  TextStyle? _chipStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium?.copyWith(fontSize: 11.5);

  Widget _hintBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          _legendBox(isSubject: true),
          const SizedBox(width: 6),
          Text('Môn học', style: _hintStyle),
          const SizedBox(width: 16),
          _legendBox(isSubject: false),
          const SizedBox(width: 6),
          Text(
            'Khái niệm (chữ càng to càng nhiều môn cùng dạy)',
            style: _hintStyle,
          ),
          const Spacer(),
          Text(
            'Bấm một nút để xem chi tiết · cuộn để zoom · kéo để di chuyển',
            style: TextStyle(fontSize: 11.5, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  TextStyle get _hintStyle =>
      TextStyle(fontSize: 11.5, color: AppColors.textPrimary);

  Widget _legendBox({required bool isSubject}) => Container(
    width: isSubject ? 18 : 22,
    height: 11,
    decoration: BoxDecoration(
      color: isSubject
          ? AppColors.surface
          : AppColors.primary.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(isSubject ? 3 : 6),
      border: Border.all(
        color: isSubject ? AppColors.textSecondary : AppColors.primary,
      ),
    ),
  );

  // ------------------------------------------------------------------
  // KHUNG VẼ
  // ------------------------------------------------------------------

  /// Các nút đang được làm nổi theo tiêu điểm hiện tại. `null` nghĩa là
  /// không làm mờ gì cả.
  Set<String>? _highlighted(KnowledgeIndex index) {
    switch (_focus) {
      case _NoFocus():
        return null;
      case _ConceptFocus(:final id):
        return {id, ...?index.concepts[id]?.bySubject.keys};
      case _SubjectFocus(:final code):
        final s = index.subjects[code];
        return {code, ...?s?.concepts.map((c) => c.conceptId)};
      case _CompareFocus(:final a, :final b):
        final link = index.linkBetween(a, b);
        return {a, b, ...?link?.sharedConceptIds};
    }
  }

  Widget _canvas(KnowledgeIndex index, Map<String, SubjectKnowledge> scope) {
    final layout = _layout!;
    final highlighted = _highlighted(index);
    final positions = layout.positions;

    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        if (size != _viewport) {
          final first = _viewport == Size.zero;
          _viewport = size;
          if (first) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
          }
        }
        return Container(
          color: AppColors.background,
          child: InteractiveViewer(
            transformationController: _viewer,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(400),
            minScale: 0.15,
            maxScale: 3,
            child: SizedBox(
              width: layout.size.width,
              height: layout.size.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _setFocus(const _NoFocus()),
                      child: CustomPaint(
                        painter: _EdgePainter(
                          edges: _edges,
                          positions: positions,
                          highlighted: highlighted,
                          base: AppColors.textHint.withValues(alpha: 0.28),
                          accent: AppColors.primary.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
                  for (final node in _nodes)
                    if (positions[node.id] != null)
                      Positioned(
                        left: positions[node.id]!.dx - node.width / 2,
                        top: positions[node.id]!.dy - node.height / 2,
                        child: node.isSubject
                            ? _subjectNode(node, index, highlighted)
                            : _conceptNode(node, index, scope, highlighted),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _subjectNode(
    KnowledgeNode node,
    KnowledgeIndex index,
    Set<String>? highlighted,
  ) {
    final s = index.subjects[node.id];
    final isFocus = switch (_focus) {
      _SubjectFocus(:final code) => code == node.id,
      _CompareFocus(:final a, :final b) => a == node.id || b == node.id,
      _ => false,
    };
    final dim = highlighted != null && !highlighted.contains(node.id);
    final semester = _semesterOf[node.id] ?? s?.semester ?? 0;
    return Opacity(
      opacity: dim ? 0.18 : 1,
      child: Tooltip(
        message:
            '${node.id} — ${s?.name ?? ''}\nHK$semester · '
            '${s?.concepts.length ?? 0} khái niệm'
            '${s?.hasSyllabus == false ? ' (chưa có syllabus)' : ''}',
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
          onTap: () => _setFocus(_SubjectFocus(node.id)),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              width: node.width,
              height: node.height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isFocus ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isFocus ? AppColors.primary : AppColors.textSecondary,
                  width: isFocus ? 2 : 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                node.id,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isFocus ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _conceptNode(
    KnowledgeNode node,
    KnowledgeIndex index,
    Map<String, SubjectKnowledge> scope,
    Set<String>? highlighted,
  ) {
    final concept = index.concepts[node.id]!;
    final n = _countIn(concept, scope);
    final isFocus =
        _focus is _ConceptFocus && (_focus as _ConceptFocus).id == node.id;
    final inCategory = _category == null || concept.category == _category;
    final dim =
        (highlighted != null && !highlighted.contains(node.id)) || !inCategory;
    final accent = isFocus || (_category != null && inCategory);
    final base = concept.extracted || concept.generic
        ? AppColors.textSecondary
        : AppColors.primary;

    return Opacity(
      opacity: dim ? 0.2 : 1,
      child: Tooltip(
        message:
            '${concept.label}\n${concept.category} · $n môn cùng dạy'
            '${concept.extracted ? '\n(tự trích theo tần suất, không có trong từ điển)' : ''}'
            '${concept.generic ? '\n(kỹ năng chung — không dùng để nối môn)' : ''}',
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
          onTap: () => _setFocus(_ConceptFocus(node.id)),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              width: node.width,
              height: node.height,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: accent
                    ? AppColors.primary
                    : base.withValues(alpha: AppColors.isDark ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: accent
                      ? AppColors.primary
                      : base.withValues(alpha: 0.7),
                  width: isFocus ? 2 : 1,
                ),
              ),
              child: Text(
                concept.label,
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
                style: TextStyle(
                  fontSize: _conceptFont(n),
                  fontWeight: n >= 3 ? FontWeight.w700 : FontWeight.w500,
                  color: accent ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  final List<KnowledgeEdge> edges;
  final Map<String, Offset> positions;
  final Set<String>? highlighted;
  final Color base;
  final Color accent;

  _EdgePainter({
    required this.edges,
    required this.positions,
    required this.highlighted,
    required this.base,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final normal = Paint()
      ..color = base
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final strong = Paint()
      ..color = accent
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final faded = Paint()
      ..color = base.withValues(alpha: base.a * 0.35)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final hl = highlighted;
    // Vẽ cạnh thường trước, cạnh được làm nổi sau để nằm đè lên trên.
    for (final pass in [false, true]) {
      for (final e in edges) {
        final a = positions[e.a];
        final b = positions[e.b];
        if (a == null || b == null) continue;
        final isStrong = hl != null && hl.contains(e.a) && hl.contains(e.b);
        if (isStrong != pass) continue;
        final paint = isStrong ? strong : (hl == null ? normal : faded);
        canvas.drawLine(a, b, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) =>
      old.edges != edges ||
      old.positions != positions ||
      old.highlighted != highlighted ||
      old.base != base ||
      old.accent != accent;
}

// ============================================================================
// BẢNG CHI TIẾT BÊN PHẢI
// ============================================================================

class _KnowledgePanel extends StatelessWidget {
  final KnowledgeIndex index;
  final Map<String, SubjectKnowledge> scope;
  final Map<String, int> semesterOf;
  final _Focus focus;
  final ValueChanged<_Focus> onFocus;
  final VoidCallback? onShowSubjectGraph;

  const _KnowledgePanel({
    required this.index,
    required this.scope,
    required this.semesterOf,
    required this.focus,
    required this.onFocus,
    this.onShowSubjectGraph,
  });

  int _semester(String code) =>
      semesterOf[code] ?? index.subjects[code]?.semester ?? 0;

  /// Liên kết giữa các môn đều nằm trong phạm vi đang xem.
  List<KnowledgeLink> get _scopeLinks => [
    for (final l in index.links)
      if (scope.containsKey(l.from) && scope.containsKey(l.to)) l,
  ];

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (focus) {
      _NoFocus() => _overview(context),
      _ConceptFocus(:final id) => _concept(context, id),
      _SubjectFocus(:final code) => _subject(context, code),
      _CompareFocus(:final a, :final b) => _compare(context, a, b),
    };
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        children: [
          if (focus is! _NoFocus)
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Tổng quan tri thức'),
                    onPressed: () => onFocus(const _NoFocus()),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              children: [body],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // TỔNG QUAN
  // ------------------------------------------------------------------

  Widget _overview(BuildContext context) {
    final links = _scopeLinks;
    final hidden = links.where((l) => l.isNotableHidden).toList();
    // Tri thức chuyên môn xếp trước kỹ năng mềm: "phương pháp nghiên cứu"
    // có mặt ở mười môn nhưng không nói gì về mạch kiến thức ngành.
    int soft(KnowledgeConcept c) =>
        c.category == KnowledgeCategory.society || c.extracted ? 1 : 0;
    final shared =
        [
          for (final c in index.concepts.values)
            if (c.linking)
              (c, c.bySubject.keys.where(scope.containsKey).length),
        ]..sort((a, b) {
          final bySoft = soft(a.$1).compareTo(soft(b.$1));
          return bySoft != 0 ? bySoft : b.$2.compareTo(a.$2);
        });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Tri thức của chương trình'),
        const SizedBox(height: 4),
        _muted(
          'Khái niệm được trích tự động từ tên môn, mô tả, CLO và chủ đề từng '
          'buổi trong syllabus. Hai môn tương quan khi dạy chung khái niệm — '
          'kể cả khi chương trình không đặt môn này làm tiên quyết của môn '
          'kia.',
        ),
        const SizedBox(height: 14),
        if (hidden.isNotEmpty)
          _Callout(
            icon: Icons.lightbulb_outline,
            text:
                '${hidden.length} cặp môn dùng chung từ hai khái niệm trở lên '
                'nhưng chưa có quan hệ tiên quyết nào — tương quan ẩn mà sơ đồ '
                'môn học không cho thấy. Nên ôn lại môn trước khi học môn sau.',
          ),
        const SizedBox(height: 14),
        _section('Tri thức xuyên suốt nhiều môn'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (c, n) in shared.take(14))
              if (n >= 2)
                _ConceptChip(
                  label: c.label,
                  count: n,
                  onTap: () => onFocus(_ConceptFocus(c.id)),
                ),
          ],
        ),
        const SizedBox(height: 18),
        _section('Cặp môn tương quan tri thức mạnh nhất'),
        if (links.isEmpty)
          _muted('Chưa tìm thấy cặp môn nào dùng chung tri thức.'),
        for (final l in links.take(12))
          _LinkTile(
            link: l,
            index: index,
            onTap: () => onFocus(_CompareFocus(l.from, l.to)),
          ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // MỘT KHÁI NIỆM
  // ------------------------------------------------------------------

  Widget _concept(BuildContext context, String id) {
    final c = index.concepts[id];
    if (c == null) return _muted('Khái niệm không còn trong chỉ mục.');
    final subjects =
        [
          for (final e in c.bySubject.entries)
            if (scope.containsKey(e.key)) e,
        ]..sort((a, b) {
          final bySem = _semester(a.key).compareTo(_semester(b.key));
          return bySem != 0 ? bySem : b.value.weight.compareTo(a.value.weight);
        });
    final maxWeight = subjects.fold<double>(
      0.01,
      (m, e) => math.max(m, e.value.weight),
    );

    // Khái niệm hay đi cùng: xuất hiện ở nhiều môn cùng với khái niệm này.
    final together = <String, int>{};
    for (final e in subjects) {
      for (final sc
          in index.subjects[e.key]?.concepts ?? const <SubjectConcept>[]) {
        if (sc.conceptId == id) continue;
        final other = index.concepts[sc.conceptId];
        if (other == null || !other.linking) continue;
        together[sc.conceptId] = (together[sc.conceptId] ?? 0) + 1;
      }
    }
    final co = together.entries.where((e) => e.value >= 2).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(c.label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Tag(text: c.category),
            _Tag(text: '${subjects.length} môn trong khung'),
            if (c.extracted) const _Tag(text: 'tự trích'),
            if (c.generic) const _Tag(text: 'kỹ năng chung'),
          ],
        ),
        const SizedBox(height: 16),
        _section('Lộ trình của khái niệm qua các kỳ'),
        _muted(
          'Xếp theo học kỳ: môn đầu tiên là nơi khái niệm được dạy lần đầu, '
          'các môn sau dùng lại hoặc đào sâu nó.',
        ),
        const SizedBox(height: 8),
        for (final e in subjects)
          _SubjectEvidence(
            code: e.key,
            name: index.subjects[e.key]?.name ?? '',
            semester: _semester(e.key),
            weight: e.value.weight / maxWeight,
            evidence: e.value.evidence,
            onTap: () => onFocus(_SubjectFocus(e.key)),
          ),
        if (co.isNotEmpty) ...[
          const SizedBox(height: 14),
          _section('Hay đi cùng'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in co.take(10))
                _ConceptChip(
                  label: index.concepts[e.key]!.label,
                  count: e.value,
                  onTap: () => onFocus(_ConceptFocus(e.key)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------------
  // MỘT MÔN
  // ------------------------------------------------------------------

  Widget _subject(BuildContext context, String code) {
    final s = index.subjects[code];
    if (s == null) return _muted('Môn này chưa có dữ liệu tri thức.');
    final links = [
      for (final l in index.linksOf(code))
        if (scope.containsKey(l.other(code))) l,
    ];
    final concepts = [
      for (final c in s.concepts)
        if (index.concepts[c.conceptId] != null) c,
    ];
    final programming = s.programmingScore >= AppState.programmingThreshold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('$code · HK${_semester(code)}'),
        const SizedBox(height: 2),
        _muted(s.name.replaceAll('_', ' — ')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Tag(text: s.hasSyllabus ? 'có syllabus' : 'chưa có syllabus'),
            if (programming)
              _Tag(
                text:
                    'có kiến thức lập trình (${(s.programmingScore * 100).round()}%)',
                icon: Icons.code,
              ),
          ],
        ),
        if (onShowSubjectGraph != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.hub_outlined, size: 16),
            label: const Text('Xem môn này trên sơ đồ tiên quyết'),
            onPressed: () {
              final subject = AppState.instance.graph.byCode[code];
              if (subject?.id != null) AppState.instance.select(subject!.id);
              onShowSubjectGraph!();
            },
          ),
        ],
        const SizedBox(height: 12),
        _section('Khái niệm trích được (${concepts.length})'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in concepts)
              _ConceptChip(
                label: index.concepts[c.conceptId]!.label,
                faded: !index.concepts[c.conceptId]!.linking,
                onTap: () => onFocus(_ConceptFocus(c.conceptId)),
              ),
          ],
        ),
        if (s.keywords.isNotEmpty) ...[
          const SizedBox(height: 14),
          _section('Từ khoá đặc trưng (tự trích, TF-IDF)'),
          _muted('Cụm từ hiếm ở các môn khác nhưng nổi bật ở môn này.'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final k in s.keywords) _Tag(text: k.phrase)],
          ),
        ],
        const SizedBox(height: 16),
        _section('Tương quan tri thức với các môn khác'),
        if (links.isEmpty)
          _muted(
            'Chưa thấy môn nào trong khung dùng chung tri thức với môn này.',
          ),
        for (final l in links.take(12))
          _LinkTile(
            link: l,
            index: index,
            focusCode: code,
            onTap: () => onFocus(_CompareFocus(l.from, l.to)),
          ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // SO SÁNH HAI MÔN
  // ------------------------------------------------------------------

  Widget _compare(BuildContext context, String a, String b) {
    final sa = index.subjects[a];
    final sb = index.subjects[b];
    if (sa == null || sb == null) return _muted('Thiếu dữ liệu của một môn.');
    final link = index.linkBetween(a, b);
    final shared = link?.sharedConceptIds ?? const <String>[];
    final aIds = {for (final c in sa.concepts) c.conceptId};
    final bIds = {for (final c in sb.concepts) c.conceptId};
    bool shows(String id) {
      final c = index.concepts[id];
      return c != null && !c.generic;
    }

    final onlyA = [
      for (final id in aIds)
        if (!bIds.contains(id) && shows(id)) id,
    ];
    final onlyB = [
      for (final id in bIds)
        if (!aIds.contains(id) && shows(id)) id,
    ];
    final first = _semester(a) <= _semester(b) ? a : b;
    final second = first == a ? b : a;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('$a ↔ $b'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (link != null)
              _Tag(text: 'tương quan ${(link.similarity * 100).round()}%'),
            _Tag(
              text: link?.hasDirectEdge == true
                  ? 'đã có quan hệ trên sơ đồ'
                  : 'tương quan ẩn — chưa có quan hệ tiên quyết',
              icon: link?.hasDirectEdge == true
                  ? Icons.link
                  : Icons.lightbulb_outline,
            ),
          ],
        ),
        if (link != null && !link.hasDirectEdge && shared.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Callout(
            icon: Icons.tips_and_updates_outlined,
            text:
                'Trước khi học $second (HK${_semester(second)}), nên ôn lại '
                '${shared.take(3).map((id) => index.concepts[id]?.label ?? id).join(', ')} '
                'đã học ở $first (HK${_semester(first)}).',
          ),
        ],
        const SizedBox(height: 16),
        _section('Tri thức chung (${shared.length})'),
        if (shared.isEmpty)
          _muted('Hai môn không có khái niệm chuyên môn chung.'),
        for (final id in shared)
          _SharedConcept(
            label: index.concepts[id]?.label ?? id,
            a: a,
            b: b,
            evidenceA: sa.conceptOf(id)?.evidence ?? const [],
            evidenceB: sb.conceptOf(id)?.evidence ?? const [],
            onTap: () => onFocus(_ConceptFocus(id)),
          ),
        const SizedBox(height: 14),
        _section('Chỉ $a có'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final id in onlyA)
              _ConceptChip(
                label: index.concepts[id]!.label,
                onTap: () => onFocus(_ConceptFocus(id)),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _section('Chỉ $b có'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final id in onlyB)
              _ConceptChip(
                label: index.concepts[id]!.label,
                onTap: () => onFocus(_ConceptFocus(id)),
              ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------------

  Widget _title(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
    ),
  );

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w800,
        color: AppColors.textSecondary,
      ),
    ),
  );

  Widget _muted(String text) => Text(
    text,
    style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.textSecondary),
  );
}

class _Callout extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Callout({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final IconData? icon;

  const _Tag({required this.text, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.obsidianActive,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: AppColors.textSecondary),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 11.5, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConceptChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool faded;
  final VoidCallback onTap;

  const _ConceptChip({
    required this.label,
    this.count,
    this.faded = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: faded
              ? AppColors.obsidianActive
              : AppColors.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: faded
                ? AppColors.border
                : AppColors.primary.withValues(alpha: 0.45),
          ),
        ),
        child: Text(
          count == null ? label : '$label · $count',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: faded ? AppColors.textSecondary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final KnowledgeLink link;
  final KnowledgeIndex index;
  final String? focusCode;
  final VoidCallback onTap;

  const _LinkTile({
    required this.link,
    required this.index,
    this.focusCode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = focusCode == null
        ? '${link.from} ↔ ${link.to}'
        : '→ ${link.other(focusCode!)}';
    final shared = link.sharedConceptIds
        .take(4)
        .map((id) => index.concepts[id]?.label ?? id)
        .join(', ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              child: Text(
                '${(link.similarity * 100).round()}%',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: link.hasDirectEdge
                            ? 'Hai môn đã nối nhau trên sơ đồ tiên quyết'
                            : 'Tương quan ẩn: dùng chung tri thức nhưng chưa có '
                                  'quan hệ tiên quyết',
                        child: Icon(
                          link.hasDirectEdge
                              ? Icons.link
                              : Icons.lightbulb_outline,
                          size: 14,
                          color: link.hasDirectEdge
                              ? AppColors.textHint
                              : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    shared,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectEvidence extends StatelessWidget {
  final String code;
  final String name;
  final int semester;
  final double weight;
  final List<ConceptEvidence> evidence;
  final VoidCallback onTap;

  const _SubjectEvidence({
    required this.code,
    required this.name,
    required this.semester,
    required this.weight,
    required this.evidence,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'HK$semester',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  code,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: 'Mức độ môn này dạy khái niệm',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: weight.clamp(0.05, 1.0),
                        minHeight: 5,
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.12,
                        ),
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (name.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                name.replaceAll('_', ' — '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            for (final e in evidence.take(2)) ...[
              const SizedBox(height: 6),
              _EvidenceLine(evidence: e),
            ],
          ],
        ),
      ),
    );
  }
}

class _EvidenceLine extends StatelessWidget {
  final ConceptEvidence evidence;

  const _EvidenceLine({required this.evidence});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.obsidianActive,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            evidence.ref,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            evidence.snippet,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              fontStyle: FontStyle.italic,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _SharedConcept extends StatelessWidget {
  final String label;
  final String a;
  final String b;
  final List<ConceptEvidence> evidenceA;
  final List<ConceptEvidence> evidenceB;
  final VoidCallback onTap;

  const _SharedConcept({
    required this.label,
    required this.a,
    required this.b,
    required this.evidenceA,
    required this.evidenceB,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            if (evidenceA.isNotEmpty) ...[
              const SizedBox(height: 6),
              _side(a, evidenceA.first),
            ],
            if (evidenceB.isNotEmpty) ...[
              const SizedBox(height: 6),
              _side(b, evidenceB.first),
            ],
          ],
        ),
      ),
    );
  }

  Widget _side(String code, ConceptEvidence e) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 62,
        child: Text(
          code,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      ),
      Expanded(child: _EvidenceLine(evidence: e)),
    ],
  );
}
