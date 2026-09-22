import 'package:flutter/material.dart';

import '../../models/graph_settings.dart';
import '../../utils/app_colors.dart';

/// Bảng điều khiển nổi (Floating Panel) tùy chỉnh Đồ thị tri thức (Graph View).
class GraphSettingsPanel extends StatelessWidget {
  final GraphSettings settings;
  final ValueChanged<GraphSettings> onChanged;
  final VoidCallback onClose;
  final VoidCallback onResimulate;
  final VoidCallback onResetZoom;
  final VoidCallback onResetDefaults;

  const GraphSettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.onClose,
    required this.onResimulate,
    required this.onResetZoom,
    required this.onResetDefaults,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 320,
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          color: (isDark ? const Color(0xFF1E1E24) : Colors.white).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF33333F) : const Color(0xFFD6D4E2),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Header ---
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF262630) : const Color(0xFFF3F2F8),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? const Color(0xFF33333F) : const Color(0xFFE4E2ED),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.tune_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cài đặt đồ thị',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: 'Đóng cài đặt',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: onClose,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // --- Body ---
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Section 1: Kích thước & Hiển thị ---
                      _buildSectionHeader(
                        icon: Icons.aspect_ratio_rounded,
                        title: 'Kích thước & Hiển thị',
                      ),
                      const SizedBox(height: 8),

                      _buildSliderRow(
                        label: 'Độ to node',
                        valueText: '${(settings.nodeScale * 100).round()}%',
                        value: settings.nodeScale,
                        min: 0.6,
                        max: 1.8,
                        onChanged: (v) => onChanged(settings.copyWith(nodeScale: v)),
                      ),

                      _buildSliderRow(
                        label: 'Độ dày liên kết',
                        valueText: '${settings.edgeWidth.toStringAsFixed(1)}px',
                        value: settings.edgeWidth,
                        min: 0.8,
                        max: 3.5,
                        onChanged: (v) => onChanged(settings.copyWith(edgeWidth: v)),
                      ),

                      _buildSwitchRow(
                        label: 'Hiện nhãn kỳ học (K1, K2...)',
                        value: settings.showSemesterBadge,
                        onChanged: (v) => onChanged(settings.copyWith(showSemesterBadge: v)),
                      ),

                      _buildSwitchRow(
                        label: 'Hiện số tín chỉ (TC)',
                        value: settings.showCredits,
                        onChanged: (v) => onChanged(settings.copyWith(showCredits: v)),
                      ),

                      _buildSwitchRow(
                        label: 'Hiện mũi tên liên kết',
                        value: settings.showArrows,
                        onChanged: (v) => onChanged(settings.copyWith(showArrows: v)),
                      ),

                      const SizedBox(height: 6),
                      Text(
                        'Chế độ màu node:',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _buildChoiceChip(
                              label: 'Theo kỳ học',
                              selected: settings.colorMode == 'semester',
                              onTap: () => onChanged(settings.copyWith(colorMode: 'semester')),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildChoiceChip(
                              label: 'Theo kết nối',
                              selected: settings.colorMode == 'degree',
                              onTap: () => onChanged(settings.copyWith(colorMode: 'degree')),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // --- Section 2: Lực & Khoảng cách ---
                      _buildSectionHeader(
                        icon: Icons.grain_rounded,
                        title: 'Lực & Khoảng cách (Physics)',
                      ),
                      const SizedBox(height: 8),

                      _buildSwitchRow(
                        label: 'Mô phỏng vật lý tự động',
                        value: settings.enablePhysics,
                        onChanged: (v) => onChanged(settings.copyWith(enablePhysics: v)),
                      ),

                      _buildSliderRow(
                        label: 'Khoảng cách liên kết',
                        valueText: '${settings.linkDistance.round()}px',
                        value: settings.linkDistance,
                        min: 60.0,
                        max: 300.0,
                        onChanged: (v) => onChanged(settings.copyWith(linkDistance: v)),
                      ),

                      _buildSliderRow(
                        label: 'Lực đẩy phân tán',
                        valueText: '${(settings.repulsionForce / 1000).round()}k',
                        value: settings.repulsionForce,
                        min: 5000.0,
                        max: 60000.0,
                        onChanged: (v) => onChanged(settings.copyWith(repulsionForce: v)),
                      ),

                      _buildSliderRow(
                        label: 'Lực hút về tâm',
                        valueText: (settings.centerGravity * 1000).toStringAsFixed(1),
                        value: settings.centerGravity,
                        min: 0.001,
                        max: 0.020,
                        onChanged: (v) => onChanged(settings.copyWith(centerGravity: v)),
                      ),

                      const SizedBox(height: 16),

                      // --- Section 3: Thao tác nhanh ---
                      _buildSectionHeader(
                        icon: Icons.touch_app_outlined,
                        title: 'Thao tác nhanh',
                      ),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.refresh, size: 14),
                              label: const Text('Xốc đồ thị', style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onPressed: onResimulate,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.center_focus_strong_outlined, size: 14),
                              label: const Text('Căn giữa', style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onPressed: onResetZoom,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          icon: const Icon(Icons.restore, size: 14),
                          label: const Text(
                            'Khôi phục cài đặt mặc định',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                          onPressed: onResetDefaults,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildSliderRow({
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              Text(
                valueText,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.border,
              thumbColor: AppColors.primary,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: AppColors.textPrimary),
          ),
          Transform.scale(
            scale: 0.75,
            child: Switch(
              value: value,
              activeTrackColor: AppColors.primary,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final isDark = AppColors.isDark;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.18)
              : (isDark ? const Color(0xFF282832) : const Color(0xFFF0EFF5)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
