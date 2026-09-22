import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/curriculum.dart';
import '../../models/subject.dart';
import '../../services/obsidian_launcher.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';
import '../curriculum/curriculum_form_dialog.dart';
import '../subjects/subject_form_dialog.dart';
import '../vault/vault_import_flow.dart';
import 'subject_delete_dialog.dart';
import 'tree_pickers.dart';

/// Chuyển sang một tab khác của khung ứng dụng (0 = Bản đồ, 2 = Vault...).
typedef TreeNavigate = void Function(int tabIndex);

/// Menu chuột phải cho cây "Tệp & môn học" trên thanh bên.
///
/// Ba cấp của cây có ba menu riêng, nhưng dùng chung một bộ khung hiển thị để
/// kiểu dáng đồng nhất với phần còn lại của giao diện Obsidian.
class TreeContextMenu {
  TreeContextMenu._();

  // ------------------------------------------------------------------
  // CẤP 1: TỆP MÔN HỌC (KHUNG CTĐT)
  // ------------------------------------------------------------------

  static Future<void> showForCurriculum(
    BuildContext context, {
    required Offset position,
    required CurriculumGroup group,
    required TreeNavigate onNavigate,
    required VoidCallback onExpandAll,
    required VoidCallback onCollapseAll,
  }) async {
    final state = AppState.instance;
    final subjects = subjectsOfGroup(group);
    final isOther = group.isUnassigned;

    final action = await _show(context, position, [
      _item('open_graph', Icons.hub_outlined, 'Xem trên Bản đồ tri thức'),
      _item('new_subject', Icons.note_add_outlined, 'Tạo môn học mới ở đây'),
      if (!isOther)
        _item(
          'edit',
          Icons.drive_file_rename_outline,
          'Đổi tên / Sửa thông tin',
        ),
      if (isOther)
        _item(
          'group_into',
          Icons.create_new_folder_outlined,
          'Gom tất cả vào một tệp môn học…',
        ),
      const PopupMenuDivider(),
      if (!isOther)
        _item(
          'import_here',
          Icons.download_outlined,
          'Nạp thêm từ Vault vào tệp này',
        ),
      _item('export', Icons.upload_file_outlined, 'Ghi cả tệp ra Vault'),
      _item('copy', Icons.copy_all_outlined, 'Chép danh sách mã môn'),
      const PopupMenuDivider(),
      _item('expand', Icons.unfold_more, 'Mở rộng mọi kỳ'),
      _item('collapse', Icons.unfold_less, 'Thu gọn mọi kỳ'),
      if (!isOther) ...[
        const PopupMenuDivider(),
        _item('delete', Icons.delete_outline, 'Xoá tệp môn học', danger: true),
      ],
    ]);
    if (action == null || !context.mounted) return;

    switch (action) {
      case 'open_graph':
        // Nhóm "ngoài khung" cũng là một mã hợp lệ ('OTHER') trong
        // `curriculumGroups`, nên lọc theo nó cho ra đúng tập môn chưa xếp —
        // truyền null vào đây thì hoá ra hiện cả đồ thị.
        state.setActiveCurriculum(group.code);
        onNavigate(0);

      case 'new_subject':
        await SubjectFormDialog.show(context, curriculumId: group.curriculumId);

      case 'edit':
        await _editCurriculum(context, group);

      case 'group_into':
        await _groupIntoCurriculum(context, subjects);

      case 'import_here':
        await VaultImportFlow.run(
          context,
          preselectedCurriculumId: group.curriculumId,
        );

      case 'export':
        await _exportSubjects(context, subjects, 'tệp "${group.code}"');

      case 'copy':
        await _copyCodes(context, subjects);

      case 'expand':
        onExpandAll();

      case 'collapse':
        onCollapseAll();

      case 'delete':
        await _deleteCurriculum(context, group);
    }
  }

  // ------------------------------------------------------------------
  // CẤP 2: HỌC KỲ
  // ------------------------------------------------------------------

