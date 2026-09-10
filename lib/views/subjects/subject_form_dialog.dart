import 'package:flutter/material.dart';

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
      } else {
        await AppState.instance.addSubject(
          Subject.create(
            code: _code.text,
            name: _name.text,
            semester: _semester,
            credits: _credits,
            description: _description.text.trim(),
          ),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      Ui.error(context, e);
    }
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
                    if (!mounted) return;
                    Navigator.pop(context, true);
                  } catch (e) {
                    if (!mounted) return;
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
