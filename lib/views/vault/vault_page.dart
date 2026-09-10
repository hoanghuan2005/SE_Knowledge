import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../services/obsidian_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/ui_helpers.dart';

/// Cầu nối giữa file `.md` trên đĩa và SQLite.
///
/// Quét Vault bằng `dart:io`, bóc cú pháp `[[...]]` thành các cạnh của đồ thị,
/// và ghi ngược đồ thị ra file Markdown mà Obsidian mở được ngay.
class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  List<ObsidianNote> _notes = const [];
  ObsidianNote? _preview;
  String _previewRaw = '';
  bool _busy = false;
  VaultSyncReport? _lastReport;

  Future<void> _pickVault() async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Chọn Vault',
    );
    if (path == null) return;
    await AppState.instance.setVaultPath(path);
    await _scan();
  }

  Future<void> _scan() async {
    final path = AppState.instance.vaultPath;
    if (path == null) return;

    setState(() => _busy = true);
    try {
      final notes = await ObsidianService.instance.scanVault(path);
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _preview = null;
        _previewRaw = '';
      });
    } catch (e) {
      if (mounted) Ui.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final report = await AppState.instance.importFromVault();
      await _scan();
      if (!mounted) return;
      setState(() => _lastReport = report);
      Ui.success(context, report.summary);
    } catch (e) {
      if (mounted) Ui.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final ok = await Ui.confirm(
      context,
      title: 'Ghi đồ thị ra Vault?',
      message:
          'Mỗi môn trong CSDL sẽ thành một file <MÃ MÔN>.md, kèm front matter '
          'và các liên kết [[...]]. File cùng tên sẽ bị ghi đè, nhưng phần '
          '"## Ghi chú" bạn tự viết vẫn được giữ lại.',
      confirmLabel: 'Ghi ra Vault',
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      final count = await AppState.instance.exportToVault();
      await _scan();
      if (mounted) Ui.success(context, 'Đã ghi $count file .md ra Vault.');
    } catch (e) {
      if (mounted) Ui.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openNote(ObsidianNote note) async {
    try {
      final raw = await ObsidianService.instance.readNote(note.filePath);
      if (!mounted) return;
      setState(() {
        _preview = note;
        _previewRaw = raw;
      });
    } catch (e) {
      if (mounted) Ui.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;

        return Column(
          children: [
            PageHeader(
              title: 'Obsidian Vault',
              subtitle: state.hasVault
                  ? state.vaultPath!
                  : 'Chưa chọn thư mục Vault',
              actions: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text(state.hasVault ? 'Đổi thư mục' : 'Chọn thư mục'),
                  onPressed: _busy ? null : _pickVault,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Quét lại'),
                  onPressed: _busy || !state.hasVault ? null : _scan,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Ghi ra Vault'),
                  onPressed: _busy || !state.hasVault ? null : _export,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Nạp vào CSDL'),
                  onPressed: _busy || !state.hasVault ? null : _import,
                ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: !state.hasVault
                  ? _noVault()
                  : Row(
                      children: [
                        SizedBox(width: 340, child: _noteList()),
                        const VerticalDivider(width: 1),
                        Expanded(child: _previewPane()),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _noVault() {
    return EmptyState(
      icon: Icons.folder_off_outlined,
      title: 'Chưa liên kết Obsidian Vault',
      message:
          'Chọn thư mục Vault của bạn. App sẽ quét mọi file .md, đọc cú pháp '
          '[[Tên môn]] và dựng lại đồ thị tiên quyết trong SQLite. Không có '
          'file nào bị sửa cho tới khi bạn bấm "Ghi ra Vault".',
      action: ElevatedButton.icon(
        icon: const Icon(Icons.folder_open, size: 18),
        label: const Text('Chọn thư mục Vault'),
        onPressed: _pickVault,
      ),
    );
  }

  Widget _noteList() {
    if (_notes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: EmptyState(
          icon: Icons.description_outlined,
          title: 'Không thấy file .md nào',
          message:
              'Thư mục này chưa có ghi chú Markdown. Bấm "Ghi ra Vault" để '
              'app sinh sẵn file cho các môn đang có trong CSDL.',
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Text(
            '${_notes.length} file .md',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _notes.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, i) {
              final note = _notes[i];
              final selected = _preview?.filePath == note.filePath;
              return Material(
                color: selected ? AppColors.primaryLight : Colors.transparent,
                child: ListTile(
                  dense: true,
                  onTap: () => _openNote(note),
                  title: Text(
                    note.fileName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    note.prerequisiteLinks.isEmpty
                        ? '${note.allLinks.length} liên kết [[...]]'
                        : 'Tiên quyết: ${note.prerequisiteLinks.join(", ")}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: Text(
                    'K${note.semester}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
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

  Widget _previewPane() {
    final report = _lastReport;
    final note = _preview;

    if (note == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: report == null
            ? const EmptyState(
                icon: Icons.article_outlined,
                title: 'Chọn một file để xem nội dung',
                message:
                    'Bấm vào một ghi chú bên trái để xem Markdown thô cùng các '
                    'liên kết [[...]] mà app bóc tách được.',
              )
            : _reportCard(report),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${note.code} — ${note.name}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                note.filePath,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final link in note.allLinks)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: note.prerequisiteLinks.contains(link)
                            ? AppColors.primaryLight
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        '[[$link]]',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            color: AppColors.background,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                _previewRaw,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  fontFamily: 'monospace',
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _reportCard(VaultSyncReport report) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kết quả lần đồng bộ gần nhất',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              report.summary,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            if (report.warnings.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Liên kết chưa khớp',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              for (final w in report.warnings.take(20))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $w',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.error,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