  static Future<void> showForSemester(
    BuildContext context, {
    required Offset position,
    required CurriculumGroup group,
    required int semester,
    required List<Subject> subjects,
    required bool isCollapsed,
    required VoidCallback onToggle,
  }) async {
    final action = await _show(context, position, [
      _item(
        'toggle',
        isCollapsed ? Icons.arrow_drop_down : Icons.arrow_right,
        isCollapsed ? 'Mở rộng kỳ này' : 'Thu gọn kỳ này',
      ),
      _item('new_subject', Icons.note_add_outlined, 'Tạo môn học trong kỳ này'),
      const PopupMenuDivider(),
      _item('set_term', Icons.swap_vert, 'Chuyển cả kỳ sang kỳ khác…'),
      _item(
        'move',
        Icons.drive_file_move_outline,
        'Chuyển cả kỳ sang tệp khác…',
      ),
      _item(
        'extract',
        Icons.create_new_folder_outlined,
        'Tách kỳ này thành tệp mới…',
      ),
      const PopupMenuDivider(),
      _item(
        'export',
        Icons.upload_file_outlined,
        'Ghi các môn trong kỳ ra Vault',
      ),
      _item('copy', Icons.copy_all_outlined, 'Chép danh sách mã môn'),
      if (!group.isUnassigned) ...[
        const PopupMenuDivider(),
        _item('detach', Icons.link_off, 'Gỡ cả kỳ khỏi tệp này', danger: true),
      ],
    ]);
    if (action == null || !context.mounted) return;

    final ids = subjects.map((s) => s.id).whereType<int>().toList();

    switch (action) {
      case 'toggle':
        onToggle();

      case 'new_subject':
        await SubjectFormDialog.show(
          context,
          curriculumId: group.curriculumId,
          initialSemester: semester,
        );

      case 'set_term':
        final term = await PickTermDialog.show(
          context,
          title: 'Chuyển ${subjects.length} môn của kỳ $semester sang kỳ nào?',
          initial: semester,
        );
        if (term == null || !context.mounted) return;
        await AppState.instance.setTermOfSubjects(
          curriculumId: group.curriculumId,
          subjectIds: ids,
          term: term,
        );
        if (context.mounted) {
          Ui.success(context, 'Đã chuyển ${ids.length} môn sang kỳ $term.');
        }

      case 'move':
        await _moveSubjects(context, group, ids);

      case 'extract':
        await _groupIntoCurriculum(
          context,
          subjects,
          fromCurriculumId: group.curriculumId,
          suggested: '${group.code}_K$semester',
        );

      case 'export':
        await _exportSubjects(context, subjects, 'kỳ $semester');

      case 'copy':
        await _copyCodes(context, subjects);

      case 'detach':
        await _detach(context, group, ids, 'kỳ $semester');
    }
  }

  // ------------------------------------------------------------------
  // CẤP 3: MÔN HỌC
  // ------------------------------------------------------------------

  static Future<void> showForSubject(
    BuildContext context, {
    required Offset position,
    required Subject subject,
    required CurriculumGroup group,
    required TreeNavigate onNavigate,
  }) async {
    final state = AppState.instance;

    final action = await _show(context, position, [
      _item('open_note', Icons.description_outlined, 'Mở ghi chú'),
      _item('open_graph', Icons.hub_outlined, 'Xem trên Bản đồ tri thức'),
      const PopupMenuDivider(),
      _item('edit', Icons.edit_outlined, 'Sửa thông tin môn…'),
      _item(
        'add_edge',
        Icons.account_tree_outlined,
        'Thêm liên kết tiên quyết…',
      ),
      _item('set_term', Icons.swap_vert, 'Đổi kỳ…'),
      _item('move', Icons.drive_file_move_outline, 'Chuyển sang tệp khác…'),
      const PopupMenuDivider(),
      _item('export', Icons.upload_file_outlined, 'Ghi ra Vault'),
      if (subject.notePath != null && state.hasVault)
        _item('obsidian', Icons.open_in_new, 'Mở trong Obsidian'),
      _item('copy', Icons.content_copy, 'Chép mã môn'),
      const PopupMenuDivider(),
      if (!group.isUnassigned)
        _item(
          'detach',
          Icons.link_off,
          'Gỡ khỏi tệp "${group.code}"',
          danger: true,
        ),
      _item('delete', Icons.delete_outline, 'Xoá môn khỏi CSDL', danger: true),
    ]);
    if (action == null || !context.mounted) return;

    final id = subject.id;

    switch (action) {
      case 'open_note':
        state.openNoteTab(subject);

      case 'open_graph':
        state.select(subject.id);
        state.setActiveNote(null);
        onNavigate(0);

      case 'edit':
        await SubjectFormDialog.show(context, subject: subject);

      case 'add_edge':
        await AddEdgeDialog.show(context, subject);

      case 'set_term':
        if (id == null) return;
        final term = await PickTermDialog.show(
          context,
          title: 'Chuyển ${subject.code} sang kỳ nào?',
          initial: subject.semester,
        );
        if (term == null || !context.mounted) return;
        await state.setTermOfSubjects(
          curriculumId: group.curriculumId,
          subjectIds: [id],
          term: term,
        );
        if (context.mounted) {
          Ui.success(context, 'Đã chuyển ${subject.code} sang kỳ $term.');
        }

      case 'move':
        if (id == null) return;
        await _moveSubjects(context, group, [id]);

      case 'export':
        await _exportSubjects(context, [subject], subject.code);

      case 'obsidian':
        final ok = await ObsidianLauncher.openNote(
          vaultPath: state.vaultPath!,
          notePath: subject.notePath!,
        );
        if (context.mounted && !ok) {
          Ui.error(context, 'Không mở được ghi chú trong Obsidian.');
        }

      case 'copy':
        await Clipboard.setData(ClipboardData(text: subject.code));
        if (context.mounted) Ui.info(context, 'Đã chép "${subject.code}".');

      case 'detach':
        if (id == null) return;
        await _detach(context, group, [id], subject.code);

      case 'delete':
        await _deleteSubject(context, subject);
    }
  }

