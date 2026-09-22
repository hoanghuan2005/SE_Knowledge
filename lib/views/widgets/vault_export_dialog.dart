import 'package:flutter/material.dart';

import '../../models/curriculum.dart';
import '../../models/subject.dart';
import '../../services/obsidian_service.dart';
import '../../utils/app_colors.dart';

/// Người dùng đã chốt gì trên hộp thoại: ghi những môn nào, vào thư mục nào,
/// có kèm `_INDEX.md`, có dời file cũ sang thư mục đó không.
class VaultExportDecision {
  final List<Subject> subjects;
  final bool writeIndex;

  /// Thư mục con trong Vault để ghi vào. Rỗng = ghi thẳng ra gốc Vault.
  final String subFolder;

  /// Dời các file `.md` cũ đang nằm ngoài [subFolder] vào đó.
  final bool moveExisting;

  const VaultExportDecision({
    required this.subjects,
    this.writeIndex = false,
    this.subFolder = '',
    this.moveExisting = true,
  });
}

/// Phạm vi chọn nhanh. Chỉ là nút bấm đặt sẵn ô tích — nguồn sự thật vẫn là
/// cây bên dưới, nên vừa bấm xong vẫn sửa tay tiếp được.
enum _Scope { all, curriculum, manual }

/// Chọn phạm vi trước khi ghi đồ thị ra Vault.
///
/// Trước đây nút "Ghi ra Vault" chỉ hỏi Có/Không rồi đổ **toàn bộ** CSDL ra
/// đĩa. Với một Vault có vài trăm môn thuộc nhiều khung, đó gần như luôn là
/// nhiều hơn thứ người dùng muốn.
///
/// Hộp thoại soi gương [VaultImportPlanDialog] ở chiều ngược lại: chọn phạm
/// vi ở trên, xem trước hệ quả ở dưới, rồi mới ghi.
///
/// Chọn theo **kỳ luôn nằm trong một tệp môn học** chứ không có bộ lọc "mọi
/// môn kỳ 3" toàn cục: một môn nằm trong hai tệp với hai kỳ khác nhau thì
/// "kỳ 3" không có nghĩa xác định.
class VaultExportDialog extends StatefulWidget {
  final VaultExportPreview preview;

  /// Cây tệp môn học -> kỳ -> môn, lấy từ `AppState.curriculumGroups`.
  final List<CurriculumGroup> groups;

  /// Xin ảnh chụp mới khi người dùng đổi thư mục đích.
  ///
  /// Đường dẫn đích và tập "file đã tồn tại" đều phụ thuộc thư mục, nên đổi
  /// thư mục mà không hỏi lại đĩa thì mọi con số dưới đây thành lời nói dối.
  /// `null` (dùng trong kiểm thử) thì nút chọn thư mục bị khoá.
  final Future<VaultExportPreview> Function(String subFolder)? onFolderChanged;

  /// Mở hộp thoại chọn thư mục của hệ điều hành, trả về đường dẫn tuyệt đối.
  ///
  /// Tiêm từ ngoài vào thay vì gọi thẳng `file_selector` ở đây: hộp thoại hệ
  /// điều hành không dựng được trong widget test.
  final Future<String?> Function()? onPickFolder;

  /// Đổi đường dẫn tuyệt đối vừa chọn thành thư mục con của Vault, `null` nếu
  /// nó nằm ngoài Vault.
  final String? Function(String absolute)? toSubFolder;

  const VaultExportDialog({
    super.key,
    required this.preview,
    required this.groups,
    this.onFolderChanged,
    this.onPickFolder,
    this.toSubFolder,
  });

  static Future<VaultExportDecision?> show(
    BuildContext context, {
    required VaultExportPreview preview,
    required List<CurriculumGroup> groups,
    Future<VaultExportPreview> Function(String subFolder)? onFolderChanged,
    Future<String?> Function()? onPickFolder,
    String? Function(String absolute)? toSubFolder,
  }) {
    return showDialog<VaultExportDecision>(
      context: context,
      builder: (_) => VaultExportDialog(
        preview: preview,
        groups: groups,
        onFolderChanged: onFolderChanged,
        onPickFolder: onPickFolder,
        toSubFolder: toSubFolder,
      ),
    );
  }

