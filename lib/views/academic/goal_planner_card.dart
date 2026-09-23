import 'package:flutter/material.dart';

import '../../services/goal_planner_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../curriculum/grade_status.dart';

/// Thẻ "Mục tiêu GPA" ở tab Học lực.
///
/// Đặt một mục tiêu (mặc định 8.0), thẻ cho biết các môn còn lại phải đạt
/// trung bình bao nhiêu, cho kéo thử điểm dự kiến để xem GPA tốt nghiệp, và
/// liệt kê những môn **nên đăng ký học cải thiện** — tích vào môn nào thì
/// phần dự kiến cộng luôn môn đó.
class GoalPlannerCard extends StatefulWidget {
  final VoidCallback? onOpenBoard;

  const GoalPlannerCard({super.key, this.onOpenBoard});

  @override
  State<GoalPlannerCard> createState() => _GoalPlannerCardState();
}

class _GoalPlannerCardState extends State<GoalPlannerCard> {
  double? _assumed;
  final Set<String> _retakes = {};

  static const List<double> _presets = [7.0, 7.5, 8.0, 8.5, 9.0];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final plan = state.goalPlan;
        if (plan.isEmpty) return const SizedBox.shrink();

        final required = plan.requiredAverage;
        // Mặc định giả định giữ đúng phong độ hiện tại.
        final assumed = (_assumed ?? plan.currentGpa)
            .clamp(5.0, 10.0)
            .toDouble();
        final projected = plan.projectedGpa(
          remainingAverage: assumed,
          retakeCodes: _retakes,
        );
        final minimal = plan.minimalRetakes(remainingAverage: assumed);
        final statusColor = goalStatusColor(plan.status);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.flag_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Mục tiêu GPA tốt nghiệp',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    for (final v in _presets)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(v.toStringAsFixed(1)),
                          visualDensity: VisualDensity.compact,
                          selected: state.targetGpa == v,
                          onSelected: (_) {
                            setState(_retakes.clear);
                            state.setTargetGpa(v);
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        goalStatusIcon(plan.status),
                        size: 20,
                        color: statusColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _headline(plan),
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _Figure(
                        label: 'GPA hiện tại',
                        value: plan.currentGpa.toStringAsFixed(2),
                        hint: '${plan.countedCredits} tín chỉ đã tính',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Figure(
                        label: 'Cần TB cho môn còn lại',
                        value: required == null
                            ? '—'
                            : required > 10
                            ? '> 10'
                            : required.toStringAsFixed(2),
                        hint:
                            '${plan.remaining.length} môn · ${plan.remainingCredits} tín chỉ',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Figure(
                        label: 'GPA cao nhất có thể',
                        value: plan.maxReachableGpa.toStringAsFixed(2),
                        hint: 'nếu mọi môn còn lại đạt 10',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _progress(plan),
                const SizedBox(height: 18),
                Text(
                  'Mô phỏng',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    SizedBox(
                      width: 250,
                      child: Text(
                        'Điểm TB dự kiến cho các môn còn lại: '
                        '${assumed.toStringAsFixed(1)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: assumed,
                        min: 5,
                        max: 10,
                        divisions: 50,
                        label: assumed.toStringAsFixed(1),
                        onChanged: plan.remainingCredits == 0
                            ? null
                            : (v) => setState(() => _assumed = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'GPA tốt nghiệp ≈ ',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      projected.toStringAsFixed(2),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: projected >= plan.target
                            ? AppColors.statusGoodText
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      projected >= plan.target
                          ? Icons.check_circle
                          : Icons.remove_circle_outline,
                      size: 16,
                      color: projected >= plan.target
                          ? AppColors.statusGood
                          : AppColors.textHint,
                    ),
                  ],
                ),
                if (minimal.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Với TB ${assumed.toStringAsFixed(1)} cho môn còn lại, học '
                      'cải thiện ít nhất ${minimal.length} môn '
                      '(${minimal.map((r) => r.code).join(', ')}) là chạm '
                      '${plan.target.toStringAsFixed(1)}.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'Nên đăng ký học cải thiện',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (plan.belowTargetCount > 0)
                      Text(
                        '${plan.belowTargetCount} môn đã qua dưới '
                        '${plan.target.toStringAsFixed(1)} · xếp theo GPA được thêm',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    const Spacer(),
                    if (widget.onOpenBoard != null)
                      TextButton.icon(
                        icon: const Icon(Icons.view_week_outlined, size: 16),
                        label: const Text('Xem trên bảng học kỳ'),
                        onPressed: widget.onOpenBoard,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (plan.retakes.isEmpty)
                  Text(
                    'Không có môn nào đã qua mà dưới mục tiêu.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textHint),
                  )
                else
                  for (final r in plan.retakes)
                    _RetakeRow(
                      suggestion: r,
                      selected: _retakes.contains(r.code),
                      onChanged: (v) => setState(() {
                        if (v) {
                          _retakes.add(r.code);
                        } else {
                          _retakes.remove(r.code);
                        }
                      }),
                    ),
                const SizedBox(height: 10),
                Text(
                  'Giả định học lại đạt ${(plan.target + GoalPlannerService.retakeMargin).clamp(0, 10).toStringAsFixed(1)} '
                  '(hoặc cao hơn điểm cũ 0.5). Kiểm tra quy chế học cải thiện '
                  'của khoá mình trước khi đăng ký — FAP tính lần qua môn mới '
                  'nhất vào GPA.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _headline(GoalPlan plan) {
    final target = plan.target.toStringAsFixed(1);
    final required = plan.requiredAverage;
    return switch (plan.status) {
      GoalStatus.secured =>
        'Đã nắm chắc mục tiêu $target: các môn còn lại chỉ cần qua môn.',
      GoalStatus.onTrack =>
        'Đúng hướng: giữ trung bình ${required!.toStringAsFixed(2)} (thấp hơn '
            'GPA hiện tại) cho ${plan.remainingCredits} tín chỉ còn lại là đạt $target.',
      GoalStatus.stretch =>
        'Cần cố hơn: các môn còn lại phải đạt trung bình '
            '${required!.toStringAsFixed(2)} — cao hơn GPA hiện tại '
            '${plan.currentGpa.toStringAsFixed(2)}. Học cải thiện vài môn sẽ '
            'giảm áp lực này.',
      GoalStatus.needsRetake =>
        required == null
            ? 'Đã hết môn phải học mà GPA mới ${plan.currentGpa.toStringAsFixed(2)}: '
                  'chỉ học cải thiện mới đạt $target.'
            : 'Kể cả đạt 10 mọi môn còn lại, GPA tối đa chỉ '
                  '${plan.maxReachableGpa.toStringAsFixed(2)} — phải học cải thiện '
                  'mới đạt $target.',
    };
  }

  Widget _progress(GoalPlan plan) {
    final ratio = plan.totalCredits == 0
        ? 0.0
        : plan.countedCredits / plan.totalCredits;
    return Row(
      children: [
        Text(
          'Tiến trình',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 9,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${plan.countedCredits}/${plan.totalCredits} tín chỉ tính GPA '
          '(${(ratio * 100).round()}%)',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final String hint;

  const _Figure({required this.label, required this.value, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
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

class _RetakeRow extends StatelessWidget {
  final RetakeSuggestion suggestion;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _RetakeRow({
    required this.suggestion,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final r = suggestion;
    return InkWell(
      onTap: () => onChanged(!selected),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => onChanged(v ?? false),
            ),
            SizedBox(
              width: 86,
              child: Text(
                r.code,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                r.name.replaceAll('_', ' — '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            for (final reason in r.reasons)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.obsidianActive,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    reason,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: Text(
                '${r.currentGrade.toStringAsFixed(1)} → ${r.assumedGrade.toStringAsFixed(1)}',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
              ),
            ),
            SizedBox(
              width: 78,
              child: Text(
                '+${r.gainNow.toStringAsFixed(2)} GPA',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.statusGoodText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