  // ------------------------------------------------------------------
  // HÀNH ĐỘNG DÙNG CHUNG
  // ------------------------------------------------------------------

  static Future<void> _editCurriculum(
    BuildContext context,
    CurriculumGroup group,
  ) async {
    final state = AppState.instance;
    final row = state.curriculums.cast<Map<String, dynamic>?>().firstWhere(
      (c) => c?['id'] == group.curriculumId,
      orElse: () => null,
    );
    if (row == null) {
      Ui.error(context, 'Không tìm thấy tệp môn học trong CSDL.');
      return;
    }

    final data = await CurriculumFormDialog.show(context, initialData: row);
    if (data == null || !context.mounted) return;

    try {
      await state.updateCurriculum(
        group.curriculumId!,
        code: data['code']?.toString(),
        name: data['name']?.toString(),
        major: data['major']?.toString(),
        totalCredits: int.tryParse(data['total_credits']?.toString() ?? ''),
        decisionNo: data['decision_no']?.toString(),
        description: data['description']?.toString(),
      );
      if (context.mounted) Ui.success(context, 'Đã cập nhật tệp môn học.');
    } catch (e) {
      if (context.mounted) Ui.error(context, e);
    }
  }

  static Future<void> _deleteCurriculum(
    BuildContext context,
    CurriculumGroup group,
  ) async {
    final id = group.curriculumId;
    if (id == null) return;

    final deleteSubjects = await CurriculumDeleteDialog.show(
      context,
      curriculumCode: group.code,
      curriculumName: group.name,
      totalCourses: group.totalSubjects,
    );
    if (deleteSubjects == null || !context.mounted) return;

    try {
      await AppState.instance.deleteCurriculum(
        id,
        deleteSubjects: deleteSubjects,
      );
      if (context.mounted) {
        Ui.success(
          context,
          deleteSubjects
              ? 'Đã xoá tệp "${group.code}" và các môn chỉ thuộc tệp này.'
              : 'Đã xoá tệp "${group.code}". Các môn chuyển về nhóm ngoài khung.',
        );
      }
    } catch (e) {
      if (context.mounted) Ui.error(context, e);
    }
  }

  /// Tạo (hoặc chọn) một tệp rồi dồn [subjects] vào đó.
  static Future<void> _groupIntoCurriculum(
    BuildContext context,
    List<Subject> subjects, {
    int? fromCurriculumId,
    String suggested = '',
  }) async {
    if (subjects.isEmpty) {
      Ui.info(context, 'Nhóm này chưa có môn nào.');
      return;
    }

    final targetId = await PickCurriculumDialog.show(
      context,
      title: 'Xếp ${subjects.length} môn vào tệp môn học',
      message:
          'Các môn vẫn nằm nguyên trong CSDL, chỉ được gắn thêm vào tệp bạn '
          'chọn để quản lý và chỉnh sửa riêng.',
      excludeId: fromCurriculumId,
      suggestedCode: suggested,
    );
    if (targetId == null || !context.mounted) return;

    try {
      await AppState.instance.moveSubjectsToCurriculum(
        fromCurriculumId: fromCurriculumId,
        toCurriculumId: targetId,
        subjectIds: subjects.map((s) => s.id).whereType<int>().toList(),
      );
      if (context.mounted) {
        Ui.success(context, 'Đã xếp ${subjects.length} môn vào tệp mới.');
      }
    } catch (e) {
      if (context.mounted) Ui.error(context, e);
    }
  }

