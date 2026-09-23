import 'package:flutter/material.dart';

import '../../services/obsidian_service.dart';
import '../../utils/app_colors.dart';

/// Người dùng đã chốt gì trên hộp thoại: nạp kế hoạch nào, vào tệp môn học nào.
class VaultImportDecision {
  final VaultSyncPlan plan;
  final VaultImportTarget target;

  const VaultImportDecision({required this.plan, required this.target});
}

enum _TargetMode { create, existing, none }

/// Xem trước thay đổi trước khi nạp Vault vào SQLite.
///
/// `planImport()` chỉ đọc đĩa và so với cơ sở dữ liệu, chưa ghi gì. Hộp thoại
/// này bày nguyên kế hoạch đó ra để người dùng quyết định, nhất là nhóm "gỡ
/// liên kết" — thứ phát sinh khi ai đó xoá một `[[...]]` khỏi file `.md`, và
/// là thao tác duy nhất trong luồng nhập có thể làm mất dữ liệu.
///
/// Hai ô điều khiển ở đầu hộp thoại trả lời đúng hai câu hỏi khiến lần nạp
/// trước "gộp hết vào một chỗ":
///  * **Phạm vi** — quét cả Vault hay chỉ một thư mục con (một lượt quét).
///  * **Tệp môn học** — các môn vừa nạp xếp vào nhóm nào trên thanh bên.
class VaultImportPlanDialog extends StatefulWidget {
  final VaultSyncPlan initialPlan;

  /// Các thư mục con chọn được làm phạm vi quét.
  final List<VaultFolderOption> folders;

  /// Các tệp môn học đã có: cần `id`, `code`, `name`, `course_count`.
  final List<Map<String, dynamic>> curriculums;

  /// Quét lại khi người dùng đổi phạm vi.
  final Future<VaultSyncPlan> Function(String subFolder) onReplan;

  /// Chọn sẵn một tệp môn học — dùng khi mở hộp thoại từ menu chuột phải của
  /// chính tệp đó ("Nạp thêm từ Vault vào tệp này").
  final int? preselectedCurriculumId;

  const VaultImportPlanDialog({
    super.key,
    required this.initialPlan,
    this.folders = const [],
    this.curriculums = const [],
    required this.onReplan,
    this.preselectedCurriculumId,
  });

  static Future<VaultImportDecision?> show(
    BuildContext context, {
    required VaultSyncPlan initialPlan,
    List<VaultFolderOption> folders = const [],
    List<Map<String, dynamic>> curriculums = const [],
    required Future<VaultSyncPlan> Function(String subFolder) onReplan,
    int? preselectedCurriculumId,
  }) {
    return showDialog<VaultImportDecision>(
      context: context,
      builder: (_) => VaultImportPlanDialog(
        initialPlan: initialPlan,
        folders: folders,
        curriculums: curriculums,
        onReplan: onReplan,
        preselectedCurriculumId: preselectedCurriculumId,
      ),
    );
  }

  @override
  State<VaultImportPlanDialog> createState() => _VaultImportPlanDialogState();
}

class _VaultImportPlanDialogState extends State<VaultImportPlanDialog> {
  late VaultSyncPlan _plan;
  late String _subFolder;
  late final TextEditingController _codeCtrl;

  _TargetMode _mode = _TargetMode.create;
  int? _existingId;
  bool _replanning = false;

  /// Lỗi của lần quét lại gần nhất, hiện ngay dưới ô phạm vi.
  String? _scanError;

  /// Cho phép kỳ trong file `.md` ghi đè kỳ môn đang có trong tệp đích.
  bool _overwriteTerms = false;

  /// Người dùng đã tự gõ mã thì thôi ghi đè bằng gợi ý khi đổi phạm vi.
  bool _codeTouched = false;

