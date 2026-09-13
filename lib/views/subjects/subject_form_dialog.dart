import 'package:flutter/material.dart';

import '../../models/prerequisite.dart';
import '../../models/subject.dart';
import '../../state/app_state.dart';
import '../../utils/ui_helpers.dart';

/// Hộp thoại thêm mới / sửa một môn học (một NODE của đồ thị).
class SubjectFormDialog extends StatefulWidget {
  /// null = thêm mới.
  final Subject? subject;

  const SubjectFormDialog({super.key, this.subject});

  static Future<bool> show(BuildContext context, {Subject? subject}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => SubjectFormDialog(subject: subject),
    );
    return saved ?? false;
  }

  @override
  State<SubjectFormDialog> createState() => _SubjectFormDialogState();
}

class _SubjectFormDialogState extends State<SubjectFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _description;
  late int _semester;
  late int _credits;
  bool _saving = false;

  /// Id cac mon duoc chon lam tien quyet, dong bo lai voi CSDL luc luu.
  final Set<int> _selectedPrerequisiteIds = <int>{};

  bool get _isEdit => widget.subject != null;

  @override
  void initState() {
    super.initState();
    final s = widget.subject;
    _code = TextEditingController(text: s?.code ?? '');
    _name = TextEditingController(text: s?.name ?? '');
    _description = TextEditingController(text: s?.description ?? '');
    _semester = s?.semester ?? 1;
    _credits = s?.credits ?? 3;
    if (s?.id != null) {
      _selectedPrerequisiteIds.addAll(
        AppState.instance
            .prerequisitesOf(s!.id!)
            .map((e) => e.id)
            .whereType<int>(),
      );
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    try {
      final int subjectId;
      if (_isEdit) {
        await AppState.instance.updateSubject(
          widget.subject!.copyWith(
            code: _code.text.trim().toUpperCase(),
            name: _name.text.trim(),
            semester: _semester,
            credits: _credits,
            description: _description.text.trim(),
          ),
        );
        subjectId = widget.subject!.id!;
      } else {
        subjectId = await AppState.instance.addSubject(
          Subject.create(
            code: _code.text,
            name: _name.text,
            semester: _semester,
            credits: _credits,
            description: _description.text.trim(),
          ),
        );
      }

      final failures = await _syncPrerequisites(subjectId);

      if (!mounted) return;
      // Mon da luu thanh cong roi: canh bao cac canh loi nhung khong chan.
      if (failures.isNotEmpty) {
        Ui.error(
          context,
          'Đã lưu môn, nhưng ${failures.length} liên kết tiên quyết không '
          'áp dụng được: ${failures.join('; ')}',
        );
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      Ui.error(context, e);
    }
  }

  /// Đưa tập tiên quyết trong CSDL về đúng [_selectedPrerequisiteIds].
  ///
  /// Mỗi cạnh được xử lý độc lập: một cạnh hỏng (trùng hoặc tạo chu trình ->
  /// DbConflictException) không làm hỏng các cạnh còn lại. Trả về danh sách mô
  /// tả lỗi để màn hình gọi hiển thị sau khi môn đã lưu xong.
  Future<List<String>> _syncPrerequisites(int subjectId) async {
    // Đọc lại từ state ngay lúc lưu, nên cạnh thêm qua AddEdgeDialog cũng được
    // tính đúng thay vì bị coi là "vừa bỏ chọn".
    final before = _isEdit
        ? AppState.instance
              .prerequisitesOf(subjectId)
              .map((e) => e.id)
              .whereType<int>()
              .toSet()
        : <int>{};
    final after = _selectedPrerequisiteIds;

    final labelOf = {
      for (final s in AppState.instance.graph.subjects)
        if (s.id != null) s.id!: s.code,
    };
    final failures = <String>[];

    for (final id in after.difference(before)) {
      try {
        await AppState.instance.addEdge(
          subjectId: subjectId,
          prerequisiteId: id,
          relationType: Prerequisite.kPrerequisite,
        );
      } catch (e) {
        failures.add('${labelOf[id] ?? id} ($e)');
      }
    }

    for (final id in before.difference(after)) {
      try {
        await AppState.instance.removeEdge(
          subjectId: subjectId,
          prerequisiteId: id,
        );
      } catch (e) {
        failures.add('${labelOf[id] ?? id} ($e)');
      }
    }

    return failures;
  }

  /// Khối chọn nhiều môn tiên quyết ngay trong form chính.
  Widget _buildPrerequisitePicker() {
    final candidates = AppState.instance.graph.subjects
        .where((s) => s.id != null && s.id != widget.subject?.id)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Môn tiên quyết (chọn nhiều)',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        if (candidates.isEmpty)
          const Text('Chưa có môn nào khác để chọn làm tiên quyết.')
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in candidates)
                    FilterChip(
                      label: Text('${s.code} — ${s.name}'),
                      selected: _selectedPrerequisiteIds.contains(s.id),
                      onSelected: _saving
                          ? null
                          : (selected) => setState(() {
                              if (selected) {
                                _selectedPrerequisiteIds.add(s.id!);
                              } else {
                                _selectedPrerequisiteIds.remove(s.id!);
                              }
                            }),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Sửa môn học' : 'Thêm môn học'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Mã môn *',
                    hintText: 'VD: CSD201',
                    helperText: 'Mã môn là khoá UNIQUE, cũng là tên file .md',
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Nhập mã môn'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Tên môn *',
                    hintText: 'VD: Data Structures and Algorithms',
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Nhập tên môn'
                      : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _semester,
                        decoration: const InputDecoration(labelText: 'Kỳ học'),
                        items: [
                          for (var i = 1; i <= 9; i++)
                            DropdownMenuItem(value: i, child: Text('Kỳ $i')),
                        ],
                        onChanged: (v) => setState(() => _semester = v ?? 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _credits,
                        decoration: const InputDecoration(labelText: 'Tín chỉ'),
                        items: [
                          for (var i = 1; i <= 10; i++)
                            DropdownMenuItem(value: i, child: Text('$i tín chỉ')),
                        ],
                        onChanged: (v) => setState(() => _credits = v ?? 3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả ngắn',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                _buildPrerequisitePicker(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Huỷ'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(_isEdit ? 'Lưu' : 'Thêm'),
        ),
      ],
    );
  }
}

