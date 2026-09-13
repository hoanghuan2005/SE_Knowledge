import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/subject.dart';
import '../../services/obsidian_launcher.dart';
import '../../services/obsidian_service.dart';
import '../../services/subject_delete_guard.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';
import '../subjects/subject_form_dialog.dart';
import 'subject_chat_panel.dart';
import 'subject_delete_dialog.dart';

/// Bảng bên phải: mặc định mở ngay khung "Hỏi AI" cho môn vừa chọn (đọc nội
/// dung .md và tự đề xuất câu hỏi), tab "Chi tiết" bên cạnh giữ nguyên thông
/// tin môn, tiên quyết và môn mở ra như trước.
class SubjectDetailPanel extends StatefulWidget {
  const SubjectDetailPanel({super.key});

  @override
  State<SubjectDetailPanel> createState() => _SubjectDetailPanelState();
}

class _SubjectDetailPanelState extends State<SubjectDetailPanel> {
  int? _lastSubjectId;

  /// true = tab "Hỏi AI", false = tab "Chi tiết". Mỗi lần người dùng bấm
  /// CHỌN MỘT MÔN KHÁC trên đồ thị, panel tự quay lại tab "Hỏi AI" — đúng ý
  /// "bấm vào node là AI gen câu hỏi ngay", còn chọn lại "Chi tiết" thì giữ
  /// nguyên cho tới khi đổi môn khác.
  bool _showChat = true;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final subject = AppState.instance.selectedSubject;

        if (subject?.id != _lastSubjectId) {
          _lastSubjectId = subject?.id;
          _showChat = true;
        }

        return Container(
          width: 320,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(left: BorderSide(color: AppColors.divider)),
          ),
          child: subject == null
              ? const _NoSelection()
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: _ModeToggle(
                        showChat: _showChat,
                        onChanged: (v) => setState(() => _showChat = v),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    Expanded(
                      child: _showChat
                          ? SubjectChatPanel(
                              key: ValueKey('chat-${subject.id}'),
                              subject: subject,
                            )
                          : _Detail(subject: subject),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final bool showChat;
  final ValueChanged<bool> onChanged;

  const _ModeToggle({required this.showChat, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment<bool>(
            value: true,
            icon: Icon(Icons.auto_awesome, size: 14),
            label: Text('Hỏi AI', style: TextStyle(fontSize: 12)),
          ),
          ButtonSegment<bool>(
            value: false,
            icon: Icon(Icons.info_outline, size: 14),
            label: Text('Chi tiết', style: TextStyle(fontSize: 12)),
          ),
        ],
        selected: {showChat},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _NoSelection extends StatelessWidget {
  const _NoSelection();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: EmptyState(
        icon: Icons.touch_app_outlined,
        title: 'Chưa chọn môn nào',
        message:
            'Bấm vào một node trên đồ thị hoặc một dòng trong danh sách môn '
            'để xem chi tiết và quản lý liên kết tiên quyết.',
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  final Subject subject;

  const _Detail({required this.subject});

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final prereqs = state.prerequisitesOf(subject.id!);
    final unlocks = state.unlockedBy(subject.id!);
    final color = AppColors.forSemester(subject.semester);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                subject.code,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Sửa môn',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => SubjectFormDialog.show(context, subject: subject),
            ),
            IconButton(
              tooltip: 'Xoá môn',
              icon: const Icon(
                Icons.delete_outline,
                size: 20,
                color: AppColors.error,
              ),
              onPressed: () => _confirmDelete(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          subject.name,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Kỳ ${subject.semester}  ·  ${subject.credits} tín chỉ',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        if (subject.description.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            subject.description,
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: AppColors.textPrimary,
            ),
          ),
        ],
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Môn tiên quyết',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => AddEdgeDialog.show(context, subject),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Thêm'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
            ),
          ],
        ),
        if (prereqs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Không có — đây là môn nền tảng.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textHint),
            ),
          )
        else
          for (final p in prereqs)
            _EdgeTile(
              subject: p,
              onRemove: () async {
                try {
                  await AppState.instance.removeEdge(
                    subjectId: subject.id!,
                    prerequisiteId: p.id!,
                  );
                } catch (e) {
                  if (context.mounted) Ui.error(context, e);
                }
              },
              onOpen: () => AppState.instance.select(p.id),
            ),
        const SizedBox(height: 20),
       Padding(
  padding: const EdgeInsets.only(bottom: 4),
  child: Text(
    'Mở ra các môn',
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
  ),
),
        if (unlocks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Chưa có môn nào phụ thuộc vào môn này.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textHint),
            ),
          )
        else
          for (final u in unlocks)
            _EdgeTile(subject: u, onOpen: () => AppState.instance.select(u.id)),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),
        _NoteSection(subject: subject),
      ],
    );
  }

  /// Phân tích ràng buộc trước, rồi mới hỏi. Không dùng hộp thoại xác nhận
  /// chung nữa vì nó luôn hiện đúng một câu, bất kể môn đang bị bao nhiêu môn
  /// khác phụ thuộc — đúng chỗ dễ bẻ gãy đồ thị mà người dùng không hay biết.
  Future<void> _confirmDelete(BuildContext context) async {
    final DeleteImpact impact;
    try {
      impact = await AppState.instance.analyzeDelete(subject.id!);
    } catch (e) {
      if (context.mounted) Ui.error(context, e);
      return;
    }
    if (!context.mounted) return;

    final choice = await showDialog<SubjectDeleteChoice>(
      context: context,
      builder: (_) => SubjectDeleteDialog(impact: impact),
    );
    if (choice == null || !context.mounted) return;

    try {
      final result = await AppState.instance.deleteSubjectSafely(
        impact,
        strategy: choice.strategy,
        deleteNoteFile: choice.deleteNoteFile,
      );
      if (!context.mounted) return;
      // Xoá đã xong dù có cảnh báo, nên báo thành công rồi nối cảnh báo vào
      // sau thay vì hiện báo lỗi làm người dùng tưởng thao tác thất bại.
      if (result.warnings.isEmpty) {
        Ui.success(context, result.summary);
      } else {
        Ui.toast(context, '${result.summary} ${result.warnings.join(' ')}');
      }
    } catch (e) {
      if (context.mounted) Ui.error(context, e);
    }
  }
}

