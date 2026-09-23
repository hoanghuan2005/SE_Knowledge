import 'package:flutter/material.dart';

import '../../models/transcript_entry.dart';
import '../../services/goal_planner_service.dart';
import '../../utils/app_colors.dart';

/// Màu của mức khả thi mục tiêu GPA: xanh khi đúng hướng, vàng khi phải
/// cố hơn, đỏ khi chỉ học cải thiện mới kịp.
Color goalStatusColor(GoalStatus status) => switch (status) {
  GoalStatus.secured || GoalStatus.onTrack => AppColors.statusGood,
  GoalStatus.stretch => AppColors.statusWarning,
  GoalStatus.needsRetake => AppColors.statusCritical,
};

IconData goalStatusIcon(GoalStatus status) => switch (status) {
  GoalStatus.secured => Icons.verified_outlined,
  GoalStatus.onTrack => Icons.check_circle_outline,
  GoalStatus.stretch => Icons.trending_up,
  GoalStatus.needsRetake => Icons.warning_amber_rounded,
};

/// Trạng thái của một môn **so với GPA mục tiêu** — cách tô xanh/đỏ dùng
/// chung cho bảng học kỳ, màn hình tổng quan và bảng tri thức.
///
/// Màu trạng thái không bao giờ đứng một mình: mỗi mức có biểu tượng và nhãn
/// riêng, để người mù màu đỏ-lục vẫn đọc được bảng.
enum TargetStatus {
  /// Đã qua và đạt từ mục tiêu trở lên.
  reached,

  /// Đã qua nhưng dưới mục tiêu — ứng viên học cải thiện.
  belowTarget,

  /// Đã qua, môn không chấm điểm (LAB211, TRS601).
  passedNoGrade,

  /// Học rồi nhưng trượt.
  failed,

  studying,
  notStarted,
}

class TargetStatusStyle {
  final String label;
  final String shortLabel;
  final IconData icon;
  final Color color;

  const TargetStatusStyle({
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.color,
  });
}

TargetStatus targetStatusOf(TranscriptEntry? entry, double target) {
  if (entry == null) return TargetStatus.notStarted;
  switch (entry.status) {
    case SubjectStatus.notPassed:
      return TargetStatus.failed;
    case SubjectStatus.studying:
      return TargetStatus.studying;
    case SubjectStatus.notStarted:
    case SubjectStatus.unknown:
      return TargetStatus.notStarted;
    case SubjectStatus.passed:
      final g = entry.grade;
      if (g == null) return TargetStatus.passedNoGrade;
      return g >= target ? TargetStatus.reached : TargetStatus.belowTarget;
  }
}

TargetStatusStyle targetStatusStyle(TargetStatus status) => switch (status) {
  TargetStatus.reached => TargetStatusStyle(
    label: 'Đạt mục tiêu',
    shortLabel: 'Đạt',
    icon: Icons.check_circle,
    color: AppColors.statusGood,
  ),
  TargetStatus.belowTarget => const TargetStatusStyle(
    label: 'Dưới mục tiêu — nên cải thiện',
    shortLabel: 'Cải thiện',
    icon: Icons.trending_up,
    color: AppColors.statusSerious,
  ),
  TargetStatus.passedNoGrade => TargetStatusStyle(
    label: 'Đã qua (không chấm điểm)',
    shortLabel: 'Đã qua',
    icon: Icons.task_alt,
    color: AppColors.isDark ? const Color(0xFF7E8894) : const Color(0xFF6B7280),
  ),
  TargetStatus.failed => const TargetStatusStyle(
    label: 'Chưa qua — phải học lại',
    shortLabel: 'Chưa qua',
    icon: Icons.cancel,
    color: AppColors.statusCritical,
  ),
  TargetStatus.studying => TargetStatusStyle(
    label: 'Đang học',
    shortLabel: 'Đang học',
    icon: Icons.schedule,
    color: AppColors.isDark ? const Color(0xFFB388FF) : const Color(0xFF6D3FD1),
  ),
  TargetStatus.notStarted => TargetStatusStyle(
    label: 'Chưa học',
    shortLabel: 'Chưa học',
    icon: Icons.radio_button_unchecked,
    color: AppColors.isDark ? const Color(0xFF6E6E82) : const Color(0xFF9195A6),
  ),
};

/// Nhãn nhỏ: biểu tượng + chữ, cùng màu trạng thái.
class TargetStatusChip extends StatelessWidget {
  final TargetStatus status;
  final String? text;
  final bool compact;

  const TargetStatusChip({
    super.key,
    required this.status,
    this.text,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = targetStatusStyle(status);
    return Tooltip(
      message: style.label,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7, vertical: 2),
        decoration: BoxDecoration(
          color: style.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 12, color: style.color),
            const SizedBox(width: 4),
            Text(
              text ?? style.shortLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
