import 'package:flutter/material.dart';

import '../../models/subject.dart';
import '../../services/subject_delete_guard.dart';
import '../../utils/app_colors.dart';

/// Lựa chọn người dùng chốt trên hộp thoại cảnh báo xoá.
class SubjectDeleteChoice {
  final DeleteStrategy strategy;
  final bool deleteNoteFile;

  const SubjectDeleteChoice({
    required this.strategy,
    required this.deleteNoteFile,
  });
}

/// Hộp thoại cảnh báo trước khi xoá một môn học.
///
/// Dựng hoàn toàn từ [DeleteImpact] mà [SubjectDeleteGuard] phân tích ra, nên
/// nội dung đổi theo từng môn: môn đứng một mình chỉ hỏi một câu, còn môn nằm
/// giữa chuỗi tiên quyết thì liệt kê đủ những gì sắp mất và mời nối tắt để vá.
///
/// Trả về `null` khi người dùng huỷ, hoặc [SubjectDeleteChoice] khi đồng ý xoá.
class SubjectDeleteDialog extends StatefulWidget {
  final DeleteImpact impact;

  const SubjectDeleteDialog({super.key, required this.impact});

  @override
  State<SubjectDeleteDialog> createState() => _SubjectDeleteDialogState();
}

class _SubjectDeleteDialogState extends State<SubjectDeleteDialog> {
  late DeleteStrategy _strategy;
  bool _deleteNoteFile = false;

  DeleteImpact get _impact => widget.impact;

  @override
  void initState() {
    super.initState();
    // Khi môn đang bị phụ thuộc mà vẫn nối tắt được thì chọn sẵn phương án nối
    // tắt: đó đúng là ca mà xoá thẳng sẽ cắt đôi lộ trình học. Các ca còn lại
    // giữ mặc định xoá thẳng cho đúng với điều người dùng vừa bấm.
    _strategy = _impact.risk == DeleteRisk.danger && _impact.canRewire
        ? DeleteStrategy.rewire
        : DeleteStrategy.cascade;
  }

  Color get _riskColor => switch (_impact.risk) {
    DeleteRisk.safe => AppColors.info,
    DeleteRisk.warning => AppColors.warning,
    DeleteRisk.danger => AppColors.error,
  };

  IconData get _riskIcon => switch (_impact.risk) {
    DeleteRisk.safe => Icons.info_outline,
    DeleteRisk.warning => Icons.warning_amber_rounded,
    DeleteRisk.danger => Icons.dangerous_outlined,
  };

  String get _riskLabel => switch (_impact.risk) {
    DeleteRisk.safe => 'An toàn',
    DeleteRisk.warning => 'Cần cân nhắc',
    DeleteRisk.danger => 'Nguy hiểm',
  };