/// Hộp thoại chọn một môn để làm tiên quyết cho [subject].
class AddEdgeDialog extends StatefulWidget {
  final Subject subject;

  const AddEdgeDialog({super.key, required this.subject});

  static Future<bool> show(BuildContext context, Subject subject) async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => AddEdgeDialog(subject: subject),
    );
    return added ?? false;
  }

  @override
  State<AddEdgeDialog> createState() => _AddEdgeDialogState();
}

class _AddEdgeDialogState extends State<AddEdgeDialog> {
  int? _prerequisiteId;
  String _relationType = 'PREREQUISITE';
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final existing = state
        .prerequisitesOf(widget.subject.id!)
        .map((s) => s.id)
        .toSet();

    final options = state.graph.subjects
        .where((s) => s.id != widget.subject.id && !existing.contains(s.id))
        .toList();

    return AlertDialog(
      title: Text('Thêm tiên quyết cho ${widget.subject.code}'),
      content: SizedBox(
        width: 420,
        child: options.isEmpty
            ? const Text('Không còn môn nào khả dụng để làm tiên quyết.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: _prerequisiteId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Môn phải học trước',
                    ),
                    items: [
                      for (final s in options)
                        DropdownMenuItem(
                          value: s.id,
                          child: Text(
                            '${s.code} — ${s.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _prerequisiteId = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _relationType,
                    decoration: const InputDecoration(labelText: 'Loại quan hệ'),
                    items: const [
                      DropdownMenuItem(
                        value: 'PREREQUISITE',
                        child: Text('Tiên quyết bắt buộc'),
                      ),
                      DropdownMenuItem(
                        value: 'RELATED',
                        child: Text('Liên quan / tham khảo'),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _relationType = v ?? 'PREREQUISITE'),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Huỷ'),
        ),
        ElevatedButton(
          onPressed: _saving || _prerequisiteId == null
              ? null
              : () async {
                  setState(() => _saving = true);
                  try {
                    await AppState.instance.addEdge(
                      subjectId: widget.subject.id!,
                      prerequisiteId: _prerequisiteId!,
                      relationType: _relationType,
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!context.mounted) return;
                    setState(() => _saving = false);
                    Ui.error(context, e);
                  }
                },
          child: const Text('Thêm liên kết'),
        ),
      ],
    );
  }
}
