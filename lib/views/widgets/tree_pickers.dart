import 'package:flutter/material.dart';

import '../../models/curriculum.dart';
import '../../models/subject.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';

/// Chọn một tệp môn học (khung CTĐT) đã có, hoặc gõ mã để tạo tệp mới.
///
/// Dùng chung cho "Chuyển sang tệp khác", "Tách thành tệp mới" và "Gom môn
/// ngoài khung vào một tệp". Trả về `curriculums.id` của tệp đích, hoặc `null`
/// khi người dùng huỷ.
class PickCurriculumDialog extends StatefulWidget {
  final String title;
  final String message;

  /// Tệp nguồn — không cho chọn chính nó làm đích.
  final int? excludeId;

  /// Gợi ý sẵn cho ô "tạo tệp mới".
  final String suggestedCode;

  const PickCurriculumDialog({
    super.key,
    required this.title,
    this.message = '',
    this.excludeId,
    this.suggestedCode = '',
  });

  static Future<int?> show(
    BuildContext context, {
    required String title,
    String message = '',
    int? excludeId,
    String suggestedCode = '',
  }) {
    return showDialog<int>(
      context: context,
      builder: (_) => PickCurriculumDialog(
        title: title,
        message: message,
        excludeId: excludeId,
        suggestedCode: suggestedCode,
      ),
    );
  }

  @override
  State<PickCurriculumDialog> createState() => _PickCurriculumDialogState();
}

class _PickCurriculumDialogState extends State<PickCurriculumDialog> {
  late final TextEditingController _code;
  late List<Map<String, dynamic>> _options;
  bool _createNew = false;
  int? _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: widget.suggestedCode);
    _options = AppState.instance.curriculums
        .where((c) => c['id'] != widget.excludeId)
        .toList();
    _createNew = _options.isEmpty;
    _selected = _options.isNotEmpty ? _options.first['id'] as int? : null;
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      final id = _createNew
          ? await AppState.instance.ensureCurriculumByCode(_code.text)
          : _selected;
      if (!mounted) return;
      Navigator.pop(context, id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  bool get _canConfirm =>
      _createNew ? _code.text.trim().isNotEmpty : _selected != null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message.isNotEmpty) ...[
              Text(
                widget.message,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_options.isNotEmpty)
              DropdownButtonFormField<int>(
                initialValue: _selected,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Tệp môn học đích',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in _options)
                    DropdownMenuItem(
                      value: c['id'] as int,
                      child: Text(
                        '${c['code']} · ${c['course_count'] ?? 0} môn',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
                onChanged: _createNew
                    ? null
                    : (v) => setState(() => _selected = v),
              ),
            if (_options.isNotEmpty)
              CheckboxListTile(
                value: _createNew,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Tạo tệp môn học mới thay vì chọn tệp trên',
                  style: TextStyle(fontSize: 12.5),
                ),
                onChanged: (v) => setState(() => _createNew = v ?? false),
              ),
            if (_createNew)
              TextField(
                controller: _code,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Mã tệp môn học mới',
                  hintText: 'VD: BIT_SE_K19B',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        ElevatedButton(
          onPressed: _busy || !_canConfirm ? null : _confirm,
          child: const Text('Xác nhận'),
        ),
      ],
    );
  }
}

/// Chọn số kỳ (1..12). Trả về `null` khi huỷ.
class PickTermDialog extends StatefulWidget {
  final String title;
  final int initial;

  const PickTermDialog({super.key, required this.title, this.initial = 1});

  static Future<int?> show(
    BuildContext context, {
    required String title,
    int initial = 1,
  }) {
    return showDialog<int>(
      context: context,
      builder: (_) => PickTermDialog(title: title, initial: initial),
    );
  }

  @override
  State<PickTermDialog> createState() => _PickTermDialogState();
}

class _PickTermDialogState extends State<PickTermDialog> {
  late int _term = widget.initial.clamp(1, 12);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 320,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 1; i <= 12; i++)
              ChoiceChip(
                label: Text('Kỳ $i'),
                selected: _term == i,
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _term == i ? Colors.white : AppColors.textPrimary,
                ),
                selectedColor: AppColors.forSemester(i),
                onSelected: (_) => setState(() => _term = i),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _term),
          child: const Text('Áp dụng'),
        ),
      ],
    );
  }
}

/// Mọi môn của một nhóm, đã gộp hết các kỳ lại.
List<Subject> subjectsOfGroup(CurriculumGroup group) => [
  for (final list in group.semesters.values) ...list,
];