  @override
  State<VaultExportDialog> createState() => _VaultExportDialogState();
}

class _VaultExportDialogState extends State<VaultExportDialog> {
  /// Môn người dùng tích, theo `subject.id`.
  ///
  /// Khoá theo id chứ không theo (tệp, kỳ, môn): một môn dùng chung hai tệp
  /// vẫn chỉ ghi ra đúng một file, nên tích ở đâu cũng là tích cùng một thứ.
  final Set<int> _selected = <int>{};

  final Set<String> _expanded = <String>{};

  _Scope _scope = _Scope.all;
  int? _scopeCurriculumId;
  bool _includePrerequisites = false;
  bool _writeIndex = true;
  bool _moveExisting = true;

  /// Ảnh chụp đang hiển thị. Bắt đầu từ ảnh cha truyền vào, đổi mỗi lần người
  /// dùng chọn thư mục khác.
  late VaultExportPreview _preview;
  bool _refreshing = false;

  /// Người dùng vừa chọn một thư mục nằm ngoài Vault.
  String? _folderError;

  @override
  void initState() {
    super.initState();
    _preview = widget.preview;
    // Ô "Một tệp môn học" trỏ sẵn vào tệp thật đầu tiên, để bấm phát là chạy.
    for (final g in widget.groups) {
      if (!g.isUnassigned) {
        _scopeCurriculumId = g.curriculumId;
        break;
      }
    }
    _applyScope();
    _expanded.addAll(_groupsInScope().map((g) => g.code));
  }

  /// Mở hộp thoại chọn thư mục của hệ điều hành rồi nhận kết quả.
  ///
  /// Chọn ra ngoài Vault thì giữ nguyên thư mục cũ và nói lý do — đổi bừa sang
  /// đường dẫn đó nghĩa là ghi vào chỗ Obsidian không nhìn thấy.
  Future<void> _pickFolder() async {
    final pick = widget.onPickFolder;
    final convert = widget.toSubFolder;
    if (pick == null || convert == null) return;

    final absolute = await pick();
    if (absolute == null || !mounted) return;

    final folder = convert(absolute);
    if (folder == null) {
      setState(() {
        _folderError =
            'Thư mục đó nằm ngoài Vault. Obsidian chỉ thấy file bên trong '
            'Vault, nên phải chọn một thư mục con của "${_preview.vaultPath}".';
      });
      return;
    }
    setState(() => _folderError = null);
    await _refreshPreview(folder);
  }