  static Future<void> _moveSubjects(
    BuildContext context,
    CurriculumGroup group,
    List<int> subjectIds,
  ) async {
    if (subjectIds.isEmpty) return;

    final targetId = await PickCurriculumDialog.show(
      context,
      title: 'Chuyển ${subjectIds.length} môn sang tệp khác',
      message: group.isUnassigned
          ? 'Các môn đang ở nhóm ngoài khung sẽ được gắn vào tệp bạn chọn.'
          : 'Các môn sẽ rời tệp "${group.code}" và sang tệp bạn chọn.',
      excludeId: group.curriculumId,
    );
    if (targetId == null || !context.mounted) return;

    try {
      await AppState.instance.moveSubjectsToCurriculum(
        fromCurriculumId: group.curriculumId,
        toCurriculumId: targetId,
        subjectIds: subjectIds,
      );
      if (context.mounted) {
        Ui.success(context, 'Đã chuyển ${subjectIds.length} môn.');
      }
    } catch (e) {
      if (context.mounted) Ui.error(context, e);
    }
  }

  static Future<void> _detach(
    BuildContext context,
    CurriculumGroup group,
    List<int> subjectIds,
    String label,
  ) async {
    final id = group.curriculumId;
    if (id == null || subjectIds.isEmpty) return;

    final ok = await Ui.confirm(
      context,
      title: 'Gỡ $label khỏi tệp "${group.code}"?',
      message:
          '${subjectIds.length} môn sẽ rời khỏi tệp này và chuyển về nhóm '
          '"Môn ngoài khung". Môn học, ghi chú và các liên kết tiên quyết vẫn '
          'còn nguyên trong CSDL.',
      confirmLabel: 'Gỡ khỏi tệp',
      destructive: true,
    );
    if (!ok || !context.mounted) return;

    try {
      final n = await AppState.instance.removeSubjectsFromCurriculum(
        curriculumId: id,
        subjectIds: subjectIds,
      );
      if (context.mounted) Ui.success(context, 'Đã gỡ $n môn khỏi tệp.');
    } catch (e) {
      if (context.mounted) Ui.error(context, e);
    }
  }

  static Future<void> _deleteSubject(
    BuildContext context,
    Subject subject,
  ) async {
    final id = subject.id;
    if (id == null) return;

    try {
      final impact = await AppState.instance.analyzeDelete(id);
      if (!context.mounted) return;

      final choice = await showDialog<SubjectDeleteChoice>(
        context: context,
        builder: (_) => SubjectDeleteDialog(
          impact: impact,
          transcriptEntryCount: AppState.instance.transcript
              .where((e) => e.subjectCode == impact.target.code.toUpperCase())
              .length,
        ),
      );
      if (choice == null || !context.mounted) return;

      final result = await AppState.instance.deleteSubjectSafely(
        impact,
        strategy: choice.strategy,
        deleteNoteFile: choice.deleteNoteFile,
      );
      if (context.mounted) Ui.success(context, result.summary);
    } catch (e) {
      if (context.mounted) Ui.error(context, e);
    }
  }

  static Future<void> _exportSubjects(
    BuildContext context,
    List<Subject> subjects,
    String label,
  ) async {
    if (!AppState.instance.hasVault) {
      Ui.error(context, 'Chưa chọn thư mục Obsidian Vault.');
      return;
    }
    if (subjects.isEmpty) {
      Ui.info(context, 'Không có môn nào để ghi.');
      return;
    }

    try {
      final n = await AppState.instance.exportSubjectsToVault(subjects);
      if (context.mounted) {
        Ui.success(context, 'Đã ghi $n file .md của $label ra Vault.');
      }
    } catch (e) {
      if (context.mounted) Ui.error(context, e);
    }
  }

  static Future<void> _copyCodes(
    BuildContext context,
    List<Subject> subjects,
  ) async {
    final text = subjects.map((s) => s.code).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      Ui.info(context, 'Đã chép ${subjects.length} mã môn.');
    }
  }

  // ------------------------------------------------------------------
  // KHUNG HIỂN THỊ
  // ------------------------------------------------------------------

  static Future<String?> _show(
    BuildContext context,
    Offset position,
    List<PopupMenuEntry<String>> items,
  ) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final size = overlay?.size ?? MediaQuery.sizeOf(context);

    return showMenu<String>(
      context: context,
      color: AppColors.obsidianSidebar,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.obsidianBorder),
      ),
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        size.width - position.dx,
        size.height - position.dy,
      ),
      items: items,
    );
  }

  static PopupMenuItem<String> _item(
    String value,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    final color = danger ? AppColors.error : AppColors.obsidianText;
    return PopupMenuItem<String>(
      value: value,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