  @override
  void initState() {
    super.initState();
    _plan = widget.initialPlan;
    _subFolder = widget.initialPlan.subFolder;
    _codeCtrl = TextEditingController(text: _suggestedCode());

    // Mở từ menu chuột phải của một tệp thì tệp đó là đích hiển nhiên.
    if (widget.preselectedCurriculumId != null) {
      _mode = _TargetMode.existing;
      _existingId = widget.preselectedCurriculumId;
      return;
    }

    // Vault đã từng nạp và các file tự khai đúng một tệp đã có -> chọn sẵn tệp
    // đó, để nạp lại không đẻ ra tệp trùng tên.
    final detected = _plan.detectedCurriculumCodes.firstOrNull;
    if (detected != null) {
      final match = _findCurriculumByCode(detected);
      if (match != null) {
        _mode = _TargetMode.existing;
        _existingId = match['id'] as int?;
      }
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _findCurriculumByCode(String code) {
    final wanted = code.trim().toUpperCase();
    for (final c in widget.curriculums) {
      if ((c['code'] as String? ?? '').trim().toUpperCase() == wanted) return c;
    }
    return null;
  }

  /// Gợi ý mã tệp: ưu tiên front matter `curriculum:` các file tự khai, sau đó
  /// là tên thư mục đang quét, cuối cùng là tên thư mục Vault.
  String _suggestedCode() {
    final detected = _plan.detectedCurriculumCodes.firstOrNull;
    if (detected != null && detected.isNotEmpty) return detected;

    final source = _subFolder.isNotEmpty
        ? _subFolder.split(RegExp(r'[\\/]')).last
        : _plan.vaultPath
                  .split(RegExp(r'[\\/]'))
                  .where((e) => e.isNotEmpty)
                  .lastOrNull ??
              '';
    return _sanitizeCode(source);
  }

  static String _sanitizeCode(String raw) => raw
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  Future<void> _changeScope(String? folder) async {
    final next = folder ?? '';
    final previous = _subFolder;
    if (next == previous || _replanning) return;
    setState(() {
      _replanning = true;
      _subFolder = next;
      _scanError = null;
    });
    try {
      final plan = await widget.onReplan(next);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _replanning = false;
        if (!_codeTouched) _codeCtrl.text = _suggestedCode();
      });
    } catch (e) {
      // Quét hỏng (thư mục vừa bị đổi tên...) thì phải trả ô phạm vi về chỗ
      // cũ và nói rõ ra. Giữ nguyên nhãn thư mục mới trong khi `_plan` vẫn là
      // kế hoạch cũ là cách chắc chắn khiến người dùng bấm "Nạp vào CSDL" rồi
      // nuốt trọn cả Vault mà tưởng chỉ nạp một thư mục.
      if (!mounted) return;
      setState(() {
        _subFolder = previous;
        _replanning = false;
        _scanError = e.toString();
      });
    }
  }

