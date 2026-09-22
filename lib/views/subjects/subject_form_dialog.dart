import 'package:flutter/material.dart';

import '../../models/prerequisite.dart';
import '../../models/subject.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';

/// Hộp thoại thêm mới / sửa một môn học (một NODE của đồ thị).
class SubjectFormDialog extends StatefulWidget {
  /// null = thêm mới.
  final Subject? subject;

  /// Khi thêm mới từ menu chuột phải của một tệp môn học: môn vừa tạo được
  /// gắn luôn vào tệp đó thay vì rơi vào nhóm "Môn ngoài khung".
  final int? curriculumId;

  /// Kỳ điền sẵn khi tạo môn từ menu chuột phải của một kỳ.
  final int? initialSemester;

  const SubjectFormDialog({
    super.key,
    this.subject,
    this.curriculumId,
    this.initialSemester,
  });

  static Future<bool> show(
    BuildContext context, {
    Subject? subject,
    int? curriculumId,
    int? initialSemester,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => SubjectFormDialog(
        subject: subject,
        curriculumId: curriculumId,
        initialSemester: initialSemester,
      ),
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
    _semester = s?.semester ?? widget.initialSemester ?? 1;
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

      // Môn tạo từ menu chuột phải của một tệp môn học thì phải nằm luôn
      // trong tệp đó, nếu không nó sẽ rơi xuống nhóm "Môn ngoài khung" và
      // người dùng tưởng thao tác không ăn.
      final curriculumId = widget.curriculumId;
      if (curriculumId != null) {
        await AppState.instance.assignSubjectsToCurriculum(
          curriculumId: curriculumId,
          subjects: [
            Subject.create(
              code: _code.text,
              name: _name.text,
              semester: _semester,
              credits: _credits,
            ).copyWith(id: subjectId),
          ],
        );
      }

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
  /// Cho chọn NHIỀU môn một lượt: dựng đồ thị thường phải nối vài cạnh liền
  /// nhau, mở lại hộp thoại cho từng cạnh một là thừa thao tác.
  final Set<int> _selectedIds = <int>{};
  String _relationType = Prerequisite.kPrerequisite;
  bool _saving = false;

  /// Chuột đang ở trên ô chọn môn. Tự theo dõi thay vì để InkWell lo, vì
  /// InkWell tô phủ cả dòng helperText phía dưới viền.
  bool _pickerHovered = false;

  Future<void> _save() async {
    if (_selectedIds.isEmpty || _saving) return;
    setState(() => _saving = true);

    final labelOf = {
      for (final s in AppState.instance.graph.subjects)
        if (s.id != null) s.id!: s.code,
    };
    final failures = <String>[];
    var added = 0;

    // Mỗi cạnh một try/catch riêng: một cạnh tạo chu trình không được làm hỏng
    // những cạnh hợp lệ còn lại trong cùng lượt chọn.
    for (final id in _selectedIds) {
      try {
        await AppState.instance.addEdge(
          subjectId: widget.subject.id!,
          prerequisiteId: id,
          relationType: _relationType,
        );
        added++;
      } catch (e) {
        failures.add('${labelOf[id] ?? id} ($e)');
      }
    }

    if (!mounted) return;
    if (failures.isNotEmpty) {
      Ui.error(
        context,
        'Không thêm được ${failures.length} liên kết: ${failures.join('; ')}',
      );
    }
    if (added > 0) {
      Navigator.pop(context, true);
    } else {
      // Hỏng sạch thì giữ hộp thoại lại để người dùng bỏ bớt môn rồi thử lại.
      setState(() => _saving = false);
    }
  }

  /// Chữ tóm tắt hiện trong ô khi menu đang đóng.
  String _summary(List<Subject> options) {
    final codes = options
        .where((s) => _selectedIds.contains(s.id))
        .map((s) => s.code)
        .toList();
    if (codes.isEmpty) return 'Chưa chọn môn nào';
    return '${codes.length} môn: ${codes.join(', ')}';
  }

  /// Ô chọn môn: nhìn và mở giống hệt dropdown "Loại quan hệ", nhưng bên trong
  /// là danh sách checkbox nên chọn được nhiều môn mà menu không tự đóng.
  Widget _subjectPicker(List<Subject> options) {
    final hasSelection = _selectedIds.isNotEmpty;

    return MenuAnchor(
      // Chặn bề ngang để tên môn dài không kéo menu tràn ra ngoài màn hình, và
      // chặn chiều cao để danh sách dài thì cuộn bên trong menu.
      style: const MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(412, 0)),
        maximumSize: WidgetStatePropertyAll(Size(412, 320)),
      ),
      // MenuAnchor neo theo cả InputDecorator, mà InputDecorator tính luôn
      // dòng helperText bên dưới viền — nên menu mặc định rơi xuống dưới dòng
      // chữ đó, chừa một khoảng trống nhìn hụt. Kéo lên đúng chiều cao dòng
      // helper để menu bắt đầu ngay mép dưới ô và che dòng chữ lại.
      alignmentOffset: const Offset(0, -12),
      builder: (context, controller, _) {
        // Cố tình KHÔNG dùng InkWell: nó bọc cả InputDecorator nên vệt
        // hover/splash phủ luôn xuống dòng helperText, trông như cả khối bị
        // đổi nền. Đặt hoverColor/splashColor trong suốt vẫn còn sót lớp phủ,
        // nên bỏ hẳn Ink ra khỏi cây widget. MouseRegion giữ lại con trỏ bàn
        // tay, HitTestBehavior.opaque giữ nguyên vùng bấm của cả ô.
        return MouseRegion(
          cursor: _saving
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onEnter: (_) {
            if (!_pickerHovered) setState(() => _pickerHovered = true);
          },
          onExit: (_) {
            if (_pickerHovered) setState(() => _pickerHovered = false);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _saving
                ? null
                : () =>
                      controller.isOpen ? controller.close() : controller.open(),
            child: InputDecorator(
              // Hover do InputDecorator vẽ, đúng cách DropdownButtonFormField
              // đang làm cho ô "Loại quan hệ" — nên nền chỉ tô trong khung ô,
              // không liếm xuống dòng helperText như InkWell trước đây.
              isHovering: _pickerHovered && !_saving,
              decoration: InputDecoration(
                labelText: 'Môn phải học trước',
                helperText: 'Bấm để mở danh sách, chọn được nhiều môn',
                suffixIcon: Icon(
                  controller.isOpen
                      ? Icons.arrow_drop_up
                      : Icons.arrow_drop_down,
                ),
              ),
              child: Text(
                _summary(options),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: hasSelection
                    ? null
                    : TextStyle(color: Theme.of(context).hintColor),
              ),
            ),
          ),
        );
      },
      menuChildren: [
        // Cả danh sách gói trong MỘT child là lưới chip, không phải mỗi môn
        // một dòng menu. Nhờ không dùng MenuItemButton nên bấm chip không kích
        // hoạt cơ chế đóng menu của MenuAnchor — chọn liên tục nhiều môn được.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: SizedBox(
            width: 388,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final s in options) _subjectChip(s)],
                ),
                if (hasSelection)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => setState(_selectedIds.clear),
                      icon: const Icon(Icons.clear, size: 16),
                      label: Text('Bỏ chọn tất cả (${_selectedIds.length})'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Một môn dưới dạng chip: chấm màu theo kỳ ở đầu, mã môn ở giữa, dấu `×`
  /// để bỏ chọn ở cuối — dấu `×` chỉ hiện khi môn đang được chọn.
  ///
  /// Nhãn chỉ để mã môn cho chip gọn; tên đầy đủ nằm ở tooltip, vì
  /// "CSD201 — Data Structures and Algorithms" nhét vào chip thì mỗi hàng chỉ
  /// còn chỗ cho một môn.
  Widget _subjectChip(Subject s) {
    final selected = _selectedIds.contains(s.id);

    return Tooltip(
      message: '${s.code} — ${s.name}',
      child: InputChip(
        isEnabled: !_saving,
        selected: selected,
        // Tắt dấu tick mặc định, nếu không nó chen vào chỗ của avatar.
        showCheckmark: false,
        // Nền theo trạng thái. Lưu ý: hễ truyền `color` là RawChip đặt luôn
        // hoverColor của InkWell bên trong thành trong suốt (chip.dart), tức
        // toàn bộ hiệu ứng hover dồn hết vào resolver này — trả `hoverColor`
        // mặc định của ThemeData (~4% alpha) thì nhìn như không có hover.
        // Trả null ở mọi trạng thái không hover để chip giữ nguyên màu mặc
        // định, kể cả màu của trạng thái đang chọn.
        color: WidgetStateProperty.resolveWith((states) {
          if (!states.contains(WidgetState.hovered)) return null;
          return states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.55);
        }),
        // Thêm viền tím khi hover: nếu nền tím vẫn chìm trên theme tối thì
        // đường viền vẫn cho thấy rõ con trỏ đang ở chip nào.
        side: WidgetStateBorderSide.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? const BorderSide(color: AppColors.primary, width: 1.5)
              : null,
        ),
        avatar: CircleAvatar(
          backgroundColor: AppColors.forSemester(s.semester),
          child: Text(
            '${s.semester}',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        label: Text(s.code),
        onSelected: (value) => setState(() {
          if (value) {
            _selectedIds.add(s.id!);
          } else {
            _selectedIds.remove(s.id!);
          }
        }),
        onDeleted: selected
            ? () => setState(() => _selectedIds.remove(s.id!))
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final existing = state
        .prerequisitesOf(widget.subject.id!)
        .map((s) => s.id)
        .toSet();

    final options = state.graph.subjects
        .where(
          (s) =>
              s.id != null &&
              s.id != widget.subject.id &&
              !existing.contains(s.id),
        )
        .toList();

    return AlertDialog(
      title: Text(
        'Thêm tiên quyết cho ${widget.subject.code}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: 460,
        child: options.isEmpty
            ? const Text('Không còn môn nào khả dụng để làm tiên quyết.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _relationType,
                    decoration: const InputDecoration(
                      labelText: 'Loại quan hệ',
                      helperText: 'Áp dụng cho mọi môn được chọn bên dưới',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: Prerequisite.kPrerequisite,
                        child: Text('Tiên quyết bắt buộc'),
                      ),
                      DropdownMenuItem(
                        value: Prerequisite.kRelated,
                        child: Text('Liên quan / tham khảo'),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(
                            () =>
                                _relationType = v ?? Prerequisite.kPrerequisite,
                          ),
                  ),
                  const SizedBox(height: 16),
                  _subjectPicker(options),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Huỷ'),
        ),
        ElevatedButton(
          onPressed: _saving || _selectedIds.isEmpty ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _selectedIds.isEmpty
                      ? 'Thêm liên kết'
                      : 'Thêm ${_selectedIds.length} liên kết',
                ),
        ),
      ],
    );
  }
}
