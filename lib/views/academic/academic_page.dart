import 'package:flutter/material.dart';

import '../../models/transcript_entry.dart';
import '../../services/academic_analytics_service.dart';
import '../../services/ai_service.dart';
import '../../services/settings_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';
import '../widgets/linked_answer_text.dart';
import 'transcript_import_dialog.dart';

/// Tab "Học lực": tổng hợp bảng điểm cá nhân và soi nó trên đồ thị tiên quyết.
///
/// Tách thành trang riêng thay vì nhồi vào `subjects_page.dart` (đã 700 dòng)
/// hay `app_shell.dart` (2.300 dòng) — và vì đây là một góc nhìn khác hẳn:
/// danh sách môn trả lời "chương trình có gì", còn trang này trả lời "mình
/// đang đứng ở đâu trong chương trình đó".
class AcademicPage extends StatefulWidget {
  /// Nhảy sang tab Đồ thị sau khi đã chọn sẵn node — dùng lại đúng cơ chế của
  /// nút "Xem trên đồ thị" ở tab Trợ lý AI.
  final VoidCallback? onOpenGraph;

  const AcademicPage({super.key, this.onOpenGraph});

  @override
  State<AcademicPage> createState() => _AcademicPageState();
}

/// Cách sắp xếp bảng điểm đầy đủ.
enum _SortBy { semester, grade, code }

class _AcademicPageState extends State<AcademicPage> {
  final TextEditingController _search = TextEditingController();
  _SortBy _sortBy = _SortBy.semester;
  bool _descending = true;

