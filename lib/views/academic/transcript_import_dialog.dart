import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../models/graph_data.dart';
import '../../models/transcript_entry.dart';
import '../../services/academic_analytics_service.dart';
import '../../services/db_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';

/// Nhập bảng điểm từ file transcript của FAP.
///
/// Đi đúng mạch `FapImportDialog`: **chọn file -> bóc tách -> xem trước -> mới
/// ghi**. Màn xem trước phải trả lời được bốn câu trước khi người dùng bấm
/// nút: đọc được bao nhiêu dòng (và bỏ qua dòng nào, vì sao), bao nhiêu môn
/// khớp với đồ thị, bao nhiêu môn chưa có, và GPA tính ra bằng bao nhiêu để
/// đối chiếu ngay với con số trên FAP.
class TranscriptImportDialog extends StatefulWidget {
  final TranscriptImportPlan plan;

  const TranscriptImportDialog({super.key, required this.plan});

  /// Mở hộp thoại chọn file rồi hiện bản xem trước.
  ///
  /// Trả về `true` khi đã ghi xuống CSDL, `null` khi người dùng huỷ hoặc
  /// không chọn file nào.
  static Future<bool?> pickAndShow(BuildContext context) async {
    const typeGroup = XTypeGroup(
      label: 'Bảng điểm FAP',
      extensions: ['xls', 'xlsx', 'html', 'htm'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null || !context.mounted) return null;

    TranscriptImportPlan plan;
    try {
      plan = await AppState.instance.planTranscriptImport(file.path);
    } catch (e) {
      if (context.mounted) Ui.error(context, e);
      return null;
    }
    if (!context.mounted) return null;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => TranscriptImportDialog(plan: plan),
    );
  }

  @override
  State<TranscriptImportDialog> createState() => _TranscriptImportDialogState();
}

class _TranscriptImportDialogState extends State<TranscriptImportDialog> {
  bool _saving = false;

  /// Mặc định **tắt**: Vovinam và tiếng Nhật không nên tự động nhảy vào đồ thị
  /// tri thức ngành. Điểm của chúng vẫn được lưu đủ dù tuỳ chọn này tắt.
  bool _createMissingSubjects = false;

  TranscriptImportPlan get _plan => widget.plan;

  /// GPA tính ngay trên dữ liệu vừa bóc, trước khi ghi — để người dùng đối
  /// chiếu với con số FAP đang hiện và bắt được lỗi bóc tách ngay tại đây.
  late final AcademicProfile _preview = AcademicAnalyticsService.instance
      .analyze(_plan.entries, GraphData.empty);

  Future<void> _import() async {
    setState(() => _saving = true);
    try {
      final result = await AppState.instance.applyTranscriptPlan(
        _plan,
        createMissingSubjects: _createMissingSubjects,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      Ui.success(context, result.summary);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      Ui.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.insights_outlined, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Nhập bảng điểm từ FAP')),
        ],
      ),
      content: SizedBox(
        width: 860,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(
                  icon: Icons.table_rows_outlined,
                  label: '${_plan.totalCount} dòng đọc được',
                ),
                _Chip(
                  icon: Icons.link,
                  label: '${_plan.matchedCount} dòng khớp môn trong đồ thị',
                ),
                _Chip(
                  icon: Icons.help_outline,
                  label:
                      '${_plan.missingSubjectCodes.length} môn chưa có trong đồ thị',
                ),
                _Chip(
                  icon: Icons.edit_note,
                  label: _plan.willOverwriteCount == 0
                      ? 'Chưa có dòng nào bị ghi đè'
                      : '${_plan.willOverwriteCount} dòng sẽ được cập nhật',
                ),
                _Chip(
                  icon: Icons.school_outlined,
                  label:
                      'GPA ${_preview.gpaLabel} · ${_preview.totalCredits} tín chỉ '
                      '· ${_preview.gpaSubjectCount} môn',
                  highlight: true,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Đối chiếu GPA và số tín chỉ ở trên với con số FAP đang hiện. '
              'Lệch nhau nghĩa là file chưa tải đủ, chưa nên ghi vào CSDL.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (_plan.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              _WarningBox(warnings: _plan.warnings),
            ],
            if (_plan.missingSubjectCodes.isNotEmpty) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _createMissingSubjects,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _createMissingSubjects = v ?? false),
                title: const Text(
                  'Tự tạo các môn còn thiếu trong đồ thị',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Tắt (khuyến nghị): điểm vẫn được lưu đủ, chỉ là chưa gắn '
                  'vào node nào — tránh đưa Vovinam, tiếng Nhật, tiếng Anh dự '
                  'bị vào đồ thị tri thức ngành. '
                  'Các môn chưa có: ${_plan.missingSubjectCodes.join(", ")}',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Divider(height: 1),
            Flexible(
              child: Scrollbar(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _plan.entries.length + 1,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    if (index == 0) return const _HeaderRow();
                    return _EntryRow(entry: _plan.entries[index - 1]);
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
          onPressed: _saving || _plan.isEmpty ? null : _import,
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

/// Khối liệt kê những dòng bị bỏ qua. Hiện nguyên văn lý do chứ không chỉ đếm
/// — người dùng cần biết mình mất dòng nào.
class _WarningBox extends StatelessWidget {
  final List<String> warnings;

  const _WarningBox({required this.warnings});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${warnings.length} dòng bị bỏ qua',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          for (final w in warnings.take(6))
            Text(
              '• $w',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          if (warnings.length > 6)
            Text(
              '• (còn ${warnings.length - 6} dòng nữa)',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

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
          SizedBox(width: 92, child: Text('Mã môn', style: style)),
          Expanded(child: Text('Tên môn', style: style)),
          SizedBox(width: 92, child: Text('Kỳ', style: style)),
          SizedBox(width: 56, child: Text('Tín chỉ', style: style)),
          SizedBox(width: 52, child: Text('Điểm', style: style)),
          SizedBox(width: 82, child: Text('Trạng thái', style: style)),
          SizedBox(width: 74, child: Text('Vào GPA', style: style)),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final TranscriptEntry entry;

  const _EntryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final body = TextStyle(fontSize: 12, color: AppColors.textPrimary);
    final muted = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    final gradeColor = AppColors.gradeColor(entry.grade, entry.status);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Row(
              children: [
                Text(
                  entry.subjectCode,
                  style: body.copyWith(fontWeight: FontWeight.w600),
                ),
                if (entry.isGraduationCondition)
                  Text(
                    ' *',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.error,
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
          SizedBox(width: 92, child: Text(entry.displaySemester, style: muted)),
          SizedBox(width: 56, child: Text('${entry.credits}', style: muted)),
          SizedBox(
            width: 52,
            child: Text(
              entry.displayGrade,
              style: body.copyWith(
                fontWeight: FontWeight.w700,
                color: gradeColor,
              ),
            ),
          ),
          SizedBox(
            width: 82,
            child: Text(
              entry.statusLabel,
              style: muted.copyWith(color: gradeColor),
            ),
          ),
          SizedBox(
            width: 74,
            child: Icon(
              entry.countsTowardGpa ? Icons.check_circle : Icons.remove_circle_outline,
              size: 15,
              color: entry.countsTowardGpa
                  ? AppColors.success
                  : AppColors.textHint,
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
  final bool highlight;

  const _Chip({required this.icon, required this.label, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.success : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
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
