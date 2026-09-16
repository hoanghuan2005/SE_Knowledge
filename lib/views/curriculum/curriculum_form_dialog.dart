import 'package:flutter/material.dart';
import '../../utils/app_colors.dart';

/// Hộp thoại Thêm / Chỉnh sửa Khung chương trình đào tạo
class CurriculumFormDialog extends StatefulWidget {
  final Map<String, dynamic>? initialData;

  const CurriculumFormDialog({super.key, this.initialData});

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    Map<String, dynamic>? initialData,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CurriculumFormDialog(initialData: initialData),
    );
  }

  @override
  State<CurriculumFormDialog> createState() => _CurriculumFormDialogState();
}

class _CurriculumFormDialogState extends State<CurriculumFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _majorController;
  late final TextEditingController _creditsController;
  late final TextEditingController _decisionController;
  late final TextEditingController _descController;

  bool get isEditing => widget.initialData != null;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    _codeController = TextEditingController(text: d?['code']?.toString() ?? '');
    _nameController = TextEditingController(text: d?['name']?.toString() ?? '');
    _majorController = TextEditingController(text: d?['major']?.toString() ?? '');
    _creditsController = TextEditingController(
      text: d?['total_credits']?.toString() ?? '145',
    );
    _decisionController = TextEditingController(text: d?['decision_no']?.toString() ?? '');
    _descController = TextEditingController(text: d?['description']?.toString() ?? '');
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _majorController.dispose();
    _creditsController.dispose();
    _decisionController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final credits = int.tryParse(_creditsController.text.trim()) ?? 145;
    Navigator.of(context).pop<Map<String, dynamic>>({
      'code': _codeController.text.trim().toUpperCase(),
      'name': _nameController.text.trim(),
      'major': _majorController.text.trim().isNotEmpty
          ? _majorController.text.trim()
          : _nameController.text.trim(),
      'total_credits': credits,
      'decision_no': _decisionController.text.trim(),
      'description': _descController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.obsidianSidebar,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.obsidianBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.school_outlined, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing ? 'Chỉnh sửa Khung CTĐT' : 'Tạo Khung CTĐT mới',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Khung chương trình đào tạo để nhóm các môn học theo kỳ',
                            style: TextStyle(fontSize: 11, color: AppColors.obsidianTextMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Form fields
                Row(
                  children: [
                    // Mã khung
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        controller: _codeController,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Mã khung *',
                          hintText: 'VD: SE, BIT_SE_K20B',
                          labelStyle: TextStyle(fontSize: 12, color: AppColors.obsidianTextMuted),
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.obsidianWorkspace,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: AppColors.obsidianBorder),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Vui lòng nhập mã khung';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Tổng tín chỉ
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _creditsController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Tổng tín chỉ',
                          hintText: '145',
                          labelStyle: TextStyle(fontSize: 12, color: AppColors.obsidianTextMuted),
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.obsidianWorkspace,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: AppColors.obsidianBorder),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Tên khung CTĐT
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Tên khung / Ngành học *',
                    hintText: 'VD: Kỹ thuật phần mềm (Software Engineering)',
                    labelStyle: TextStyle(fontSize: 12, color: AppColors.obsidianTextMuted),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.obsidianWorkspace,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AppColors.obsidianBorder),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Vui lòng nhập tên khung';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),

                // Chuyên ngành & Số quyết định
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _majorController,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Chuyên ngành',
                          hintText: 'VD: Software Engineering',
                          labelStyle: TextStyle(fontSize: 12, color: AppColors.obsidianTextMuted),
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.obsidianWorkspace,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: AppColors.obsidianBorder),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _decisionController,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Số quyết định',
                          hintText: 'VD: 123/QĐ-ĐHFPT',
                          labelStyle: TextStyle(fontSize: 12, color: AppColors.obsidianTextMuted),
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.obsidianWorkspace,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: AppColors.obsidianBorder),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Mô tả
                TextFormField(
                  controller: _descController,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Mô tả / Ghi chú (tuỳ chọn)',
                    labelStyle: TextStyle(fontSize: 12, color: AppColors.obsidianTextMuted),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.obsidianWorkspace,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AppColors.obsidianBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.obsidianBorder),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Huỷ bỏ', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: Icon(isEditing ? Icons.check : Icons.add, size: 16),
                      label: Text(
                        isEditing ? 'Lưu thay đổi' : 'Tạo khung',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _submit,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hộp thoại xác nhận xoá Khung chương trình đào tạo
class CurriculumDeleteDialog extends StatefulWidget {
  final String curriculumCode;
  final String curriculumName;
  final int totalCourses;

  const CurriculumDeleteDialog({
    super.key,
    required this.curriculumCode,
    required this.curriculumName,
    required this.totalCourses,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String curriculumCode,
    required String curriculumName,
    required int totalCourses,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => CurriculumDeleteDialog(
        curriculumCode: curriculumCode,
        curriculumName: curriculumName,
        totalCourses: totalCourses,
      ),
    );
  }

  @override
  State<CurriculumDeleteDialog> createState() => _CurriculumDeleteDialogState();
}

class _CurriculumDeleteDialogState extends State<CurriculumDeleteDialog> {
  bool _deleteOrphanSubjects = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.obsidianSidebar,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.obsidianBorder),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Xoá Khung "${widget.curriculumCode}"?',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bạn có chắc chắn muốn xoá Khung chương trình "${widget.curriculumName}" (${widget.totalCourses} môn học)?',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 14),
          CheckboxListTile(
            value: _deleteOrphanSubjects,
            onChanged: (val) => setState(() => _deleteOrphanSubjects = val ?? false),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(
              'Đồng thời xoá tất cả môn học chỉ thuộc khung này khỏi CSDL',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orangeAccent),
            ),
            subtitle: Text(
              'Nếu không tích, các môn học sẽ được giữ lại trong danh mục chung.',
              style: TextStyle(fontSize: 11, color: AppColors.obsidianTextMuted),
            ),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppColors.obsidianBorder),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Huỷ', style: TextStyle(fontSize: 12)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          onPressed: () => Navigator.of(context).pop(_deleteOrphanSubjects),
          child: const Text('Xác nhận xoá', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