  /// Câu trả lời đang stream về từ AI. Rỗng nghĩa là chưa hỏi lần nào.
  String _aiAnswer = '';
  bool _aiRunning = false;
  String? _aiError;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        return Column(
          children: [
            PageHeader(
              title: 'Học lực',
              subtitle: state.hasTranscript
                  ? 'GPA tích luỹ ${state.academicProfileOrEmpty.gpaLabel} · '
                        '${state.transcript.length} dòng điểm đã nhập'
                  : 'Chưa nhập bảng điểm',
              actions: [
                if (state.hasTranscript)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: const Text('Nhập lại'),
                    onPressed: _import,
                  ),
              ],
            ),
            Expanded(
              child: state.hasTranscript
                  ? _content(state.academicProfileOrEmpty)
                  : _emptyState(),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------------

  Widget _emptyState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: EmptyState(
          icon: Icons.insights_outlined,
          title: 'Chưa có bảng điểm nào',
          message:
              'Nhập bảng điểm để app tính GPA tích luỹ, vẽ xu hướng theo kỳ và '
              'chỉ ra những môn sắp học đang đứng trên một nền yếu.\n\n'
              '1. Vào FAP > Report > Transcript, bấm tải file '
              '"StudentTranscript_<MSSV>.xls" về máy.\n'
              '2. Bấm nút bên dưới rồi chọn đúng file vừa tải.',
          action: ElevatedButton.icon(
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Nhập bảng điểm từ FAP'),
            onPressed: _import,
          ),
        ),
      ),
    );
  }

  Widget _content(AcademicProfile profile) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _aiButtonRow(),
        const SizedBox(height: 16),
        _statRow(profile),
        const SizedBox(height: 16),
        if (_aiAnswer.isNotEmpty || _aiRunning || _aiError != null) ...[
          _aiPanel(),
          const SizedBox(height: 16),
        ],
        _SectionCard(
          icon: Icons.show_chart,
          title: 'GPA theo từng kỳ',
          subtitle: profile.bySemester.length < 2
              ? 'Cần ít nhất hai kỳ có điểm mới vẽ được đường xu hướng.'
              : 'Đường ngang mờ là GPA tích luỹ ${profile.gpaLabel} — '
                    'kỳ nằm trên đường đó đã kéo GPA đi lên. '
                    'Xu hướng 3 kỳ gần nhất: ${profile.trend.label}.',
          child: SizedBox(
            height: 210,
            child: profile.bySemester.isEmpty
                ? _noData('Chưa có kỳ nào đủ điều kiện tính GPA.')
                : CustomPaint(
                    painter: _SemesterChartPainter(
                      points: profile.bySemester,
                      averageGpa: profile.gpa,
                      lineColor: AppColors.primary,
                      gridColor: AppColors.border,
                      textColor: AppColors.textSecondary,
                      surfaceColor: AppColors.surface,
                    ),
                    child: const SizedBox.expand(),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          icon: Icons.donut_small_outlined,
          title: 'Nhóm năng lực',
          subtitle:
              'Phân loại theo tiền tố mã môn. Nhóm dưới '
              '${AcademicAnalyticsService.minSubjectsForConclusion} môn có điểm '
              'không đủ dữ liệu để kết luận mạnh hay yếu.',
          child: profile.byDomain.isEmpty
              ? _noData('Chưa có môn nào có điểm.')
              : Column(
                  children: [
                    for (final d in profile.byDomain)
                      _DomainBar(domain: d, overallGpa: profile.gpa),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          icon: Icons.warning_amber_rounded,
          title: 'Cảnh báo rủi ro',
          subtitle:
              'Ghép bảng điểm với đồ thị tiên quyết: môn nền điểm thấp mà mở '
              'ra nhiều môn phía sau được xếp lên trước. Bấm một dòng để xem '
              'môn đó trên đồ thị.',
          child: profile.risks.isEmpty
              ? _noData(
                  'Không có môn nào sắp học đứng trên một nền yếu. '
                  'Nhập thêm khung chương trình từ FAP nếu đồ thị còn trống.',
                )
              : Column(
                  children: [
                    for (final r in profile.risks)
                      _RiskTile(risk: r, onOpen: () => _openOnGraph(r)),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _transcriptTable(),
      ],
    );
  }

  Widget _noData(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Text(
      message,
      style: TextStyle(fontSize: 12.5, color: AppColors.textHint),
    ),
  );

  Widget _statRow(AcademicProfile profile) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'GPA tích luỹ',
            value: profile.gpaLabel,
            hint: '${profile.gpaSubjectCount} môn được tính',
            color: AppColors.primary,
            big: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Tín chỉ tích luỹ',
            value: '${profile.totalCredits}',
            hint: 'đã vào GPA',
            color: AppColors.info,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Môn đã qua',
            value: '${profile.passedCount}',
            hint: 'kể cả môn điều kiện',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Đang học',
            value: '${profile.studyingCount}',
            hint: '${profile.notStartedCount} môn chưa bắt đầu',
            color: AppColors.warning,
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // BẢNG ĐIỂM ĐẦY ĐỦ
  // ------------------------------------------------------------------

  Widget _transcriptTable() {
    final rows = _visibleRows();
    return _SectionCard(
      icon: Icons.table_chart_outlined,
      title: 'Bảng điểm đầy đủ',
      subtitle:
          'Bỏ tích "Tính vào GPA" ở một dòng nếu quy chế khoá của bạn khác với '
          'cờ mà FAP đánh — GPA phía trên tính lại ngay.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Tìm theo mã môn, tên môn, kỳ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const Spacer(),
              Text(
                '${rows.length}/${AppState.instance.transcript.length} dòng',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _TranscriptHeaderRow(
            sortBy: _sortBy,
            descending: _descending,
            onSort: (by) => setState(() {
              if (_sortBy == by) {
                _descending = !_descending;
              } else {
                _sortBy = by;
                _descending = true;
              }
            }),
          ),
          const Divider(height: 1),
          if (rows.isEmpty)
            _noData('Không có dòng nào khớp từ khoá.')
          else
            for (final e in rows)
              _TranscriptRow(
                entry: e,
                onToggleGpa: (value) => _toggleGpa(e, value),
              ),
        ],
      ),
    );
  }

  List<TranscriptEntry> _visibleRows() {
    final keyword = _search.text.trim().toLowerCase();
    final rows = AppState.instance.transcript.where((e) {
      if (keyword.isEmpty) return true;
      return e.subjectCode.toLowerCase().contains(keyword) ||
          e.subjectName.toLowerCase().contains(keyword) ||
          e.semesterLabel.toLowerCase().contains(keyword);
    }).toList();

    rows.sort((a, b) {
      final cmp = switch (_sortBy) {
        // Môn chưa có điểm luôn xếp cuối dù đang sắp tăng hay giảm: chúng
        // không có giá trị để so, đẩy lên đầu chỉ làm che mất phần đáng xem.
        _SortBy.grade => _compareNullableGrade(a, b),
        _SortBy.code => a.subjectCode.compareTo(b.subjectCode),
        _SortBy.semester => a.semesterOrder.compareTo(b.semesterOrder),
      };
      final ordered = _descending ? -cmp : cmp;
      return ordered != 0 ? ordered : a.subjectCode.compareTo(b.subjectCode);
    });
    return rows;
  }

  int _compareNullableGrade(TranscriptEntry a, TranscriptEntry b) {
    if (a.grade == null && b.grade == null) return 0;
    if (a.grade == null) return _descending ? -1 : 1;
    if (b.grade == null) return _descending ? 1 : -1;
    return a.grade!.compareTo(b.grade!);
  }

  Future<void> _toggleGpa(TranscriptEntry entry, bool value) async {
    final id = entry.id;
    if (id == null) return;
    try {
      await AppState.instance.setCountsTowardGpa(id, value);
    } catch (e) {
      if (mounted) Ui.error(context, e);
    }
  }

  // ------------------------------------------------------------------

  Future<void> _import() async {
    await TranscriptImportDialog.pickAndShow(context);
  }

  void _openOnGraph(RiskWarning risk) {
    final subject = AppState.instance.graph.byCode[risk.subjectCode];
    if (subject?.id != null) AppState.instance.select(subject!.id);
    widget.onOpenGraph?.call();
  }

  // ------------------------------------------------------------------
  // PHÂN TÍCH VỚI AI
  // ------------------------------------------------------------------

  /// Câu hỏi dựng sẵn. Bốn ý cố định để câu trả lời luôn có cùng khung, so
  /// sánh được giữa các lần hỏi ở hai kỳ khác nhau.
  static const String _analysisQuestion =
      'Dựa trên bảng điểm và đồ thị môn tiên quyết của tôi, hãy phân tích:\n'
      '1. Ba điểm mạnh rõ nhất, mỗi điểm kèm mã môn và điểm số làm bằng chứng.\n'
      '2. Ba điểm yếu cần ưu tiên xử lý, giải thích vì sao ưu tiên theo thứ tự đó.\n'
      '3. Những môn sắp học có rủi ro vì môn nền điểm thấp.\n'
      '4. Kế hoạch cải thiện cho kỳ tới, gắn với các môn cụ thể.';

  Widget _aiButtonRow() {
    return Row(
      children: [
        ElevatedButton.icon(
          icon: _aiRunning
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome, size: 18),
          label: Text(
            _aiRunning ? 'Đang phân tích...' : 'Phân tích với AI',
          ),
          onPressed: _aiRunning || !AppState.instance.hasTranscript
              ? null
              : _askAi,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Gửi toàn bộ số liệu học lực ở trang này kèm câu hỏi tới nhà cung '
            'cấp AI đã cấu hình trong Cài đặt.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Future<void> _askAi() async {
    // Người dùng đã tắt việc gửi điểm ra ngoài thì không lách qua nút này.
    if (!await SettingsService.instance.getSendTranscriptToAi()) {
      if (!mounted) return;
      Ui.info(
        context,
        'Đang tắt công tắc "Gửi bảng điểm kèm câu hỏi cho AI". Bật lại trong '
        'Cài đặt nếu muốn AI phân tích điểm của bạn.',
      );
      return;
    }

    setState(() {
      _aiRunning = true;
      _aiAnswer = '';
      _aiError = null;
    });

    try {
      final answer = await AiService.instance.ask(
        question: _analysisQuestion,
        // Truyền thẳng hồ sơ học lực làm ngữ cảnh thay vì đi đường Graph RAG:
        // câu hỏi này không nhắm vào môn nào cụ thể, cái cần là toàn bộ số
        // liệu điểm — giống cách `SubjectChatService` truyền `extraContext`.
        extraContext: AppState.instance.academicProfileOrEmpty
            .renderForPrompt(),
        extraContextHasGrades: true,
        includeKnowledgeContext: false,
        onDelta: (delta) {
          if (!mounted) return;
          setState(() => _aiAnswer += delta);
        },
      );
      if (!mounted) return;
      setState(() => _aiAnswer = answer.text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiError = e.toString());
    } finally {
      if (mounted) setState(() => _aiRunning = false);
    }
  }

  Widget _aiPanel() {
    return _SectionCard(
      icon: Icons.auto_awesome,
      title: 'Nhận xét của AI',
      subtitle:
          'Dựa trên số liệu ở trang này. Mã môn trong câu trả lời bấm được.',
      child: _aiError != null
          ? Text(
              _aiError!,
              style: TextStyle(fontSize: 13, color: AppColors.error),
            )
          // Lúc đang stream thì để chữ thường: câu còn dở có thể cắt ngang
          // giữa "[[CSD2", bóc link lúc đó sẽ nhấp nháy lung tung.
          : _aiRunning
          ? SelectableText(
              _aiAnswer.isEmpty ? 'Đang chờ phản hồi...' : '$_aiAnswer▌',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.6,
                color: AppColors.textPrimary,
              ),
            )
          : LinkedAnswerText(
              text: _aiAnswer,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.6,
                color: AppColors.textPrimary,
              ),
            ),
    );
  }
}

// ============================================================================
// CÁC KHỐI DỰNG SẴN
// ============================================================================

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    this.subtitle = '',
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.55,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final Color color;
  final bool big;

  const _StatCard({
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: big ? 34 : 26,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}

/// Một thanh ngang cho mỗi nhóm năng lực, dài theo GPA nhóm.
class _DomainBar extends StatelessWidget {
  final DomainScore domain;
  final double overallGpa;

  const _DomainBar({required this.domain, required this.overallGpa});

  @override
  Widget build(BuildContext context) {
    final significant = domain.isSignificant;
    final barColor = !significant
        ? AppColors.textHint
        : domain.isStrong
        ? AppColors.success
        : domain.isWeak
        ? AppColors.warning
        : AppColors.primary;

    return Opacity(
      // Nhóm chưa đủ dữ liệu vẫn hiện để người dùng biết nó tồn tại, nhưng mờ
      // đi để không bị đọc nhầm thành một kết luận.
      opacity: significant ? 1 : 0.55,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    domain.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  significant
                      ? '${domain.gpa.toStringAsFixed(2)}  (${domain.deltaLabel})'
                      : '${domain.gpa.toStringAsFixed(2)}  · chưa đủ dữ liệu',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: barColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (domain.gpa / 10).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${domain.subjectCount} môn có điểm · ${domain.credits} tín chỉ '
              '· ${domain.codes.join(", ")}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: AppColors.textHint),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskTile extends StatelessWidget {
  final RiskWarning risk;
  final VoidCallback onOpen;

  const _RiskTile({required this.risk, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final isWeak = risk.kind == RiskKind.weakFoundation;
    final color = isWeak ? AppColors.warning : AppColors.textSecondary;

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isWeak ? Icons.trending_down : Icons.lock_clock,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bỏ ngoặc vuông cho gọn — phần bấm được là cả dòng.
                  Text(
                    risk.message.replaceAll('[[', '').replaceAll(']]', ''),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${risk.prerequisiteCode} mở ra ${risk.dependentCount} môn '
                    'phía sau · ${risk.subjectName}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, size: 14, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

class _TranscriptHeaderRow extends StatelessWidget {
  final _SortBy sortBy;
  final bool descending;
  final ValueChanged<_SortBy> onSort;

  const _TranscriptHeaderRow({
    required this.sortBy,
    required this.descending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
    );

    Widget sortable(String label, _SortBy by, double width) {
      final active = sortBy == by;
      return SizedBox(
        width: width,
        child: InkWell(
          onTap: () => onSort(by),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: style.copyWith(
                    color: active ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),
              if (active)
                Icon(
                  descending ? Icons.arrow_drop_down : Icons.arrow_drop_up,
                  size: 16,
                  color: AppColors.primary,
                ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          sortable('Mã môn', _SortBy.code, 100),
          Expanded(child: Text('Tên môn', style: style)),
          sortable('Kỳ', _SortBy.semester, 100),
          SizedBox(width: 56, child: Text('Tín chỉ', style: style)),
          sortable('Điểm', _SortBy.grade, 62),
          SizedBox(width: 90, child: Text('Trạng thái', style: style)),
          SizedBox(width: 110, child: Text('Tính vào GPA', style: style)),
        ],
      ),
    );
  }
}

class _TranscriptRow extends StatelessWidget {
  final TranscriptEntry entry;
  final ValueChanged<bool> onToggleGpa;

  const _TranscriptRow({required this.entry, required this.onToggleGpa});

  @override
  Widget build(BuildContext context) {
    final body = TextStyle(fontSize: 12.5, color: AppColors.textPrimary);
    final muted = TextStyle(fontSize: 12.5, color: AppColors.textSecondary);
    final color = AppColors.gradeColor(entry.grade, entry.status);

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    entry.subjectCode,
                    overflow: TextOverflow.ellipsis,
                    style: body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (entry.isGraduationCondition)
                  Tooltip(
                    message:
                        'Môn điều kiện tốt nghiệp — không tính vào GPA tích luỹ',
                    child: Text(
                      ' *',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              entry.subjectName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: body,
            ),
          ),
          SizedBox(width: 100, child: Text(entry.displaySemester, style: muted)),
          SizedBox(width: 56, child: Text('${entry.credits}', style: muted)),
          SizedBox(
            width: 62,
            child: Text(
              entry.displayGrade,
              style: body.copyWith(fontWeight: FontWeight.w700, color: color),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              entry.statusLabel,
              style: muted.copyWith(color: color),
            ),
          ),
          SizedBox(
            width: 110,
            child: Checkbox(
              value: entry.countsTowardGpa,
              onChanged: entry.id == null
                  ? null
                  : (v) => onToggleGpa(v ?? false),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// BIỂU ĐỒ GPA THEO KỲ
// ============================================================================

/// Đường gấp khúc GPA theo kỳ, vẽ tay bằng [CustomPainter].
///
/// Không kéo thêm thư viện chart vào chỉ vì một biểu đồ: dữ liệu ở đây là một
/// dãy điểm đơn giản, và giữ số dependency ở mức tối thiểu là một ràng buộc
/// của dự án.
class _SemesterChartPainter extends CustomPainter {
  final List<SemesterGpa> points;
  final double averageGpa;
  final Color lineColor;
  final Color gridColor;
  final Color textColor;
  final Color surfaceColor;

  /// Trục dọc cố định 5 -> 10 thay vì co giãn theo dữ liệu: thang cố định làm
  /// biểu đồ của hai kỳ khác nhau so sánh được bằng mắt.
  static const double minGpa = 5.0;
  static const double maxGpa = 10.0;

  _SemesterChartPainter({
    required this.points,
    required this.averageGpa,
    required this.lineColor,
    required this.gridColor,
    required this.textColor,
    required this.surfaceColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const left = 34.0;
    const right = 8.0;
    const top = 10.0;
    const bottom = 26.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    if (chart.width <= 0 || chart.height <= 0) return;

    double yOf(double gpa) {
      final ratio = ((gpa - minGpa) / (maxGpa - minGpa)).clamp(0.0, 1.0);
      return chart.bottom - ratio * chart.height;
    }

    double xOf(int index) {
      if (points.length == 1) return chart.center.dx;
      return chart.left + chart.width * index / (points.length - 1);
    }

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // Lưới ngang mỗi 1 điểm, kèm nhãn trục dọc.
    for (var g = minGpa; g <= maxGpa; g += 1) {
      final y = yOf(g);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      _text(
        canvas,
        g.toStringAsFixed(0),
        Offset(2, y - 6),
        textColor,
        10,
      );
    }

    // Đường GPA tích luỹ để so sánh từng kỳ với mặt bằng chung.
    if (averageGpa >= minGpa && averageGpa <= maxGpa) {
      final y = yOf(averageGpa);
      final dash = Paint()
        ..color = lineColor.withValues(alpha: 0.45)
        ..strokeWidth = 1.2;
      for (var x = chart.left; x < chart.right; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), dash);
      }
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final offset = Offset(xOf(i), yOf(points[i].gpa));
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    canvas.drawPath(path, linePaint);

    final dotFill = Paint()..color = surfaceColor;
    final dotStroke = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final offset = Offset(xOf(i), yOf(p.gpa));
      canvas.drawCircle(offset, 4, dotFill);
      canvas.drawCircle(offset, 4, dotStroke);

      _text(
        canvas,
        p.gpa.toStringAsFixed(2),
        offset + const Offset(-14, -20),
        lineColor,
        10.5,
      );
      // Nhãn kỳ rút gọn ("Fall2023" -> "F23") để các kỳ không chồng chữ nhau.
      _text(
        canvas,
        _shortLabel(p.label),
        Offset(offset.dx - 14, chart.bottom + 6),
        textColor,
        10,
      );
    }
  }

  String _shortLabel(String label) {
    final match = RegExp(r'^(\w)\w*(\d{2})(\d{2})$').firstMatch(label);
    if (match == null) return label;
    return '${match.group(1)}${match.group(3)}';
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    Color color,
    double size,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_SemesterChartPainter old) =>
      old.points != points ||
      old.averageGpa != averageGpa ||
      old.lineColor != lineColor ||
      old.surfaceColor != surfaceColor;
}