class _EdgeTile extends StatelessWidget {
  final Subject subject;
  final VoidCallback? onRemove;
  final VoidCallback? onOpen;

  const _EdgeTile({required this.subject, this.onRemove, this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.forSemester(subject.semester),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject.code,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        subject.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Bỏ liên kết',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.link_off, size: 16),
                    onPressed: onRemove,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteSection extends StatelessWidget {
  final Subject subject;

  const _NoteSection({required this.subject});

  /// Mở file `.md` của môn này bằng app Obsidian ngoài.
  ///
  /// Khác hẳn nút "Mở ghi chú Obsidian (.md)" phía trên — nút đó mở trình
  /// soạn thảo NGAY TRONG app qua `openNoteTab`.
  Future<void> _openInObsidian(BuildContext context) async {
    final state = AppState.instance;
    final notePath = subject.notePath!;

    // File có thể đã bị xoá/đổi tên ngoài app, lúc đó Obsidian mở ra tab
    // trống chứ không báo gì — chặn trước cho rõ nguyên nhân.
    if (!await File(notePath).exists()) {
      if (!context.mounted) return;
      Ui.error(
        context,
        'Không thấy file $notePath nữa. Bấm "Xuất lại file .md" trước đã.',
      );
      return;
    }

    final ok = await ObsidianLauncher.openNote(
      vaultPath: state.vaultPath!,
      notePath: notePath,
    );
    if (ok || !context.mounted) return;

    Ui.error(
      context,
      'Không mở được bằng Obsidian. Thường do một trong hai: máy chưa cài '
      'Obsidian, hoặc thư mục Vault này chưa từng được mở như một Vault '
      'trong Obsidian. Cũng có thể file nằm ngoài Vault đang chọn — thử '
      '"Xuất lại file .md".',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final hasNote = (subject.notePath ?? '').isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ghi chú Obsidian',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hasNote ? subject.notePath! : 'Chưa xuất ra file .md nào.',
          style: TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 36,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.edit_note, size: 18),
            label: const Text(
              'Mở ghi chú Obsidian (.md)',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => AppState.instance.openNoteTab(subject),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 32,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.save_alt, size: 15),
            label: const Text('Xuất lại file .md', style: TextStyle(fontSize: 11.5)),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: !state.hasVault
                ? null
                : () async {
                    try {
                      final path = await ObsidianService.instance.exportSubject(
                        vaultPath: state.vaultPath!,
                        subject: subject,
                      );
                      await state.refresh();
                      if (context.mounted) {
                        Ui.success(context, 'Đã ghi $path');
                      }
                    } catch (e) {
                      if (context.mounted) Ui.error(context, e);
                    }
                  },
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 32,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.launch, size: 15),
            label: const Text(
              'Mở trong Obsidian',
              style: TextStyle(fontSize: 11.5),
            ),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: !state.hasVault || !hasNote
                ? null
                : () => _openInObsidian(context),
          ),
        ),
        if (!state.hasVault)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Chọn thư mục Vault ở tab Vault để bật chức năng này.',
              style: TextStyle(fontSize: 11, color: AppColors.textHint),
            ),
          ),
      ],
    );
  }
}
