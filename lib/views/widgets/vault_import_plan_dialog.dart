import 'package:flutter/material.dart';

import '../../services/obsidian_service.dart';
import '../../utils/app_colors.dart';

/// Xem trước thay đổi trước khi nạp Vault vào SQLite.
///
/// `planImport()` chỉ đọc đĩa và so với cơ sở dữ liệu, chưa ghi gì. Hộp thoại
/// này bày nguyên kế hoạch đó ra để người dùng quyết định, nhất là nhóm "gỡ
/// liên kết" — thứ phát sinh khi ai đó xoá một `[[...]]` khỏi file `.md`, và
/// là thao tác duy nhất trong luồng nhập có thể làm mất dữ liệu.
///
/// Trả về `true` khi người dùng đồng ý ghi xuống.
class VaultImportPlanDialog extends StatelessWidget {
  final VaultSyncPlan plan;

  const VaultImportPlanDialog({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            plan.hasRemovals
                ? Icons.warning_amber_rounded
                : Icons.download_outlined,
            size: 22,
            color: plan.hasRemovals ? AppColors.warning : AppColors.primary,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Nạp dữ liệu từ Vault',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                plan.summary,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              _Group(
                icon: Icons.add_circle_outline,
                color: AppColors.success,
                title: 'Môn thêm mới',
                items: [for (final n in plan.toCreate) n.code],
              ),
              _Group(
                icon: Icons.edit_outlined,
                color: AppColors.info,
                title: 'Môn cập nhật',
                items: [for (final n in plan.toUpdate) n.code],
              ),
              _Group(
                icon: Icons.link,
                color: AppColors.success,
                title: 'Liên kết thêm',
                items: [for (final e in plan.edgesToAdd) e.toString()],
              ),
              _Group(
                icon: Icons.link_off,
                color: AppColors.error,
                title: 'Liên kết bị gỡ',
                note: 'Phát sinh khi [[...]] đã bị xoá khỏi file .md.',
                items: [for (final e in plan.edgesToRemove) e.toString()],
              ),
              _Group(
                icon: Icons.help_outline,
                color: AppColors.warning,
                title: 'Liên kết gãy',
                note: 'Trỏ tới file không tồn tại trong Vault, sẽ bỏ qua.',
                items: plan.brokenLinks,
              ),
              _Group(
                icon: Icons.folder_off_outlined,
                color: AppColors.textSecondary,
                title: 'Có trong CSDL nhưng không còn file .md',
                note: 'Chỉ báo để biết, app không bao giờ tự xoá nhóm này.',
                items: [for (final s in plan.missingInVault) s.code],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Huỷ'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Nạp vào CSDL'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

/// Một nhóm thay đổi. Nhóm rỗng thì không chiếm chỗ.
class _Group extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? note;
  final List<String> items;

  const _Group({
    required this.icon,
    required this.color,
    required this.title,
    required this.items,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

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
                  '$title (${items.length})',
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
              for (final item in items)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(
                      alpha: AppColors.isDark ? 0.16 : 0.10,
                    ),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
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