  Future<void> _refreshPreview(String folder) async {
    final refresh = widget.onFolderChanged;
    if (refresh == null || !mounted) return;
    setState(() => _refreshing = true);
    try {
      final next = await refresh(folder);
      if (!mounted) return;
      setState(() {
        _preview = next;
        _refreshing = false;
      });
    } catch (_) {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // ------------------------------------------------------------------
  // TÍNH TOÁN — tất cả chạy trên bộ nhớ, không hỏi lại đĩa
  // ------------------------------------------------------------------

  List<CurriculumGroup> _groupsInScope() => switch (_scope) {
    _Scope.curriculum =>
      widget.groups.where((g) => g.curriculumId == _scopeCurriculumId).toList(),
    _ => widget.groups,
  };

  Iterable<Subject> _subjectsOf(CurriculumGroup group) =>
      group.semesters.values.expand((list) => list);

  Set<int> _idsOf(Iterable<Subject> subjects) => {
    for (final s in subjects)
      if (s.id != null) s.id!,
  };

  /// Tập môn thật sự sẽ được ghi: phần người dùng tích, cộng các môn tiên
  /// quyết nếu họ bật ô đó.
  Set<int> get _effectiveIds => _includePrerequisites
      ? _preview.withPrerequisites(_selected)
      : _selected;

  int get _addedByPrerequisites => _effectiveIds.length - _selected.length;

  List<Subject> get _effectiveSubjects {
    final ids = _effectiveIds;
    return [
      for (final s in _preview.subjects)
        if (s.id != null && ids.contains(s.id)) s,
    ];
  }

  int get _createdCount => _effectiveIds
      .where((id) => !_preview.existingFileIds.contains(id))
      .length;

  bool get _isEverything =>
      _effectiveIds.length == _preview.subjects.length;

  void _applyScope() {
    _selected.clear();
    for (final group in _groupsInScope()) {
      _selected.addAll(_idsOf(_subjectsOf(group)));
    }
    // Mục lục nói về TOÀN BỘ đồ thị, nên chỉ bật sẵn khi ghi trọn mọi môn.
    _writeIndex = _isEverything;
  }

  /// Mọi lần sửa ô tích đều rơi về "Chọn tay": giữ nhãn phạm vi cũ trong khi
  /// danh sách đã khác đi thì nhãn đó thành lời nói dối.
  void _toggle(Set<int> ids, bool? on) {
    setState(() {
      if (on ?? false) {
        _selected.addAll(ids);
      } else {
        _selected.removeAll(ids);
      }
      _scope = _Scope.manual;
      if (!_isEverything) _writeIndex = false;
    });
  }

  bool? _tristate(Set<int> ids) {
    if (ids.isEmpty) return false;
    final picked = ids.where(_selected.contains).length;
    if (picked == 0) return false;
    return picked == ids.length ? true : null;
  }

  // ------------------------------------------------------------------
  // GIAO DIỆN
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final dangling = _preview.danglingLinks(_effectiveIds);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(
            Icons.upload_file_outlined,
            size: 22,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Ghi ra Vault',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _folderPicker(),
              const Divider(height: 26),
              _scopePicker(),
              const Divider(height: 26),
              _tree(),
              const Divider(height: 26),
              _summary(dangling),
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
          icon: const Icon(Icons.upload_file, size: 18),
          label: const Text('Ghi ra Vault'),
          onPressed: _effectiveIds.isEmpty || _refreshing
              ? null
              : () => Navigator.pop(
                  context,
                  VaultExportDecision(
                    subjects: _effectiveSubjects,
                    writeIndex: _writeIndex,
                    subFolder: _preview.subFolder,
                    moveExisting: _moveExisting,
                  ),
                ),
        ),
      ],
    );
  }

  /// Đổi phạm vi: đặt lại ô tích theo nhóm tương ứng và mở sẵn các tệp trong
  /// nhóm đó. "Chọn tay" giữ nguyên ô tích hiện có làm điểm xuất phát.
  void _pickScope(_Scope scope) {
    setState(() {
      _scope = scope;
      if (scope != _Scope.manual) _applyScope();
      _expanded
        ..clear()
        ..addAll(_groupsInScope().map((g) => g.code));
    });
  }

  /// Ô chọn thư mục đích + hệ quả của nó.
  ///
  /// Vault thường còn chứa cả những file nguồn người dùng tự bỏ vào (trang FAP
  /// thô chẳng hạn). Ghi thẳng ra gốc thì file app sinh ra nằm lẫn với chúng,
  /// không phân biệt được cái nào là ghi chú của mình. Trỏ vào một thư mục
  /// riêng là cách tách hai thứ đó ra.
  Widget _folderPicker() {
    final moves = _preview.movesFor(_effectiveIds);
    final blocked = moves.where((m) => m.blocked).toList();
    final movable = moves.where((m) => !m.blocked).toList();
    final locked =
        widget.onFolderChanged == null ||
        widget.onPickFolder == null ||
        widget.toSubFolder == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Thư mục đích',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.obsidianBorder),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                _preview.subFolder.isEmpty
                    ? Icons.folder_open_outlined
                    : Icons.folder_outlined,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              // Đường dẫn đầy đủ, không phải mỗi tên thư mục: Vault nào cũng có
              // thể có một thư mục trùng tên, biết đủ đường dẫn mới yên tâm ghi.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _preview.subFolder.isEmpty
                          ? 'Gốc Vault'
                          : _preview.subFolder.replaceAll('/', '\\'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      _preview.subFolder.isEmpty
                          ? _preview.vaultPath
                          : '${_preview.vaultPath}\\'
                                '${_preview.subFolder.replaceAll('/', '\\')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_refreshing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                if (_preview.subFolder.isNotEmpty && !locked)
                  IconButton(
                    icon: const Icon(Icons.undo, size: 16),
                    tooltip: 'Về gốc Vault',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() => _folderError = null);
                      _refreshPreview('');
                    },
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.drive_folder_upload_outlined, size: 16),
                  label: const Text('Chọn…'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: locked ? null : _pickFolder,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Chọn một thư mục con của Vault để tách file app sinh ra khỏi những '
          'file bạn tự bỏ vào. Trong hộp thoại có thể tạo thư mục mới.',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
        if (_folderError != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 14, color: AppColors.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _folderError!,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (movable.isNotEmpty) ...[
          const SizedBox(height: 8),
          _check(
            value: _moveExisting,
            onChanged: (v) => setState(() => _moveExisting = v ?? false),
            label:
                'Dời ${movable.length} file .md đã có sang thư mục này',
            note: _moveExisting
                ? 'Ví dụ ${movable.take(3).map((m) => m.code).join(', ')}'
                      '${movable.length > 3 ? '…' : ''}. Ghi chú bạn tự viết đi '
                      'theo file, và app cập nhật lại đường dẫn trong CSDL.'
                : 'Bỏ tích thì file cũ nằm lại chỗ cũ và lần ghi này tạo thêm '
                      'một bản trùng mã ở thư mục mới — Obsidian sẽ resolve '
                      '[[...]] một cách nhập nhằng.',
            noteColor: _moveExisting ? null : AppColors.warning,
          ),
        ],
        if (blocked.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.report_outlined, size: 14, color: AppColors.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${blocked.length} môn không dời được vì thư mục đích đã có '
                  'file trùng tên (${blocked.take(3).map((m) => m.code).join(', ')}'
                  '${blocked.length > 3 ? '…' : ''}). App giữ nguyên cả hai bên '
                  'và ghi vào file trong thư mục đích.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _scopePicker() {
    final named = widget.groups.where((g) => !g.isUnassigned).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Phạm vi',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        RadioGroup<_Scope>(
          groupValue: _scope,
          onChanged: (v) => _pickScope(v ?? _scope),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _radio(
                _Scope.all,
                'Toàn bộ CSDL — ${_preview.subjects.length} môn',
              ),
              Row(
                children: [
                  Expanded(
                    child: _radio(
                      _Scope.curriculum,
                      'Một tệp môn học',
                      enabled: named.isNotEmpty,
                    ),
                  ),
                  if (named.isNotEmpty)
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<int>(
                        initialValue:
                            named.any(
                              (g) => g.curriculumId == _scopeCurriculumId,
                            )
                            ? _scopeCurriculumId
                            : named.first.curriculumId,
                        isDense: true,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textPrimary,
                        ),
                        items: [
                          for (final g in named)
                            DropdownMenuItem(
                              value: g.curriculumId,
                              child: Text('${g.code} (${g.totalSubjects} môn)'),
                            ),
                        ],
                        onChanged: (id) {
                          _scopeCurriculumId = id;
                          _pickScope(_Scope.curriculum);
                        },
                      ),
                    ),
                ],
              ),
              _radio(_Scope.manual, 'Chọn tay trong cây bên dưới'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _radio(_Scope value, String label, {bool enabled = true}) {
    return InkWell(
      onTap: enabled ? () => _pickScope(value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            Radio<_Scope>(
              value: value,
              enabled: enabled,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: enabled
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tree() {
    if (widget.groups.isEmpty) {
      return Text(
        'Chưa có môn nào trong CSDL.',
        style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300),
      child: Scrollbar(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [for (final g in widget.groups) _groupTile(g)],
          ),
        ),
      ),
    );
  }

  Widget _groupTile(CurriculumGroup group) {
    final ids = _idsOf(_subjectsOf(group));
    final open = _expanded.contains(group.code);
    final terms = group.semesters.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Checkbox(
              key: ValueKey('export-group-${group.code}'),
              value: _tristate(ids),
              tristate: true,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => _toggle(ids, _tristate(ids) != true),
            ),
            Flexible(
              child: InkWell(
                onTap: () => setState(() {
                  open
                      ? _expanded.remove(group.code)
                      : _expanded.add(group.code);
                }),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      open ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    Icon(
                      group.isUnassigned
                          ? Icons.folder_off_outlined
                          : Icons.folder_outlined,
                      size: 15,
                      color: group.isUnassigned
                          ? AppColors.textSecondary
                          : AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      group.code,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${group.totalSubjects} môn',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(left: 26, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final term in terms)
                  _termTile(
                    group.code,
                    group.semesters[term] ?? const [],
                    term,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _termTile(String groupCode, List<Subject> subjects, int term) {
    final ids = _idsOf(subjects);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Checkbox(
              key: ValueKey('export-term-$groupCode-$term'),
              value: _tristate(ids),
              tristate: true,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => _toggle(ids, _tristate(ids) != true),
            ),
            // Không có gì để mở/đóng ở cấp kỳ, nên bấm vào nhãn là tích luôn.
            Flexible(
              child: InkWell(
                onTap: () => _toggle(ids, _tristate(ids) != true),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Kỳ $term',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${subjects.length} môn',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 26, top: 2, bottom: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in subjects)
                if (s.id != null) _subjectChip(s),
            ],
          ),
        ),
      ],
    );
  }

  Widget _subjectChip(Subject subject) {
    final id = subject.id!;
    final on = _selected.contains(id);
    // Môn được kéo vào nhờ ô "ghi kèm tiên quyết" — tô nhạt hơn để phân biệt
    // với môn người dùng tự tích.
    final implied = !on && _includePrerequisites && _effectiveIds.contains(id);
    final color = on
        ? AppColors.primary
        : implied
        ? AppColors.success
        : AppColors.textSecondary;

    return InkWell(
      onTap: () => _toggle({id}, !on),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: on || implied
              ? color.withValues(alpha: AppColors.isDark ? 0.16 : 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: color.withValues(alpha: on || implied ? 0.4 : 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              on
                  ? Icons.check_box_outlined
                  : implied
                  ? Icons.add_circle_outline
                  : Icons.check_box_outline_blank,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 5),
            Text(
              subject.code,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(List<String> dangling) {
    final total = _effectiveIds.length;
    final created = _createdCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          total == 0
              ? 'Chưa chọn môn nào.'
              : 'Sẽ ghi $total file .md — tạo mới $created, '
                    'hoà vào ${total - created} file đã có.',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.45,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'File đã có chỉ bị ghi đè ở front matter và hai mục "Môn tiên quyết" '
          '/ "Mở ra các môn"; phần bạn tự viết được giữ nguyên.',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
        if (dangling.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.link_off, size: 14, color: AppColors.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${dangling.length} liên kết [[...]] sẽ trỏ tới file chưa có '
                  'trong Vault (ví dụ ${dangling.take(3).join(', ')}'
                  '${dangling.length > 3 ? '…' : ''}). Obsidian hiện chúng là '
                  'liên kết gãy cho tới khi bạn ghi nốt những môn đó.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        _check(
          value: _includePrerequisites,
          onChanged: (v) => setState(() {
            _includePrerequisites = v ?? false;
            if (!_isEverything) _writeIndex = false;
          }),
          label: _includePrerequisites && _addedByPrerequisites > 0
              ? 'Ghi kèm các môn tiên quyết (+$_addedByPrerequisites môn)'
              : 'Ghi kèm các môn tiên quyết',
          note:
              'Truy ngược hết nhiều bậc, để không còn liên kết tiên quyết '
              'nào trỏ vào khoảng không.',
        ),
        _check(
          value: _writeIndex,
          onChanged: (v) => setState(() => _writeIndex = v ?? false),
          label: 'Cập nhật _INDEX.md',
          note: _isEverything
              ? 'Mục lục liệt kê mọi môn trong CSDL.'
              : 'Cảnh báo: mục lục luôn liệt kê TOÀN BỘ môn trong CSDL, nên nó '
                    'sẽ trỏ tới cả những môn lần này bạn không ghi.',
          noteColor: _isEverything ? null : AppColors.warning,
        ),
      ],
    );
  }

  Widget _check({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String label,
    String? note,
    Color? noteColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: value,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: onChanged,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => onChanged(!value),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (note != null)
                  Text(
                    note,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: noteColor ?? AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