  @override
  Widget build(BuildContext context) {
    final target = _impact.target;

    return AlertDialog(
      title: Row(
        children: [
          Icon(_riskIcon, color: _riskColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Xoá ${target.code}?',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _banner(),
              const SizedBox(height: 16),
              if (_impact.dependents.isNotEmpty)
                _SubjectGroup(
                  icon: Icons.link_off,
                  color: AppColors.error,
                  title: 'Các môn đang lấy ${target.code} làm tiên quyết',
                  note: 'Xoá xong, các môn này mất điều kiện đầu vào.',
                  subjects: _impact.dependents,
                ),
              if (_impact.prerequisites.isNotEmpty)
                _SubjectGroup(
                  icon: Icons.north_east,
                  color: AppColors.textSecondary,
                  title: 'Liên kết tới môn tiên quyết sẽ bị gỡ',
                  subjects: _impact.prerequisites,
                ),
              if (_impact.willBecomeOrphan.isNotEmpty)
                _SubjectGroup(
                  icon: Icons.scatter_plot_outlined,
                  color: AppColors.warning,
                  title: 'Sẽ thành môn đơn độc trên đồ thị',
                  note: 'Không còn liên kết nào nối vào lẫn nối ra.',
                  subjects: _impact.willBecomeOrphan,
                ),
              if (_impact.canRewire) ...[
                const SizedBox(height: 4),
                _strategyPicker(),
              ],
              // Chỉ nêu cạnh bị bỏ khi đang chọn nối tắt — chọn xoá thẳng thì
              // chuyện chu trình không liên quan gì tới điều sắp xảy ra.
              if (_strategy == DeleteStrategy.rewire &&
                  _impact.rewireBlocked.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final line in _impact.rewireBlocked)
                  _NoteLine(icon: Icons.block, text: line),
              ],
              if (_impact.hasNoteFile) ...[
                const SizedBox(height: 12),
                _noteFileOption(),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(
            _strategy == DeleteStrategy.rewire ? 'Nối tắt rồi xoá' : 'Xoá',
          ),
          onPressed: () => Navigator.pop(
            context,
            SubjectDeleteChoice(
              strategy: _strategy,
              deleteNoteFile: _deleteNoteFile,
            ),
          ),
        ),
      ],
    );
  }

  Widget _banner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _riskColor.withValues(alpha: AppColors.isDark ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _riskColor.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _riskLabel.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: _riskColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _impact.headline,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _strategyPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Xử lý các liên kết bắc cầu',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<DeleteStrategy>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: DeleteStrategy.rewire,
              icon: Icon(Icons.alt_route, size: 16),
              label: Text('Nối tắt'),
            ),
            ButtonSegment(
              value: DeleteStrategy.cascade,
              icon: Icon(Icons.content_cut, size: 16),
              label: Text('Xoá thẳng'),
            ),
          ],
          selected: {_strategy},
          onSelectionChanged: (s) => setState(() => _strategy = s.first),
        ),
        const SizedBox(height: 8),
        if (_strategy == DeleteStrategy.rewire) ...[
          Text(
            'Nối thẳng môn trước với môn sau để lộ trình học không bị đứt. '
            'Sẽ tạo ${_impact.rewireSuggestions.length} liên kết mới:',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in _impact.rewireSuggestions)
                _Chip(
                  label: '${r.from.code} → ${r.to.code}',
                  color: AppColors.success,
                ),
            ],
          ),
        ] else
          Text(
            'Mọi liên kết của ${_impact.target.code} biến mất, không nối bù. '
            'Các môn phía sau sẽ mất điều kiện đầu vào.',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _noteFileOption() {
    // Nền phải đặt trên Material chứ không phải trên một Container lồng giữa:
    // CheckboxListTile vẽ hiệu ứng chạm lên Material gần nhất, có màu nền chắn
    // ở giữa thì hiệu ứng bị che mất.
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              value: _deleteNoteFile,
              onChanged: (v) => setState(() => _deleteNoteFile = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                'Xoá luôn file .md trong Vault',
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
              ),
              subtitle: Text(
                _impact.notePath!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: AppColors.textHint),
              ),
            ),
            if (!_deleteNoteFile)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _NoteLine(
                  icon: Icons.info_outline,
                  color: AppColors.warning,
                  text:
                      'Giữ file lại thì lần nhập dữ liệu từ Vault kế tiếp sẽ '
                      'tạo lại đúng môn vừa xoá.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Một nhóm môn bị ảnh hưởng, hiển thị dạng danh sách thẻ.
class _SubjectGroup extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? note;
  final List<Subject> subjects;

  const _SubjectGroup({
    required this.icon,
    required this.color,
    required this.title,
    required this.subjects,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$title (${subjects.length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in subjects)
                Tooltip(
                  message: s.name,
                  child: _Chip(label: s.code, color: color),
                ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                note!,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppColors.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _NoteLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _NoteLine({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1.5),
            child: Icon(icon, size: 13, color: tint),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11.5, height: 1.45, color: tint),
            ),
          ),
        ],
      ),
    );
  }
}