  VaultImportTarget? _buildTarget() {
    switch (_mode) {
      case _TargetMode.none:
        return const VaultImportTarget.unassigned();
      case _TargetMode.existing:
        final id = _existingId;
        return id == null
            ? null
            : VaultImportTarget.existing(id, overwriteTerms: _overwriteTerms);
      case _TargetMode.create:
        final code = _sanitizeCode(_codeCtrl.text);
        return code.isEmpty
            ? null
            : VaultImportTarget.create(code, overwriteTerms: _overwriteTerms);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _buildTarget();

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _plan.hasRemovals
                ? Icons.warning_amber_rounded
                : Icons.download_outlined,
            size: 22,
            color: _plan.hasRemovals ? AppColors.warning : AppColors.primary,
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
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _scopePicker(),
              if (_scanError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 14,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Không quét được thư mục đó, giữ nguyên phạm vi cũ: '
                          '$_scanError',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              _targetPicker(),
              const Divider(height: 26),
              if (_replanning)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              Text(
                _plan.summary,
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
                items: [for (final n in _plan.toCreate) n.code],
              ),
              _Group(
                icon: Icons.edit_outlined,
                color: AppColors.info,
                title: 'Môn cập nhật',
                items: [
                  for (final n in _plan.toUpdate)
                    (_plan.changeDetails[n.code]?.isNotEmpty ?? false)
                        ? '${n.code}: ${_plan.changeDetails[n.code]!.join(', ')}'
                        : n.code,
                ],
              ),
              _Group(
                icon: Icons.link,
                color: AppColors.success,
                title: 'Liên kết thêm',
                items: [for (final e in _plan.edgesToAdd) e.toString()],
              ),
              _Group(
                icon: Icons.link_off,
                color: AppColors.error,
                title: 'Liên kết bị gỡ',
                note: 'Phát sinh khi [[...]] đã bị xoá khỏi file .md.',
                items: [for (final e in _plan.edgesToRemove) e.toString()],
              ),
              _Group(
                icon: Icons.help_outline,
                color: AppColors.warning,
                title: 'Liên kết gãy',
                note: 'Trỏ tới file không tồn tại trong Vault, sẽ bỏ qua.',
                items: _plan.brokenLinks,
              ),
              _Group(
                icon: Icons.warning_amber_outlined,
                color: AppColors.warning,
                title: 'Cảnh báo khi quét',
                note: 'File bị bỏ qua hoặc nhiều file trùng mã môn.',
                items: _plan.warnings,
              ),
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
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Nạp vào CSDL'),
          onPressed: _replanning || target == null
              ? null
              : () => Navigator.pop(
                  context,
                  VaultImportDecision(plan: _plan, target: target),
                ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------

  Widget _scopePicker() {
    final folders = widget.folders.isEmpty
        ? [VaultFolderOption(relativePath: '', mdCount: _plan.notes.length)]
        : widget.folders;
    final hasValue = folders.any((f) => f.relativePath == _subFolder);

    return _Field(
      icon: Icons.folder_outlined,
      label: 'Phạm vi quét',
      hint:
          'Chọn đúng thư mục của một lượt quét để không nạp nhầm mọi ghi '
          'chú cá nhân đang nằm trong Vault.',
      // Cố tình dùng DropdownButton chứ không phải DropdownButtonFormField:
      // bản FormField chỉ đọc `initialValue` lúc dựng, nên khi code tự kéo
      // `_subFolder` về giá trị cũ (quét lỗi) thì ô vẫn hiện lựa chọn hỏng —
      // đúng cái bẫy khiến người dùng tưởng đang nạp một thư mục con mà thật
      // ra nạp cả Vault. `DropdownButton.value` thì bám theo state thật.
      child: InputDecorator(
        decoration: _denseDecoration(),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: hasValue ? _subFolder : '',
            isExpanded: true,
            isDense: true,
            style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
            items: [
              for (final f in folders)
                DropdownMenuItem(
                  value: f.relativePath,
                  child: Text(
                    '${f.label}  ·  ${f.mdCount} file .md',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
            ],
            onChanged: _replanning ? null : _changeScope,
          ),
        ),
      ),
    );
  }

  Widget _targetPicker() {
    return _Field(
      icon: Icons.snippet_folder_outlined,
      label: 'Nạp vào tệp môn học',
      hint:
          'Mỗi khung chương trình là một tệp riêng trên thanh bên, sửa được '
          'độc lập. Nạp khung khác vào tệp khác thì hai bên không đè nhau.',
      child: RadioGroup<_TargetMode>(
        groupValue: _mode,
        onChanged: (v) => setState(() => _mode = v ?? _mode),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _radio(
              _TargetMode.create,
              'Tạo tệp môn học mới',
              trailing: SizedBox(
                height: 34,
                child: TextField(
                  controller: _codeCtrl,
                  enabled: _mode == _TargetMode.create,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  decoration: _denseDecoration(hint: 'VD: BIT_SE_K19B'),
                  onChanged: (_) => setState(() => _codeTouched = true),
                ),
              ),
            ),
            _radio(
              _TargetMode.existing,
              'Thêm vào tệp đã có',
              enabled: widget.curriculums.isNotEmpty,
              trailing: SizedBox(
                height: 34,
                child: DropdownButtonFormField<int>(
                  initialValue: _existingId,
                  isExpanded: true,
                  decoration: _denseDecoration(),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textPrimary,
                  ),
                  hint: Text(
                    widget.curriculums.isEmpty
                        ? 'Chưa có tệp nào'
                        : 'Chọn tệp môn học',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  items: [
                    for (final c in widget.curriculums)
                      DropdownMenuItem(
                        value: c['id'] as int,
                        child: Text(
                          '${c['code']}  ·  ${c['course_count'] ?? 0} môn',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                  ],
                  onChanged: _mode == _TargetMode.existing
                      ? (v) => setState(() => _existingId = v)
                      : null,
                ),
              ),
            ),
            _radio(
              _TargetMode.none,
              'Không xếp vào tệp nào (để ở "Môn ngoài khung")',
            ),
            if (_mode != _TargetMode.none)
              CheckboxListTile(
                value: _overwriteTerms,
                dense: true,
                contentPadding: const EdgeInsets.only(left: 6),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Lấy kỳ trong file .md ghi đè kỳ đang có',
                  style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                ),
                subtitle: Text(
                  'Bỏ trống thì môn đã nằm trong tệp giữ nguyên kỳ bạn tự sửa '
                  'bằng "Đổi kỳ…"; chỉ môn mới lấy kỳ từ file.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: AppColors.textSecondary,
                  ),
                ),
                onChanged: (v) => setState(() => _overwriteTerms = v ?? false),
              ),
          ],
        ),
      ),
    );
  }

  Widget _radio(
    _TargetMode mode,
    String label, {
    Widget? trailing,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Radio<_TargetMode>(
              value: mode,
              enabled: enabled,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          Expanded(
            flex: trailing == null ? 1 : 5,
            child: GestureDetector(
              onTap: enabled ? () => setState(() => _mode = mode) : null,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: _mode == mode ? FontWeight.w600 : FontWeight.w400,
                  color: enabled
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            Expanded(flex: 4, child: trailing),
          ],
        ],
      ),
    );
  }

  InputDecoration _denseDecoration({String? hint}) => InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(fontSize: 12.5, color: AppColors.textHint),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
  );
}

/// Một ô điều khiển có nhãn + chú thích ngắn.
class _Field extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final Widget child;

  const _Field({
    required this.icon,
    required this.label,
    required this.hint,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        child,
        const SizedBox(height: 4),
        Text(
          hint,
          style: TextStyle(
            fontSize: 11,
            height: 1.35,
            color: AppColors.textSecondary,
          ),
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
              for (final item in items.take(60))
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
              if (items.length > 60)
                Text(
                  '… và ${items.length - 60} mục nữa',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
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
