import 'package:flutter/material.dart';

import '../../services/db_service.dart';
import '../../services/fap_markdown_parser.dart';
import '../../services/md_intake_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';

/// Hộp thoại xem trước dữ liệu FAP vừa nhận từ extension Chrome.
///
/// Không có gì được ghi xuống CSDL cho tới khi người dùng bấm "Ghi vào CSDL":
/// file `.md` đã nằm an toàn trên đĩa rồi, nên đóng hộp thoại không mất gì.
class FapImportDialog extends StatefulWidget {
  final IncomingNote note;
  final FapCurriculumImport data;

  const FapImportDialog({super.key, required this.note, required this.data});

  /// Mở hộp thoại phù hợp với kết quả bóc tách.
  ///
  /// Trang chưa hỗ trợ hoặc không nhận ra thì chỉ báo gọn một câu, vẫn cho biết
  /// file `.md` đã được lưu ở đâu để người dùng tự mở xem.
  static Future<void> show(
    BuildContext context,
    IncomingNote note,
    FapParseResult result,
  ) {
    final curriculum = result.curriculum;
    if (curriculum != null) {
      return showDialog<void>(
        context: context,
        builder: (ctx) => FapImportDialog(note: note, data: curriculum),
      );
    }

    final syllabus = result.syllabus;
    if (syllabus != null) {
      return showDialog<void>(
        context: context,
        builder: (ctx) => FapSyllabusImportDialog(note: note, data: syllabus),
      );
    }

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.info_outline, size: 32),
        title: const Text('Đã nhận trang từ Chrome'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.message),
            const SizedBox(height: 12),
            _PathLine(label: 'Đã lưu file', value: note.savedPath),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  State<FapImportDialog> createState() => _FapImportDialogState();
}

class _FapImportDialogState extends State<FapImportDialog> {
  bool _saving = false;

  /// Mã môn đang có trong đồ thị, để dán nhãn "Mới" / "Đã có" cho từng dòng.
  late final Set<String> _knownCodes = {
    for (final code in AppState.instance.graph.byCode.keys) code.toUpperCase(),
  };

  Future<void> _import() async {
    setState(() => _saving = true);
    try {
      final result =
          await DbService.instance.importFapCurriculum(widget.data);
      await AppState.instance.refresh();
      if (!mounted) return;
      Navigator.pop(context);
      Ui.success(
        context,
        'Đã nhập ${result.curriculumCode}: ${result.insertedSubjects} môn mới, '
        '${result.updatedSubjects} môn cập nhật, ${result.plos} PLO, '
        '${result.curriculumSubjects} liên kết chương trình.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      Ui.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final newCount =
        data.subjects.where((s) => !_knownCodes.contains(s.code.toUpperCase())).length;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.school_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              data.code.isEmpty ? 'Chương trình đào tạo' : data.code,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 860,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data.name.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  data.name,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(
                  icon: Icons.tag,
                  label: 'curid ${data.fapCurriculumId ?? '—'}',
                ),
                _Chip(
                  icon: Icons.numbers,
                  label: '${data.totalCredits ?? '—'} tín chỉ',
                ),
                _Chip(
                  icon: Icons.menu_book_outlined,
                  label: '${data.subjectCount} môn bóc được',
                ),
                _Chip(
                  icon: Icons.fiber_new_outlined,
                  label: '$newCount môn mới',
                ),
                _Chip(icon: Icons.flag_outlined, label: '${data.plos.length} PLO'),
              ],
            ),
            const SizedBox(height: 12),
            _PathLine(label: 'Đã lưu file', value: widget.note.savedPath),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Flexible(
              child: data.subjects.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'Không bóc được môn nào từ trang này. '
                        'Kiểm tra lại xem trang FAP đã tải xong bảng môn học chưa.',
                      ),
                    )
                  : Scrollbar(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: data.subjects.length + 1,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          if (index == 0) return const _SubjectHeaderRow();
                          final row = data.subjects[index - 1];
                          return _SubjectRow(
                            row: row,
                            isNew: !_knownCodes.contains(row.code.toUpperCase()),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        ElevatedButton.icon(
          onPressed: _saving || data.subjects.isEmpty ? null : _import,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: const Text('Ghi vào CSDL'),
        ),
      ],
    );
  }
}

