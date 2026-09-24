import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/graph_data.dart';
import '../../models/subject.dart';
import '../../models/transcript_entry.dart';
import '../../models/curriculum.dart';
import '../../models/graph_settings.dart';
import '../../models/knowledge.dart';
import '../../models/mini_graph_pin.dart';
import '../../services/graph_layout_cache.dart';
import '../../services/chat_session_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';
import '../subjects/roadmap_dialog.dart';
import '../curriculum/fap_inbox_import.dart';
import '../curriculum/semester_board_view.dart';
import '../knowledge/knowledge_map_view.dart';
import '../subjects/subject_form_dialog.dart';
import '../widgets/mini_graph_panel.dart';
import '../widgets/subject_detail_panel.dart';
import 'graph_settings_panel.dart';

/// Màn hình của một khung chương trình:
/// - **Sơ đồ**: đồ thị tiên quyết giữa các môn + toggle hiện tri thức syllabus trực tiếp.
/// - **Học kỳ**: bảng HK0/HK1 → HK9 xếp ngang, mỗi môn một thẻ.
class GraphPage extends StatefulWidget {
  /// Quay về màn hình tổng quan mọi khung chương trình.
  final VoidCallback? onOpenOverview;
  final VoidCallback? onOpenAiChat;

  const GraphPage({super.key, this.onOpenOverview, this.onOpenAiChat});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  final TransformationController _viewer = TransformationController();
  final GlobalKey<_ObsidianGraphCanvasState> _canvasKey =
      GlobalKey<_ObsidianGraphCanvasState>();

  bool _showRelated = true;
  bool _showSettings = false;
  bool _showKnowledge = false;
  bool _showKnowledgePanel = false;
  String? _selectedConceptId;
  String? _selectedSubjectCode;
  int? _semesterFilter;

  Future<void> _batchImportInbox(BuildContext context) =>
      FapInboxImport.run(context);

