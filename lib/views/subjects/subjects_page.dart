import 'package:flutter/material.dart';

import '../../models/subject.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';
import '../widgets/subject_detail_panel.dart';
import 'subject_form_dialog.dart';

/// Bảng dữ liệu môn học — bản đọc trực tiếp của bảng `subjects` trong SQLite.
class SubjectsPage extends StatefulWidget {
  const SubjectsPage({super.key});

  @override
  State<SubjectsPage> createState() => _SubjectsPageState();
}

class _SubjectsPageState extends State<SubjectsPage> {
  final TextEditingController _search = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Subject> _filter(List<Subject> all) {
    final kw = _keyword.trim().toLowerCase();
    if (kw.isEmpty) return all;
    return all
        .where(
          (s) =>
              s.code.toLowerCase().contains(kw) ||
              s.name.toLowerCase().contains(kw),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final rows = _filter(state.graph.subjects);

        return Column(
          children: [
            PageHeader(
              title: 'Danh sách môn học',
              subtitle: 'Bảng `subjects` — ${rows.length} dòng đang hiển thị',
              actions: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: 'Tìm theo mã hoặc tên môn',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _keyword = v),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.route_outlined, size: 18),
                  label: const Text('Gợi ý lộ trình'),
                  onPressed: () => _showLearningOrder(context),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Thêm môn'),
                  onPressed: () => SubjectFormDialog.show(context),
                ),
              ],
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: rows.isEmpty
                        ? EmptyState(
                            icon: Icons.inbox_outlined,
                            title: state.graph.isEmpty
                                ? 'Chưa có môn học nào'
                                : 'Không tìm thấy môn khớp từ khoá',
                            message: state.graph.isEmpty
                                ? 'Bấm "Thêm môn" để tạo node đầu tiên, hoặc '
                                      'nạp dữ liệu từ Obsidian Vault.'
                                : 'Thử một từ khoá khác.',
                          )
                        : _Table(rows: rows),
                  ),
                  const SubjectDetailPanel(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLearningOrder(BuildContext context) async {
    final order = await AppState.instance.suggestLearningOrder();
    if (!context.mounted) return;

    if (order == null) {
      Ui.error(
        context,
        'Đồ thị đang có chu trình nên không sắp xếp được lộ trình.',
      );
      return;
    }
    if (order.isEmpty) {
      Ui.toast(context, 'Chưa có môn nào để sắp xếp.');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lộ trình học đề xuất'),
        content: SizedBox(
          width: 460,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sắp xếp topo (thuật toán Kahn) trên đồ thị tiên quyết. '
                'Học theo thứ tự này thì không môn nào bị thiếu tiên quyết.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: order.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, i) {
                    final s = order[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 13,
                        backgroundColor: AppColors.forSemester(s.semester),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title: Text(
                        '${s.code} — ${s.name}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        'Kỳ ${s.semester} · ${s.credits} tín chỉ',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }
}

class _Table extends StatelessWidget {
  final List<Subject> rows;

  const _Table({required this.rows});

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: const Row(
            children: [
              SizedBox(width: 92, child: _Th('MÃ MÔN')),
              Expanded(child: _Th('TÊN MÔN')),
              SizedBox(width: 64, child: _Th('KỲ')),
              SizedBox(width: 72, child: _Th('TÍN CHỈ')),
              SizedBox(width: 96, child: _Th('TIÊN QUYẾT')),
              SizedBox(width: 88, child: _Th('MỞ RA')),
              SizedBox(width: 52),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, i) {
              final s = rows[i];
              final selected = state.selectedSubjectId == s.id;
              final inDeg = state.graph.inDegree(s.id!);
              final outDeg = state.graph.outDegree(s.id!);

              return Material(
                color: selected ? AppColors.primaryLight : Colors.transparent,
                child: InkWell(
                  onTap: () => state.select(s.id),
                  onDoubleTap: () =>
                      SubjectFormDialog.show(context, subject: s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 92,
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: AppColors.forSemester(s.semester),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                s.code,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        SizedBox(width: 64, child: _Td('Kỳ ${s.semester}')),
                        SizedBox(width: 72, child: _Td('${s.credits}')),
                        SizedBox(width: 96, child: _Td('$inDeg môn')),
                        SizedBox(width: 88, child: _Td('$outDeg môn')),
                        SizedBox(
                          width: 52,
                          child: IconButton(
                            tooltip: 'Thêm môn tiên quyết',
                            icon: const Icon(Icons.add_link, size: 18),
                            onPressed: () => AddEdgeDialog.show(context, s),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Th extends StatelessWidget {
  final String text;
  const _Th(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _Td extends StatelessWidget {
  final String text;
  const _Td(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
    );
  }
}