class _SubjectHeaderRow extends StatelessWidget {
  const _SubjectHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text('Mã môn', style: style)),
          Expanded(flex: 4, child: Text('Tên môn', style: style)),
          SizedBox(width: 44, child: Text('Kỳ', style: style)),
          SizedBox(width: 56, child: Text('Tín chỉ', style: style)),
          Expanded(flex: 3, child: Text('Tiên quyết (nguyên văn)', style: style)),
          SizedBox(width: 64, child: Text('Trạng thái', style: style)),
        ],
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  final FapSubjectRow row;
  final bool isNew;

  const _SubjectRow({required this.row, required this.isNew});

  @override
  Widget build(BuildContext context) {
    final body = TextStyle(fontSize: 12, color: AppColors.textPrimary);
    final muted = TextStyle(fontSize: 12, color: AppColors.textSecondary);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              row.code,
              style: body.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.displayName, style: body),
                if (row.nameVn.isNotEmpty && row.nameEn.isNotEmpty)
                  Text(row.nameVn, style: muted.copyWith(fontSize: 11)),
              ],
            ),
          ),
          SizedBox(width: 44, child: Text('${row.semester}', style: muted)),
          SizedBox(width: 56, child: Text('${row.credits}', style: muted)),
          Expanded(
            flex: 3,
            child: Text(
              row.rawPrerequisite.isEmpty ? '—' : row.rawPrerequisite,
              style: muted,
            ),
          ),
          SizedBox(
            width: 64,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (isNew ? AppColors.success : AppColors.textHint)
                      .withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isNew ? 'Mới' : 'Đã có',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isNew ? AppColors.success : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PathLine extends StatelessWidget {
  final String label;
  final String value;

  const _PathLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(fontSize: 11.5, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// Hộp thoại xem trước dữ liệu Syllabus vừa nhận từ Chrome.
class FapSyllabusImportDialog extends StatefulWidget {
  final IncomingNote note;
  final FapSyllabusImport data;

  const FapSyllabusImportDialog({
    super.key,
    required this.note,
    required this.data,
  });

  @override
  State<FapSyllabusImportDialog> createState() => _FapSyllabusImportDialogState();
}

class _FapSyllabusImportDialogState extends State<FapSyllabusImportDialog> {
  bool _saving = false;

  Future<void> _import() async {
    setState(() => _saving = true);
    try {
      final result = await DbService.instance.importFapSyllabus(widget.data);
      await AppState.instance.refresh();
      if (!mounted) return;
      Navigator.pop(context);
      Ui.success(
        context,
        'Đã lưu Syllabus môn ${result.subjectCode}: '
        '${result.materialsCount} tài liệu, ${result.closCount} CLO, '
        '${result.sessionsCount} buổi học, ${result.assessmentsCount} đầu điểm.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      Ui.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.auto_stories_outlined, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              data.subjectCode.isEmpty ? 'Syllabus chi tiết' : 'Syllabus: ${data.subjectCode}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 880,
        height: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data.displayName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  data.displayName,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Chip(
                  icon: Icons.code,
                  label: data.subjectCode,
                ),
                if (data.degreeLevel.isNotEmpty)
                  _Chip(
                    icon: Icons.school_outlined,
                    label: data.degreeLevel,
                  ),
                if (data.scoringScale != null)
                  _Chip(
                    icon: Icons.military_tech_outlined,
                    label: 'Thang điểm ${data.scoringScale}',
                  ),
                if (data.decisionNo.isNotEmpty)
                  _Chip(
                    icon: Icons.description_outlined,
                    label: data.decisionNo,
                  ),
                _Chip(
                  icon: data.isApproved ? Icons.verified_outlined : Icons.pending_outlined,
                  label: data.isApproved ? 'Đã duyệt' : 'Chưa duyệt',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DefaultTabController(
                length: 4,
                child: Column(
                  children: [
                    TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: AppColors.textSecondary,
                      indicatorColor: AppColors.primary,
                      tabs: [
                        Tab(text: 'Giáo trình (${data.materials.length})'),
                        Tab(text: 'Chuẩn đầu ra CLO (${data.clos.length})'),
                        Tab(text: 'Lịch trình (${data.sessions.length} buổi)'),
                        Tab(text: 'Đánh giá (${data.assessments.length})'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildMaterialsTab(data),
                          _buildClosTab(data),
                          _buildSessionsTab(data),
                          _buildAssessmentsTab(data),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _PathLine(label: 'Đã lưu file', value: widget.note.savedPath),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _import,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check, size: 16),
          label: Text(_saving ? 'Đang ghi...' : 'Ghi vào CSDL'),
        ),
      ],
    );
  }

  Widget _buildMaterialsTab(FapSyllabusImport data) {
    if (data.materials.isEmpty) {
      return const Center(child: Text('Không có tài liệu nào trong đề cương.'));
    }
    return ListView.separated(
      itemCount: data.materials.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (ctx, idx) {
        final m = data.materials[idx];
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: Text('${m.seqNo}', style: TextStyle(fontSize: 11, color: AppColors.primary)),
          ),
          title: Text(m.description, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
          subtitle: Text(
            [
              if (m.author.isNotEmpty) 'Tác giả: ${m.author}',
              if (m.publisher.isNotEmpty) 'NXB: ${m.publisher}',
              if (m.publishedDate.isNotEmpty) 'Năm: ${m.publishedDate}',
              if (m.edition.isNotEmpty) 'Tái bản: ${m.edition}',
              if (m.isbn.isNotEmpty) 'ISBN: ${m.isbn}',
              if (m.note.isNotEmpty) m.note,
            ].join(' • '),
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              if (m.isMain)
                const Chip(
                  label: Text('Chính', style: TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              if (m.isOnline)
                const Chip(
                  label: Text('Online', style: TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClosTab(FapSyllabusImport data) {
    if (data.clos.isEmpty) {
      return const Center(child: Text('Không có chuẩn đầu ra nào trong đề cương.'));
    }
    return ListView.separated(
      itemCount: data.clos.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (ctx, idx) {
        final clo = data.clos[idx];
        return ListTile(
          dense: true,
          leading: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              clo.code,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: AppColors.success,
              ),
            ),
          ),
          title: Text(
            clo.detail,
            style: const TextStyle(fontSize: 12),
          ),
        );
      },
    );
  }

  Widget _buildSessionsTab(FapSyllabusImport data) {
    if (data.sessions.isEmpty) {
      return const Center(child: Text('Không có lịch trình buổi học trong đề cương.'));
    }
    return ListView.separated(
      itemCount: data.sessions.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (ctx, idx) {
        final s = data.sessions[idx];
        return ListTile(
          dense: true,
          leading: Container(
            width: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'B${s.sessionNo}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
          ),
          title: Text(s.topic, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.rawLo.isNotEmpty)
                Text('Chuẩn đầu ra: ${s.rawLo}', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              if (s.studentTasks.isNotEmpty)
                Text('Nhiệm vụ: ${s.studentTasks}', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
          trailing: s.teachingType.isNotEmpty
              ? Chip(
                  label: Text(s.teachingType, style: const TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                )
              : null,
        );
      },
    );
  }

  Widget _buildAssessmentsTab(FapSyllabusImport data) {
    if (data.assessments.isEmpty) {
      return const Center(child: Text('Không có cấu trúc đánh giá trong đề cương.'));
    }
    return ListView.separated(
      itemCount: data.assessments.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (ctx, idx) {
        final a = data.assessments[idx];
        return ListTile(
          dense: true,
          leading: Container(
            width: 55,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${a.weightPercent.toStringAsFixed(a.weightPercent.truncateToDouble() == a.weightPercent ? 0 : 1)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.warning,
              ),
            ),
          ),
          title: Text(
            a.category,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              if (a.type.isNotEmpty) 'Hình thức: ${a.type}',
              if (a.duration.isNotEmpty) 'Thời gian: ${a.duration}',
              if (a.rawClo.isNotEmpty) 'Đo lường: ${a.rawClo}',
              if (a.completionCriteria.isNotEmpty) 'Đạt: ${a.completionCriteria}',
              if (a.note.isNotEmpty) a.note,
            ].join(' • '),
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        );
      },
    );
  }
}