  static String _viewTitle(CurriculumView view) => switch (view) {
    CurriculumView.graph => 'Sơ đồ môn học',
    CurriculumView.board => 'Bảng học kỳ',
    CurriculumView.knowledge => 'Mạng tri thức',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resetZoom());
  }

  @override
  void dispose() {
    _viewer.dispose();
    super.dispose();
  }

  void _resetZoom() {
    if (!mounted) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? const Size(900, 600);
    final dx = size.width / 2 - 1000.0;
    final dy = size.height / 2 - 1000.0;
    _viewer.value = Matrix4.identity()..setTranslationRaw(dx, dy, 0);
  }

  /// Ghim khung đang xem thành ô đồ thị thu nhỏ trên thanh bên.
  ///
  /// Đây là đường dự phòng cho thao tác kéo tab "Graph view" vào thanh bên:
  /// kéo thả chuẩn xác không phải ai cũng làm được, và trên máy chỉ có
  /// touchpad thì càng khó.
  Future<void> _pinCurrentToSidebar(AppState state) async {
    final code = state.activeCurriculumCode;
    final label = code ?? 'Toàn bộ môn';
    // Đi chung đường với thao tác kéo thả để cùng một luật trang: trùng thì
    // chỉ chuyển trang, đủ trang thì `pinWithFeedback` tự báo.
    final result = await MiniGraphPanel.pinWithFeedback(context, code);
    if (!mounted) return;
    switch (result) {
      case MiniGraphPinResult.added:
        Ui.success(
          context,
          'Đã ghim "$label" thành một trang của đồ thị thu nhỏ ở thanh bên.',
        );
      case MiniGraphPinResult.switched:
        Ui.toast(context, 'Đồ thị thu nhỏ đã chuyển tới trang "$label".');
      case MiniGraphPinResult.full:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final currentGraph = state.currentGraph;
        final activeGroup = state.curriculumGroups
            .cast<CurriculumGroup?>()
            .firstWhere(
              (g) => g?.code == state.activeCurriculumCode,
              orElse: () => null,
            );
        final semesters =
            currentGraph.subjects.map((s) => s.semester).toSet().toList()
              ..sort();
        final view = state.curriculumView;
        final isGraph = view == CurriculumView.graph;

        // Chỉ mở KnowledgeSidebarPanel khi ở view graph và không có môn nào đang được chọn (tránh hiện 2 sidebar cùng lúc)
        final hasSubjectSelected = state.selectedSubjectId != null;
        final showKnowledgePanel =
            isGraph &&
            _showKnowledgePanel &&
            !hasSubjectSelected &&
            state.knowledge != null;

        final index = state.knowledge;
        final scope = <String, SubjectKnowledge>{};
        final semesterOf = <String, int>{};
        if (showKnowledgePanel && index != null) {
          for (final s in currentGraph.subjects) {
            semesterOf[s.code] = s.semester;
            final sk = index.subjects[s.code];
            if (sk != null) {
              scope[s.code] = sk;
            } else {
              scope[s.code] = SubjectKnowledge(
                code: s.code,
                name: s.name,
                semester: s.semester,
                hasSyllabus: false,
                concepts: const [],
                keywords: const [],
              );
            }
          }
        }

        return Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  PageHeader(
                    title: activeGroup != null
                        ? '${_viewTitle(view)} · ${activeGroup.isUnassigned ? 'Môn ngoài khung' : activeGroup.code}'
                        : '${_viewTitle(view)} · Tất cả khung',
                    subtitle: activeGroup != null
                        ? '${currentGraph.subjects.length} môn · ${currentGraph.edges.length} liên kết'
                        : '${state.stats['subjects'] ?? 0} môn học · ${state.stats['edges'] ?? 0} liên kết tiên quyết',
                    actions: [
                      if (state.curriculumGroups.isNotEmpty) ...[
                        _CurriculumFilter(
                          groups: state.curriculumGroups,
                          value: state.activeCurriculumCode,
                          onChanged: (v) => state.setActiveCurriculum(v),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (isGraph) ...[
                        _SemesterFilter(
                          semesters: semesters,
                          value: _semesterFilter,
                          onChanged: (v) => setState(() => _semesterFilter = v),
                        ),
                        const SizedBox(width: 8),
                      ],
                      SizedBox(
                        height: 32,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.route_outlined, size: 16),
                          label: const Text(
                            'Gợi ý lộ trình',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: AppColors.border.withValues(alpha: 0.7),
                              width: 0.8,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: () => _showLearningOrder(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 32,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
                          label: const Text(
                            'Hỏi AI',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.45),
                              width: 1.0,
                            ),
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 0,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: () {
                            final code = state.activeCurriculumCode;
                            ChatSessionService.instance.newSession(
                              curriculumCode: code,
                              title: code != null ? 'Hỏi về $code' : 'Hỏi AI về chương trình',
                            );
                            widget.onOpenAiChat?.call();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 32,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add, size: 15),
                          label: const Text(
                            'Thêm môn',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: () => SubjectFormDialog.show(context),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Visibility(
                          visible: isGraph,
                          maintainState: true,
                          child: _graphCanvas(context, state, currentGraph),
                        ),
                        if (view == CurriculumView.board)
                          SemesterBoardView(data: currentGraph),
                        if (view == CurriculumView.knowledge)
                          KnowledgeMapView(
                            data: currentGraph,
                            onShowSubjectGraph: () =>
                                state.setCurriculumView(CurriculumView.graph),
                          ),
                      ],
                    ),
                  ),
                  if (isGraph) _Legend(isDark: state.isDark),
                ],
              ),
            ),
            if (isGraph)
              SizedBox(
                width: 320,
                child: showKnowledgePanel && index != null
                    ? KnowledgeSidebarPanel(
                        index: index,
                        scope: scope,
                        semesterOf: semesterOf,
                        initialConceptId: _selectedConceptId,
                        initialSubjectCode: _selectedSubjectCode,
                        onSelectConcept: (cid) => setState(() {
                          _selectedConceptId = cid;
                          _selectedSubjectCode = null;
                        }),
                        onSelectSubject: (code) => setState(() {
                          _selectedConceptId = null;
                          _selectedSubjectCode = code;
                        }),
                        onClose: () => setState(() {
                          _showKnowledge = false;
                          _showKnowledgePanel = false;
                          _selectedConceptId = null;
                          _selectedSubjectCode = null;
                        }),
                        onShowSubjectGraph: () {},
                      )
                    : const SubjectDetailPanel(),
              ),
          ],
        );
      },
    );
  }

  Widget _graphCanvas(
    BuildContext context,
    AppState state,
    GraphData currentGraph,
  ) {
    return Stack(
      children: [
        Positioned.fill(
          child: state.loading && currentGraph.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : currentGraph.isEmpty
              ? _emptyGraph(context)
              : _ObsidianGraphCanvas(
                  key: _canvasKey,
                  data: currentGraph,
                  settings: state.graphSettings,
                  showRelated: _showRelated,
                  showKnowledge: _showKnowledge,
                  semesterFilter: _semesterFilter,
                  curriculumCode: state.activeCurriculumCode,
                  selectedConceptId: _selectedConceptId,
                  selectedSubjectCode: _selectedSubjectCode,
                  onClearSelection: () => setState(() {
                    _selectedConceptId = null;
                    _selectedSubjectCode = null;
                  }),
                  viewer: _viewer,
                  onSelectSubject: (id) {
                    if (_showKnowledge && _showKnowledgePanel) {
                      final s = currentGraph.subjects
                          .cast<Subject?>()
                          .firstWhere((x) => x?.id == id, orElse: () => null);
                      if (s != null) {
                        setState(() {
                          _selectedConceptId = null;
                          _selectedSubjectCode = s.code;
                        });
                      }
                    } else {
                      setState(() {
                        _showKnowledgePanel = false;
                        _selectedConceptId = null;
                        _selectedSubjectCode = null;
                      });
                      state.select(id);
                    }
                  },
                  onSelectConcept: (conceptId) {
                    state.select(null); // Đóng bảng chi tiết môn học
                    if (state.knowledge == null) {
                      state.ensureKnowledge();
                    }
                    setState(() {
                      _showKnowledge = true;
                      _showKnowledgePanel = true;
                      _selectedConceptId = conceptId;
                      _selectedSubjectCode = null;
                    });
                  },
                ),
        ),
        if (state.graphSettings.colorMode == 'grade')
          const Positioned(left: 12, bottom: 12, child: _GradeLegend()),
        if (_showSettings)
          Positioned(
            top: 14,
            right: 62,
            child: GraphSettingsPanel(
              settings: state.graphSettings,
              onChanged: (newSettings) =>
                  state.updateGraphSettings(newSettings),
              onClose: () => setState(() => _showSettings = false),
              onResimulate: () => _canvasKey.currentState?.resimulate(),
              onResetZoom: _resetZoom,
              onResetDefaults: () => state.resetGraphSettings(),
            ),
          ),
        // Floating toolbar 2 icon dọc (Cài đặt graph & Tri thức syllabus)
        Positioned(
          top: 14,
          right: 14,
          child: _GraphFloatingControls(
            showSettings: _showSettings,
            showKnowledge: _showKnowledge,
            showRelated: _showRelated,
            onToggleSettings: () =>
                setState(() => _showSettings = !_showSettings),
            onToggleKnowledge: () {
              if (!_showKnowledge) {
                state.ensureKnowledge();
                state.select(null); // Đóng bảng chi tiết môn học
                setState(() {
                  _showKnowledge = true;
                  _showKnowledgePanel = true;
                  _selectedConceptId = null;
                  _selectedSubjectCode = null;
                });
              } else {
                setState(() {
                  _showKnowledge = false;
                  _showKnowledgePanel = false;
                  _selectedConceptId = null;
                  _selectedSubjectCode = null;
                });
              }
            },
            onToggleRelated: () => setState(() => _showRelated = !_showRelated),
            onPinMiniGraph: () => _pinCurrentToSidebar(state),
            isMiniGraphPinned: state.isMiniGraphPinned(
              state.activeCurriculumCode,
            ),
            onResetZoom: _resetZoom,
            onRefresh: state.refresh,
          ),
        ),
      ],
    );
  }

  Widget _emptyGraph(BuildContext context) {
    return EmptyState(
      icon: Icons.hub_outlined,
      title: 'Đồ thị đang trống',
      message: 'Thêm môn học đầu tiên để bắt đầu xem sơ đồ quan hệ môn học.',
      action: Wrap(
        spacing: 12,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.cloud_download_outlined, size: 18),
            label: const Text('Nhập từ fap_inbox'),
            onPressed: () => _batchImportInbox(context),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Thêm môn học'),
            onPressed: () => SubjectFormDialog.show(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showLearningOrder(BuildContext context) async {
    final state = AppState.instance;
    final order = await state.suggestLearningOrder();
    if (!context.mounted) return;

    if (order == null) {
      Ui.error(
        context,
        'Đồ thị đang có chu trình tiên quyết nên không sắp xếp được lộ trình.',
      );
      return;
    }
    if (order.isEmpty) {
      Ui.toast(context, 'Chưa có môn nào trong khung hiện tại để sắp xếp.');
      return;
    }

    RoadmapDialog.show(
      context,
      order: order,
      curriculumCode: state.activeCurriculumCode,
      graphData: state.currentGraph,
    );
  }
}

// ============================================================================
// OBSIDIAN PHYSICS & DRAG-AND-DROP GRAPH ENGINE
// ============================================================================

class _NodeSim {
  final Subject? subject;
  final KnowledgeConcept? concept;
  double x;
  double y;
  double vx = 0;
  double vy = 0;
  bool isDragging = false;

  bool get isConcept => concept != null;
  String get id => isConcept ? 'c_${concept!.id}' : 's_${subject!.id}';

  _NodeSim({this.subject, this.concept, required this.x, required this.y});
}

class _EdgeSim {
  final _NodeSim from;
  final _NodeSim to;
  final bool isHard;
  final bool isConceptLink;

  _EdgeSim({
    required this.from,
    required this.to,
    this.isHard = true,
    this.isConceptLink = false,
  });
}

class _ObsidianGraphCanvas extends StatefulWidget {
  final GraphData data;
  final GraphSettings settings;
  final bool showRelated;
  final bool showKnowledge;
  final int? semesterFilter;
  final String? curriculumCode;
  final String? selectedConceptId;
  final String? selectedSubjectCode;
  final VoidCallback? onClearSelection;
  final TransformationController viewer;
  final ValueChanged<int>? onSelectSubject;
  final ValueChanged<String>? onSelectConcept;

  const _ObsidianGraphCanvas({
    super.key,
    required this.data,
    required this.settings,
    required this.showRelated,
    this.showKnowledge = false,
    required this.semesterFilter,
    this.curriculumCode,
    this.selectedConceptId,
    this.selectedSubjectCode,
    this.onClearSelection,
    required this.viewer,
    this.onSelectSubject,
    this.onSelectConcept,
  });

  @override
  State<_ObsidianGraphCanvas> createState() => _ObsidianGraphCanvasState();
}

class _ObsidianGraphCanvasState extends State<_ObsidianGraphCanvas>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<_NodeSim> _nodes = [];
  final List<_EdgeSim> _edges = [];
  bool _isDraggingAny = false;

  static const double canvasSize = 2000.0;
  static const double centerX = 1000.0;
  static const double centerY = 1000.0;
  double get nodeWidth => 110.0 * widget.settings.nodeScale;
  double get nodeHeight => 32.0 * widget.settings.nodeScale;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _syncGraph(resetPositions: true);
  }

  @override
  void didUpdateWidget(covariant _ObsidianGraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final filterChanged = widget.semesterFilter != oldWidget.semesterFilter;
    final relatedChanged = widget.showRelated != oldWidget.showRelated;
    final knowledgeChanged = widget.showKnowledge != oldWidget.showKnowledge;
    final dataChanged = widget.data != oldWidget.data;
    final curriculumChanged = widget.curriculumCode != oldWidget.curriculumCode;
    final settingsChanged = widget.settings != oldWidget.settings;

    if (filterChanged ||
        relatedChanged ||
        knowledgeChanged ||
        dataChanged ||
        curriculumChanged) {
      _syncGraph(resetPositions: filterChanged || curriculumChanged);
    } else if (settingsChanged && widget.settings.enablePhysics) {
      _wakeSimulation();
    }
  }

  void resimulate({bool randomize = false}) {
    final rng = math.Random();
    for (final node in _nodes) {
      if (randomize) {
        node.x += (rng.nextDouble() - 0.5) * 80.0;
        node.y += (rng.nextDouble() - 0.5) * 80.0;
      }
      node.vx = (rng.nextDouble() - 0.5) * 16.0;
      node.vy = (rng.nextDouble() - 0.5) * 16.0;
    }
    _wakeSimulation();
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _wakeSimulation() {
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  /// Chụp lại vị trí các node môn học cho ô đồ thị thu nhỏ mượn.
  ///
  /// Gọi khi mô phỏng đã cân bằng và sau mỗi lần kéo node xong — hai thời điểm
  /// mà hình trên màn hình đúng là hình người dùng đang nhìn. Node tri thức bị
  /// bỏ qua vì ô thu nhỏ chỉ vẽ môn học.
  void _saveLayout() {
    final positions = <int, Offset>{
      for (final n in _nodes)
        if (n.subject?.id != null) n.subject!.id!: Offset(n.x, n.y),
    };
    GraphLayoutCache.instance.save(widget.curriculumCode, positions);
  }

  void _syncGraph({bool resetPositions = false}) {
    final visible = widget.semesterFilter == null
        ? widget.data.subjects
        : widget.data.subjects
              .where((s) => s.semester == widget.semesterFilter)
              .toList();

    if (visible.isEmpty) {
      _nodes.clear();
      _edges.clear();
      if (_ticker.isActive) _ticker.stop();
      setState(() {});
      return;
    }

    final oldMap = {for (final n in _nodes) n.id: n};
    final newNodes = <_NodeSim>[];
    final nodeById = <int, _NodeSim>{};
    final nodeBySubjectCode = <String, _NodeSim>{};

    // Bố cục lực đẩy (Force / Cụm Obsidian)
    final count = visible.length;
    for (int i = 0; i < count; i++) {
      final s = visible[i];
      final id = 's_${s.id}';
      final existing = oldMap[id];
      if (existing != null && !resetPositions) {
        newNodes.add(existing);
        nodeById[s.id!] = existing;
        nodeBySubjectCode[s.code.toUpperCase()] = existing;
      } else {
        final angle = i * (2 * math.pi / count);
        final radius = 180.0 + (i % 3) * 45.0;
        final node = _NodeSim(
          subject: s,
          x: centerX + radius * math.cos(angle),
          y: centerY + radius * math.sin(angle),
        );
        newNodes.add(node);
        nodeById[s.id!] = node;
        nodeBySubjectCode[s.code.toUpperCase()] = node;
      }
    }

    final newEdges = <_EdgeSim>[];
    // Cập nhật các cạnh liên kết giữa các môn
    for (final e in widget.data.edges) {
      if (!widget.showRelated && !e.isHardPrerequisite) continue;
      final from = nodeById[e.prerequisiteId];
      final to = nodeById[e.subjectId];
      if (from != null && to != null) {
        newEdges.add(
          _EdgeSim(from: from, to: to, isHard: e.isHardPrerequisite),
        );
      }
    }

    // Nếu người dùng bật xem tri thức syllabus
    if (widget.showKnowledge && AppState.instance.knowledge != null) {
      final kIndex = AppState.instance.knowledge!;
      final candidateConcepts = <String, Set<String>>{};
      for (final s in visible) {
        final code = s.code.toUpperCase();
        final sk = kIndex.subjects[code];
        if (sk != null) {
          for (final sc in sk.concepts.take(4)) {
            candidateConcepts.putIfAbsent(sc.conceptId, () => {}).add(code);
          }
        }
      }

      final sortedIds = candidateConcepts.keys.toList()
        ..sort(
          (a, b) => (candidateConcepts[b]?.length ?? 0).compareTo(
            candidateConcepts[a]?.length ?? 0,
          ),
        );

      final conceptNodes = <_NodeSim>[];
      final nodeByConceptId = <String, _NodeSim>{};

      for (final cid in sortedIds.take(35)) {
        final kc = kIndex.concepts[cid];
        if (kc == null) continue;
        final id = 'c_$cid';
        final existing = oldMap[id];
        if (existing != null && !resetPositions) {
          conceptNodes.add(existing);
          nodeByConceptId[cid] = existing;
        } else {
          double avgX = 0, avgY = 0;
          int cnt = 0;
          for (final sc in candidateConcepts[cid] ?? <String>{}) {
            final sn = nodeBySubjectCode[sc];
            if (sn != null) {
              avgX += sn.x;
              avgY += sn.y;
              cnt++;
            }
          }
          final rng = math.Random(cid.hashCode);
          final offset = 65.0;
          final posX = cnt > 0
              ? (avgX / cnt) + (rng.nextDouble() - 0.5) * offset
              : centerX;
          final posY = cnt > 0
              ? (avgY / cnt) + (rng.nextDouble() - 0.5) * offset
              : centerY;

          final node = _NodeSim(concept: kc, x: posX, y: posY);
          conceptNodes.add(node);
          nodeByConceptId[cid] = node;
        }
      }

      newNodes.addAll(conceptNodes);

      for (final entry in candidateConcepts.entries) {
        final cNode = nodeByConceptId[entry.key];
        if (cNode == null) continue;
        for (final sc in entry.value) {
          final sNode = nodeBySubjectCode[sc];
          if (sNode != null) {
            newEdges.add(
              _EdgeSim(
                from: sNode,
                to: cNode,
                isHard: false,
                isConceptLink: true,
              ),
            );
          }
        }
      }
    }

    _nodes
      ..clear()
      ..addAll(newNodes);

    _edges
      ..clear()
      ..addAll(newEdges);

    _wakeSimulation();
    setState(() {});
  }

  void _onTick(Duration elapsed) {
    if (_nodes.isEmpty) return;
    if (!widget.settings.enablePhysics) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }

    double maxVelocity = 0.0;
    final repulsionThreshold = math.max(
      380.0,
      widget.settings.linkDistance * 2.5,
    );
    final repulsionStrength = widget.settings.repulsionForce;

    // 1. Lực đẩy giữa các node (Repulsion Coulomb)
    for (int i = 0; i < _nodes.length; i++) {
      final n1 = _nodes[i];
      for (int j = i + 1; j < _nodes.length; j++) {
        final n2 = _nodes[j];
        final dx = n2.x - n1.x;
        final dy = n2.y - n1.y;
        final distSq = dx * dx + dy * dy + 400.0;
        final dist = math.sqrt(distSq);
        if (dist < repulsionThreshold) {
          final force = repulsionStrength / distSq;
          final fx = (dx / dist) * force;
          final fy = (dy / dist) * force;
          if (!n1.isDragging) {
            n1.vx -= fx;
            n1.vy -= fy;
          }
          if (!n2.isDragging) {
            n2.vx += fx;
            n2.vy += fy;
          }
        }
      }
    }

    // 2. Lực lò xo đàn hồi dọc theo liên kết (Spring Hooke)
    final desiredDist = widget.settings.linkDistance;
    for (final e in _edges) {
      final dx = e.to.x - e.from.x;
      final dy = e.to.y - e.from.y;
      final dist = math.sqrt(dx * dx + dy * dy) + 0.1;
      final targetDist = e.isConceptLink ? desiredDist * 0.65 : desiredDist;
      final delta = dist - targetDist;
      final force = delta * (e.isConceptLink ? 0.06 : 0.045);
      final fx = (dx / dist) * force;
      final fy = (dy / dist) * force;

      if (!e.from.isDragging) {
        e.from.vx += fx;
        e.from.vy += fy;
      }
      if (!e.to.isDragging) {
        e.to.vx -= fx;
        e.to.vy -= fy;
      }
    }

    // 3. Trọng lực hướng tâm & Giảm chấn (Damping Friction)
    final grav = widget.settings.centerGravity;
    for (final n in _nodes) {
      if (!n.isDragging) {
        n.vx += (centerX - n.x) * grav;
        n.vy += (centerY - n.y) * grav;

        n.vx *= 0.86;
        n.vy *= 0.86;

        n.x += n.vx;
        n.y += n.vy;

        final v = n.vx.abs() + n.vy.abs();
        if (v > maxVelocity) maxVelocity = v;
      }
    }

    setState(() {});

    // Tự động ngủ khi đồ thị cân bằng để tiết kiệm 100% CPU
    if (!_isDraggingAny && maxVelocity < 0.06) {
      _ticker.stop();
      _saveLayout();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_nodes.isEmpty) {
      return const EmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: 'Không có môn nào ở kỳ này',
        message: 'Đổi bộ lọc kỳ học ở thanh trên để xem các môn khác.',
      );
    }

    final isDark = AppColors.isDark;
    final selectedId = AppState.instance.selectedSubjectId;

    // Tính toán tập hợp highlight khi đang ở chế độ tri thức
    final kIndex = AppState.instance.knowledge;
    final bool hasHighlight =
        widget.showKnowledge &&
        kIndex != null &&
        (widget.selectedConceptId != null ||
            widget.selectedSubjectCode != null);

    final Set<String> highlightedCodes = {};
    final Set<String> highlightedConceptIds = {};

    if (hasHighlight) {
      if (widget.selectedConceptId != null) {
        final cid = widget.selectedConceptId!;
        highlightedConceptIds.add(cid);
        final kc = kIndex.concepts[cid];
        if (kc != null) {
          highlightedCodes.addAll(
            kc.bySubject.keys.map((s) => s.toUpperCase()),
          );
        }
      } else if (widget.selectedSubjectCode != null) {
        final code = widget.selectedSubjectCode!.toUpperCase();
        highlightedCodes.add(code);
        final sk = kIndex.subjects[code];
        if (sk != null) {
          highlightedConceptIds.addAll(sk.concepts.map((c) => c.conceptId));
        }
      }
    }

    return Container(
      color: AppColors.background,
      child: InteractiveViewer(
        transformationController: widget.viewer,
        constrained: false,
        panEnabled: !_isDraggingAny,
        boundaryMargin: const EdgeInsets.all(600),
        minScale: 0.15,
        maxScale: 3.0,
        child: SizedBox(
          width: canvasSize,
          height: canvasSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Bấm vào nền trống để bỏ chọn
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    widget.onClearSelection?.call();
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),

              // 1. Vẽ các đường mũi tên liên kết giữa các node
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GraphEdgesPainter(
                      edges: _edges,
                      isDark: isDark,
                      nodeWidth: nodeWidth,
                      nodeHeight: nodeHeight,
                      edgeWidth: widget.settings.edgeWidth,
                      showArrows: widget.settings.showArrows,
                      hasHighlight: hasHighlight,
                      highlightedCodes: highlightedCodes,
                      highlightedConceptIds: highlightedConceptIds,
                      selectedConceptId: widget.selectedConceptId,
                      selectedSubjectCode: widget.selectedSubjectCode,
                    ),
                  ),
                ),
              ),

              // 2. Các thẻ node (môn học hoặc khái niệm tri thức)
              for (final node in _nodes)
                if (node.isConcept)
                  Positioned(
                    left: node.x - 55.0 * widget.settings.nodeScale,
                    top: node.y - 13.0 * widget.settings.nodeScale,
                    child: _DraggableConceptNodeItem(
                      node: node,
                      settings: widget.settings,
                      isSelected: node.concept?.id == widget.selectedConceptId,
                      isHighlighted: highlightedConceptIds.contains(
                        node.concept?.id,
                      ),
                      isDimmed:
                          hasHighlight &&
                          !(node.concept?.id == widget.selectedConceptId ||
                              highlightedConceptIds.contains(node.concept?.id)),
                      viewer: widget.viewer,
                      onDragStart: () {
                        setState(() {
                          node.isDragging = true;
                          _isDraggingAny = true;
                        });
                        _wakeSimulation();
                      },
                      onDragUpdate: (delta) {
                        final scale = widget.viewer.value.getMaxScaleOnAxis();
                        node.x += delta.dx / scale;
                        node.y += delta.dy / scale;
                        node.vx = delta.dx / scale;
                        node.vy = delta.dy / scale;
                        _wakeSimulation();
                      },
                      onDragEnd: (wasTap) {
                        setState(() {
                          node.isDragging = false;
                          _isDraggingAny = false;
                        });
                        if (wasTap && node.concept != null) {
                          widget.onSelectConcept?.call(node.concept!.id);
                        }
                        _saveLayout();
                        _wakeSimulation();
                      },
                    ),
                  )
                else
                  Positioned(
                    left: node.x - (nodeWidth / 2),
                    top: node.y - (nodeHeight / 2),
                    child: _DraggableNodeItem(
                      node: node,
                      data: widget.data,
                      settings: widget.settings,
                      isSelected: selectedId == node.subject?.id,
                      isConceptRelated: highlightedCodes.contains(
                        node.subject?.code.toUpperCase(),
                      ),
                      isDimmed:
                          hasHighlight &&
                          !highlightedCodes.contains(
                            node.subject?.code.toUpperCase(),
                          ),
                      viewer: widget.viewer,
                      onDragStart: () {
                        setState(() {
                          node.isDragging = true;
                          _isDraggingAny = true;
                        });
                        _wakeSimulation();
                      },
                      onDragUpdate: (delta) {
                        final scale = widget.viewer.value.getMaxScaleOnAxis();
                        node.x += delta.dx / scale;
                        node.y += delta.dy / scale;
                        node.vx = delta.dx / scale;
                        node.vy = delta.dy / scale;
                        _wakeSimulation();
                      },
                      onDragEnd: (wasTap) {
                        setState(() {
                          node.isDragging = false;
                          _isDraggingAny = false;
                        });
                        final sid = node.subject?.id;
                        if (wasTap && sid != null) {
                          widget.onSelectSubject?.call(sid);
                        }
                        _saveLayout();
                        _wakeSimulation();
                      },
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// THẺ TRI THỨC (CONCEPT PILL) TRÊN GRAPH
// ============================================================================

class _DraggableConceptNodeItem extends StatefulWidget {
  final _NodeSim node;
  final GraphSettings settings;
  final bool isSelected;
  final bool isHighlighted;
  final bool isDimmed;
  final TransformationController viewer;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final ValueChanged<bool> onDragEnd;

  const _DraggableConceptNodeItem({
    required this.node,
    required this.settings,
    this.isSelected = false,
    this.isHighlighted = false,
    this.isDimmed = false,
    required this.viewer,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  State<_DraggableConceptNodeItem> createState() =>
      _DraggableConceptNodeItemState();
}

class _DraggableConceptNodeItemState extends State<_DraggableConceptNodeItem> {
  Offset _startPos = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final c = widget.node.concept!;
    final scale = widget.settings.nodeScale;
    final isDark = AppColors.isDark;

    final baseColor = switch (c.category) {
      KnowledgeCategory.programming => const Color(0xFF3B82F6),
      KnowledgeCategory.dsa => const Color(0xFF8B5CF6),
      KnowledgeCategory.database => const Color(0xFF10B981),
      KnowledgeCategory.webMobile => const Color(0xFFEC4899),
      KnowledgeCategory.systems => const Color(0xFFF59E0B),
      KnowledgeCategory.softwareEngineering => const Color(0xFF6366F1),
      KnowledgeCategory.math => const Color(0xFF14B8A6),
      _ => const Color(0xFF64748B),
    };

    final isSelected = widget.isSelected;
    final isHighlighted = widget.isHighlighted;

    return Opacity(
      opacity: widget.isDimmed ? 0.18 : 1.0,
      child: Listener(
        onPointerDown: (e) {
          _startPos = e.position;
          widget.onDragStart();
        },
        onPointerMove: (e) {
          widget.onDragUpdate(e.delta);
        },
        onPointerUp: (e) {
          final dist = (e.position - _startPos).distance;
          final wasTap = dist < 5.0;
          widget.onDragEnd(wasTap);
        },
        child: MouseRegion(
          cursor: widget.node.isDragging
              ? SystemMouseCursors.grabbing
              : SystemMouseCursors.grab,
          child: Tooltip(
            message:
                'Khái niệm: ${c.label}\n'
                'Nhóm: ${c.category}\n'
                'Xuất hiện trong ${c.subjectCount} môn: ${c.bySubject.keys.join(', ')}',
            waitDuration: const Duration(milliseconds: 300),
            child: Container(
              height: 26.0 * scale,
              padding: EdgeInsets.symmetric(
                horizontal: 8.0 * scale,
                vertical: 2.0 * scale,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? baseColor
                    : (isDark
                          ? (isHighlighted
                                ? baseColor.withValues(alpha: 0.35)
                                : baseColor.withValues(alpha: 0.20))
                          : (isHighlighted
                                ? baseColor.withValues(alpha: 0.25)
                                : baseColor.withValues(alpha: 0.12))),
                borderRadius: BorderRadius.circular(13 * scale),
                border: Border.all(
                  color: isSelected
                      ? Colors.white
                      : (widget.node.isDragging
                            ? AppColors.primary
                            : (isHighlighted
                                  ? baseColor
                                  : baseColor.withValues(alpha: 0.65))),
                  width: isSelected
                      ? 2.0
                      : (widget.node.isDragging || isHighlighted ? 1.8 : 1.0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? baseColor.withValues(alpha: 0.6)
                        : (isHighlighted
                              ? baseColor.withValues(alpha: 0.35)
                              : baseColor.withValues(alpha: 0.12)),
                    blurRadius: isSelected ? 12 : (isHighlighted ? 8 : 4),
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 13.0 * scale,
                    color: isSelected ? Colors.white : baseColor,
                  ),
                  SizedBox(width: 4.0 * scale),
                  Text(
                    c.label,
                    style: TextStyle(
                      fontSize: (10.5 * scale).clamp(8.5, 14.0),
                      fontWeight: isSelected || isHighlighted
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (isDark
                                ? const Color(0xFFE2E8F0)
                                : const Color(0xFF1E293B)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// THẺ MÔN HỌC COMPACT (BỎ DESCRIPTION) & KÉO THẢ
// ============================================================================

class _DraggableNodeItem extends StatefulWidget {
  final _NodeSim node;
  final GraphData data;
  final GraphSettings settings;
  final bool isSelected;
  final bool isConceptRelated;
  final bool isDimmed;
  final TransformationController viewer;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final ValueChanged<bool> onDragEnd;

  const _DraggableNodeItem({
    required this.node,
    required this.data,
    required this.settings,
    required this.isSelected,
    this.isConceptRelated = false,
    this.isDimmed = false,
    required this.viewer,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  State<_DraggableNodeItem> createState() => _DraggableNodeItemState();
}

class _DraggableNodeItemState extends State<_DraggableNodeItem> {
  Offset _startPos = Offset.zero;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Widget build(BuildContext context) {
    final s = widget.node.subject!;
    final inDeg = widget.data.inDegree(s.id!);
    final outDeg = widget.data.outDegree(s.id!);
    final totalDeg = inDeg + outDeg;

    // Điểm của môn này trong bảng điểm cá nhân, null nghĩa là chưa học.
    final gradeEntry = widget.settings.colorMode == 'grade'
        ? AppState.instance.gradeOf(s.code)
        : null;

    // Dòng điểm trong tooltip, rỗng khi môn chưa có trong bảng điểm.
    final gradeLine = gradeEntry == null
        ? ''
        : 'Điểm: ${gradeEntry.displayGrade} — ${gradeEntry.statusLabel}\n';

    final Color color;
    if (widget.settings.colorMode == 'grade') {
      color = AppColors.gradeColor(
        gradeEntry?.grade,
        gradeEntry?.status ?? SubjectStatus.notStarted,
      );
    } else if (widget.settings.colorMode == 'degree') {
      if (totalDeg >= 6) {
        color = const Color(0xFFEF4444);
      } else if (totalDeg >= 4) {
        color = const Color(0xFFF97316);
      } else if (totalDeg >= 2) {
        color = const Color(0xFF8B5CF6);
      } else if (totalDeg >= 1) {
        color = const Color(0xFF3B82F6);
      } else {
        color = const Color(0xFF64748B);
      }
    } else {
      color = AppColors.forSemester(s.semester);
    }

    final scale = widget.settings.nodeScale;
    final width = 110.0 * scale;
    final height = 32.0 * scale;
    final fontSize = (11.5 * scale).clamp(9.0, 16.0);
    final tagFontSize = (10.0 * scale).clamp(8.0, 14.0);
    final dotSize = (7.5 * scale).clamp(5.0, 12.0);

    return Opacity(
      opacity: widget.isDimmed ? 0.18 : 1.0,
      child: Listener(
        onPointerDown: (e) {
          _startPos = e.position;
          widget.onDragStart();
        },
        onPointerMove: (e) {
          widget.onDragUpdate(e.delta);
        },
        onPointerUp: (e) {
          final dist = (e.position - _startPos).distance;
          final wasTap = dist < 5.0;
          widget.onDragEnd(wasTap);
          if (wasTap) {
            final now = DateTime.now();
            if (now.difference(_lastTapTime).inMilliseconds < 350) {
              // Nhấp đúp: mở ngay tab ghi chú Obsidian ở thanh trên
              AppState.instance.openNoteTab(s);
            }
            _lastTapTime = now;
          }
        },
        child: MouseRegion(
          cursor: widget.node.isDragging
              ? SystemMouseCursors.grabbing
              : SystemMouseCursors.grab,
          child: Tooltip(
            message:
                '${s.code} — ${s.name}\n'
                'Học kỳ ${s.semester} • ${s.credits} tín chỉ\n'
                '$inDeg môn tiên quyết • mở ra $outDeg môn\n'
                '$gradeLine'
                '(Nhấp để chọn • Nhấp đúp mở ghi chú .md)',
            waitDuration: const Duration(milliseconds: 350),
            child: Container(
              width: width,
              height: height,
              padding: EdgeInsets.symmetric(
                horizontal: (8 * scale).clamp(4.0, 12.0),
                vertical: (4 * scale).clamp(2.0, 8.0),
              ),
              decoration: BoxDecoration(
                color: widget.isSelected ? color : AppColors.surface,
                borderRadius: BorderRadius.circular(8 * scale.clamp(0.8, 1.4)),
                border: Border.all(
                  color: widget.isSelected
                      ? color
                      : (widget.isConceptRelated
                            ? AppColors.primary
                            : (widget.node.isDragging
                                  ? AppColors.primary
                                  : AppColors.border)),
                  width:
                      widget.isSelected ||
                          widget.node.isDragging ||
                          widget.isConceptRelated
                      ? 2
                      : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.isSelected
                        ? Colors.black.withValues(alpha: 0.22)
                        : (widget.isConceptRelated
                              ? AppColors.primary.withValues(alpha: 0.35)
                              : (widget.node.isDragging
                                    ? Colors.black.withValues(alpha: 0.28)
                                    : Colors.black.withValues(alpha: 0.07))),
                    blurRadius: widget.isConceptRelated
                        ? 10
                        : (widget.node.isDragging
                              ? 14
                              : (widget.isSelected ? 8 : 4)),
                    offset: Offset(0, widget.node.isDragging ? 4 : 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: dotSize,
                    height: dotSize,
                    decoration: BoxDecoration(
                      color: widget.isSelected ? Colors.white : color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: (6 * scale).clamp(3.0, 10.0)),
                  Expanded(
                    child: Text(
                      s.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700,
                        color: widget.isSelected
                            ? Colors.white
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  // Chỉ dùng màu thì người mù màu không đọc được thang điểm,
                  // nên ở chế độ này con số luôn được in thẳng lên thẻ.
                  if (gradeEntry?.hasGrade == true) ...[
                    Text(
                      gradeEntry!.displayGrade,
                      style: TextStyle(
                        fontSize: tagFontSize,
                        fontWeight: FontWeight.w800,
                        color: widget.isSelected ? Colors.white : color,
                      ),
                    ),
                    SizedBox(width: 4 * scale),
                  ],
                  if (widget.settings.showCredits) ...[
                    Text(
                      '${s.credits}TC',
                      style: TextStyle(
                        fontSize: (tagFontSize - 0.5).clamp(7.5, 12.0),
                        fontWeight: FontWeight.w600,
                        color: widget.isSelected
                            ? Colors.white70
                            : AppColors.primary,
                      ),
                    ),
                    if (widget.settings.showSemesterBadge)
                      SizedBox(width: 4 * scale),
                  ],
                  if (widget.settings.showSemesterBadge)
                    Text(
                      'K${s.semester}',
                      style: TextStyle(
                        fontSize: tagFontSize,
                        fontWeight: FontWeight.w600,
                        color: widget.isSelected
                            ? Colors.white70
                            : AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// VẼ ĐƯỜNG MŨI TÊN LIÊN KẾT GIỮA CÁC THẺ
// ============================================================================

class _GraphEdgesPainter extends CustomPainter {
  final List<_EdgeSim> edges;
  final bool isDark;
  final double nodeWidth;
  final double nodeHeight;
  final double edgeWidth;
  final bool showArrows;
  final bool hasHighlight;
  final Set<String> highlightedCodes;
  final Set<String> highlightedConceptIds;
  final String? selectedConceptId;
  final String? selectedSubjectCode;

  _GraphEdgesPainter({
    required this.edges,
    required this.isDark,
    required this.nodeWidth,
    required this.nodeHeight,
    required this.edgeWidth,
    required this.showArrows,
    this.hasHighlight = false,
    this.highlightedCodes = const {},
    this.highlightedConceptIds = const {},
    this.selectedConceptId,
    this.selectedSubjectCode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nodeW = nodeWidth;
    final nodeH = nodeHeight;

    // Nếu có highlight: vẽ pass 0 (các cạnh mờ/không chọn) trước, sau đó pass 1 (các cạnh highlight) đè lên trên.
    final passes = hasHighlight ? [false, true] : [false];

    for (final isHighPass in passes) {
      for (final e in edges) {
        final fromX = e.from.x;
        final fromY = e.from.y;
        final toX = e.to.x;
        final toY = e.to.y;

        final dx = toX - fromX;
        final dy = toY - fromY;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 15.0) continue;

        // Xác định xem cạnh e có nằm trong tập highlight không
        bool isEdgeHighlighted = false;
        if (hasHighlight) {
          if (e.isConceptLink) {
            final cId = e.to.isConcept ? e.to.concept?.id : e.from.concept?.id;
            final sCode = e.from.subject != null
                ? e.from.subject?.code.toUpperCase()
                : e.to.subject?.code.toUpperCase();
            if (selectedConceptId != null) {
              isEdgeHighlighted =
                  (cId == selectedConceptId &&
                  sCode != null &&
                  highlightedCodes.contains(sCode));
            } else if (selectedSubjectCode != null) {
              isEdgeHighlighted =
                  (sCode == selectedSubjectCode!.toUpperCase() &&
                  cId != null &&
                  highlightedConceptIds.contains(cId));
            }
          } else {
            final fromCode = e.from.subject?.code.toUpperCase();
            final toCode = e.to.subject?.code.toUpperCase();
            if (fromCode != null &&
                toCode != null &&
                highlightedCodes.contains(fromCode) &&
                highlightedCodes.contains(toCode)) {
              isEdgeHighlighted = true;
            }
          }
        }

        if (hasHighlight && isEdgeHighlighted != isHighPass) {
          continue;
        }

        final ux = dx / dist;
        final uy = dy / dist;

        final fromW = e.from.isConcept ? 100.0 * (nodeW / 110.0) : nodeW;
        final fromH = e.from.isConcept ? 26.0 * (nodeH / 32.0) : nodeH;
        final toW = e.to.isConcept ? 100.0 * (nodeW / 110.0) : nodeW;
        final toH = e.to.isConcept ? 26.0 * (nodeH / 32.0) : nodeH;

        final borderFrom = _distToRectBorder(ux, uy, fromW, fromH);
        final startX = fromX + ux * (borderFrom + 2);
        final startY = fromY + uy * (borderFrom + 2);

        final arrowGap = (!e.isConceptLink && showArrows) ? 5.0 : 2.0;
        final borderTo = _distToRectBorder(ux, uy, toW, toH);
        final endX = toX - ux * (borderTo + arrowGap);
        final endY = toY - uy * (borderTo + arrowGap);

        if ((endX - startX) * ux + (endY - startY) * uy <= 0) continue;

        if (e.isConceptLink) {
          final double stroke;
          final Color strokeColor;
          if (isEdgeHighlighted) {
            stroke = 2.0 * (edgeWidth / 1.5).clamp(0.8, 2.4);
            strokeColor = isDark
                ? const Color(0xFF818CF8)
                : const Color(0xFF4F46E5);
          } else if (hasHighlight) {
            stroke = 0.8;
            strokeColor =
                (isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1))
                    .withValues(alpha: 0.08);
          } else {
            stroke = 1.1 * (edgeWidth / 1.5).clamp(0.6, 1.8);
            strokeColor =
                (isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1))
                    .withValues(alpha: 0.45);
          }

          final paint = Paint()
            ..color = strokeColor
            ..strokeWidth = stroke
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
          continue;
        }

        final double stroke;
        final Color strokeColor;
        if (isEdgeHighlighted) {
          stroke = (e.isHard ? 2.4 : 1.8) * (edgeWidth / 1.5);
          strokeColor = e.isHard
              ? AppColors.edgePrerequisite
              : (isDark ? const Color(0xFFA5B4FC) : const Color(0xFF6366F1));
        } else if (hasHighlight) {
          stroke = 0.8;
          strokeColor =
              (e.isHard
                      ? AppColors.edgePrerequisite
                      : (isDark
                            ? const Color(0xFF5A5A6E)
                            : const Color(0xFFA6A2B8)))
                  .withValues(alpha: 0.10);
        } else {
          stroke = (e.isHard ? 1.8 : 1.2) * (edgeWidth / 1.5);
          strokeColor = e.isHard
              ? AppColors.edgePrerequisite
              : (isDark ? const Color(0xFF5A5A6E) : const Color(0xFFA6A2B8));
        }

        final paint = Paint()
          ..color = strokeColor
          ..strokeWidth = stroke
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);

        if (showArrows) {
          final arrowSize =
              (e.isHard ? 7.0 : 6.0) * (edgeWidth / 1.5).clamp(0.7, 2.0);
          _drawArrowHead(canvas, endX, endY, ux, uy, paint.color, arrowSize);
        }
      }
    }
  }

  double _distToRectBorder(double ux, double uy, double w, double h) {
    final absUx = ux.abs();
    final absUy = uy.abs();
    if (absUx < 0.0001) return h / 2;
    if (absUy < 0.0001) return w / 2;
    final distX = (w / 2) / absUx;
    final distY = (h / 2) / absUy;
    return math.min(distX, distY);
  }

  void _drawArrowHead(
    Canvas canvas,
    double x,
    double y,
    double ux,
    double uy,
    Color color,
    double arrowSize,
  ) {
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final nx = -uy;
    final ny = ux;

    final path = Path();
    path.moveTo(x + ux * 2, y + uy * 2);
    path.lineTo(
      x - ux * arrowSize + nx * (arrowSize * 0.55),
      y - uy * arrowSize + ny * (arrowSize * 0.55),
    );
    path.lineTo(x - ux * (arrowSize * 0.65), y - uy * (arrowSize * 0.65));
    path.lineTo(
      x - ux * arrowSize - nx * (arrowSize * 0.55),
      y - uy * arrowSize - ny * (arrowSize * 0.55),
    );
    path.close();

    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _GraphEdgesPainter oldDelegate) => true;
}

class _SemesterFilter extends StatelessWidget {
  final List<int> semesters;
  final int? value;
  final ValueChanged<int?> onChanged;

  const _SemesterFilter({
    required this.semesters,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final validValue = (value == null || semesters.contains(value))
        ? value
        : null;
    return Container(
      height: 32,
      width: 98,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: validValue,
          isDense: true,
          isExpanded: true,
          icon: Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: AppColors.textSecondary,
          ),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
          dropdownColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          items: [
            DropdownMenuItem<int?>(
              value: null,
              child: Text(
                'Tất cả kỳ',
                style: TextStyle(fontSize: 11.5, color: AppColors.textPrimary),
              ),
            ),
            for (final s in semesters)
              DropdownMenuItem<int?>(
                value: s,
                child: Text(
                  s == 0 ? 'Kỳ 0' : 'Kỳ $s',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _CurriculumFilter extends StatelessWidget {
  final List<CurriculumGroup> groups;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _CurriculumFilter({
    required this.groups,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final validValue = (value == null || groups.any((g) => g.code == value))
        ? value
        : null;
    return Container(
      height: 32,
      constraints: const BoxConstraints(minWidth: 100, maxWidth: 145),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: validValue != null ? AppColors.primary : AppColors.border,
          width: validValue != null ? 1.5 : 1.0,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: validValue,
          isDense: true,
          isExpanded: true,
          icon: Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: AppColors.textSecondary,
          ),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: validValue != null
                ? AppColors.primary
                : AppColors.textPrimary,
          ),
          dropdownColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                'Tất cả khung',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            for (final g in groups)
              DropdownMenuItem<String?>(
                value: g.code,
                child: Text(
                  g.isUnassigned ? 'Ngoài khung' : g.code,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Chú giải thang màu theo điểm, hiện ở góc canvas khi đang tô màu theo điểm.
///
/// Mỗi mức có cả ô màu lẫn khoảng điểm bằng chữ, để đọc được mà không cần
/// phân biệt được màu.
class _GradeLegend extends StatelessWidget {
  const _GradeLegend();

  static const List<(String, double?, SubjectStatus)> _levels = [
    ('≥ 9.0 Xuất sắc', 9.5, SubjectStatus.passed),
    ('8.0 – 8.9 Giỏi', 8.5, SubjectStatus.passed),
    ('7.0 – 7.9 Khá', 7.5, SubjectStatus.passed),
    ('< 7.0 Cần cải thiện', 6.0, SubjectStatus.passed),
    ('Chưa qua', null, SubjectStatus.notPassed),
    ('Đang học', null, SubjectStatus.studying),
    ('Chưa học', null, SubjectStatus.notStarted),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Màu theo điểm',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          for (final (label, grade, status) in _levels)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: AppColors.gradeColor(grade, status),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final bool isDark;
  const _Legend({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          _LegendLine(
            color: AppColors.edgePrerequisite,
            label: 'Tiên quyết bắt buộc',
            isDark: isDark,
          ),
          const SizedBox(width: 20),
          _LegendLine(
            color: AppColors.edgeRelated,
            label: 'Liên quan / tham khảo',
            isDark: isDark,
          ),
          const Spacer(),
          Text(
            'Cuộn để zoom · kéo để di chuyển · bấm node để xem chi tiết',
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? const Color(0xFF8A8A93) : const Color(0xFF6B6B80),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendLine extends StatelessWidget {
  final Color color;
  final String label;
  final bool isDark;

  const _LegendLine({
    required this.color,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 22, height: 2.5, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: isDark ? const Color(0xFFDCDDDE) : const Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }
}

class _GraphFloatingControls extends StatelessWidget {
  final bool showSettings;
  final bool showKnowledge;
  final bool showRelated;
  final VoidCallback onToggleSettings;
  final VoidCallback onToggleKnowledge;
  final VoidCallback onToggleRelated;

  /// Ghim khung đang xem thành ô thu nhỏ trên thanh bên — đường không cần kéo
  /// thả, cho cả chuột bi lẫn người dùng bàn phím.
  final VoidCallback onPinMiniGraph;

  /// Khung đang xem đã là một trang của cửa sổ thu nhỏ — đổi nhãn mục menu
  /// để người dùng biết bấm vào chỉ chuyển trang chứ không thêm trang mới.
  final bool isMiniGraphPinned;
  final VoidCallback onResetZoom;
  final VoidCallback onRefresh;

  const _GraphFloatingControls({
    required this.showSettings,
    required this.showKnowledge,
    required this.showRelated,
    required this.onToggleSettings,
    required this.onToggleKnowledge,
    required this.onToggleRelated,
    required this.onPinMiniGraph,
    required this.isMiniGraphPinned,
    required this.onResetZoom,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF1E1E24) : Colors.white).withValues(
          alpha: 0.94,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            tooltip: 'Tùy chọn khác',
            icon: Icon(
              Icons.more_vert,
              size: 19,
              color: AppColors.textSecondary,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            splashRadius: 16,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            color: isDark ? const Color(0xFF25252E) : Colors.white,
            onSelected: (val) {
              if (val == 'reset_zoom') onResetZoom();
              if (val == 'refresh') onRefresh();
              if (val == 'toggle_related') onToggleRelated();
              if (val == 'pin_mini') onPinMiniGraph();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'reset_zoom',
                child: Row(
                  children: [
                    Icon(
                      Icons.center_focus_strong,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Về zoom mặc định',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(
                      Icons.refresh,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Tải lại đồ thị',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'pin_mini',
                child: Row(
                  children: [
                    Icon(
                      isMiniGraphPinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isMiniGraphPinned
                          ? 'Đã ghim · chuyển tới trang này'
                          : 'Ghim vào đồ thị thu nhỏ',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'toggle_related',
                child: Row(
                  children: [
                    Icon(
                      showRelated ? Icons.visibility : Icons.visibility_off,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      showRelated
                          ? 'Ẩn quan hệ tham khảo'
                          : 'Hiện quan hệ tham khảo',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _FloatingIconButton(
            icon: showSettings ? Icons.settings : Icons.settings_outlined,
            tooltip: 'Điều chỉnh đồ thị (vật lý, màu sắc, lực đẩy)',
            isActive: showSettings,
            onTap: onToggleSettings,
          ),
          const SizedBox(height: 4),
          _FloatingIconButton(
            icon: showKnowledge ? Icons.psychology : Icons.psychology_outlined,
            tooltip: 'Hiện/ẩn tri thức syllabus trên đồ thị',
            isActive: showKnowledge,
            onTap: onToggleKnowledge,
          ),
        ],
      ),
    );
  }
}

class _FloatingIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  const _FloatingIconButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              size: 19,
              color: isActive ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
