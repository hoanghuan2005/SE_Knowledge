import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../services/db_service.dart';
import '../../services/md_intake_service.dart';
import '../../services/obsidian_launcher.dart';
import '../../services/settings_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_constants.dart';
import '../../utils/ui_helpers.dart';
import '../academic/transcript_import_dialog.dart';
import '../vault/vault_export_flow.dart';
import '../vault/vault_import_flow.dart';

/// Cấu hình cục bộ và thông tin kiến trúc (tiện lúc demo bảo vệ đồ án).
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService _settings = SettingsService.instance;
  final TextEditingController _apiKey = TextEditingController();
  final TextEditingController _model = TextEditingController();

  String _provider = AppConstants.providerGemini;

  /// Model cho tác vụ phụ; null nghĩa là dùng chung model chính.
  String? _lightModel;
  bool _obscureKey = true;
  bool _loaded = false;
  int _dbSize = 0;
  bool _autoSaveFap = true;
  bool _batchImporting = false;
  bool _sendTranscriptToAi = true;
  bool _transcriptBusy = false;
  DateTime? _lastTranscriptImport;

  /// Khoá hai nút Xuất/Nhập Vault trong lúc đang chạy, tránh bấm chồng nhau
  /// làm hai lượt ghi cùng đụng vào một thư mục.
  bool _vaultBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final provider = await _settings.getAiProvider();
    final key = await _settings.getApiKey();
    final model = await _settings.getModel();
    final lightModel = await _settings.getLightModel(provider);
    final size = await DbService.instance.databaseSizeInBytes();
    final autoSave = await _settings.getAutoSaveFapNotes();
    final sendTranscript = await _settings.getSendTranscriptToAi();
    final lastTranscript = await DbService.instance.lastTranscriptImportAt();
    if (!mounted) return;
    setState(() {
      _provider = provider;
      _apiKey.text = key ?? '';
      _model.text = model;
      _lightModel = lightModel;
      _dbSize = size;
      _autoSaveFap = autoSave;
      _sendTranscriptToAi = sendTranscript;
      _lastTranscriptImport = lastTranscript;
      _loaded = true;
    });
  }

  Future<void> _batchImportInbox() async {
    setState(() => _batchImporting = true);
    try {
      final res = await DbService.instance.batchImportFromInbox();
      await AppState.instance.refresh();
      final size = await DbService.instance.databaseSizeInBytes();
      if (!mounted) return;
      setState(() => _dbSize = size);
      final skipped = res['skipped'] as int? ?? 0;
      final failed = res['failed'] as int? ?? 0;
      Ui.success(
        context,
        'Đã quét ${res['totalFiles']} file .md: '
        'nạp ${res['curricula']} khung CTĐT, ${res['syllabi']} syllabus, '
        '${res['edges']} cạnh tiên quyết'
        '${skipped > 0 ? ', bỏ qua $skipped file không phải trang FAP' : ''}'
        '${failed > 0 ? ', lỗi $failed file' : ''}.',
      );
    } catch (e) {
      if (!mounted) return;
      Ui.error(context, e);
    } finally {
      if (mounted) setState(() => _batchImporting = false);
    }
  }

  Future<void> _openInboxFolder() async {
    final dir = await MdIntakeService.instance.getTargetDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await ObsidianLauncher.openInExplorer(dir.path);
  }

  Future<void> _saveAi() async {
    await _settings.setAiProvider(_provider);
    await _settings.setApiKey(_apiKey.text);
    await _settings.setModel(_model.text);
    await _settings.setLightModel(_lightModel, _provider);
    if (mounted) Ui.success(context, 'Đã lưu cấu hình AI trên máy này.');
  }

  Future<void> _reset() async {
    final ok = await Ui.confirm(
      context,
      title: 'Xoá toàn bộ dữ liệu?',
      message:
          'Mọi môn học và liên kết trong SQLite sẽ bị xoá. File .md trong '
          'Obsidian Vault không bị ảnh hưởng.',
      confirmLabel: 'Xoá hết',
      destructive: true,
    );
    if (!ok) return;
    try {
      await AppState.instance.resetAll();
      if (mounted) Ui.success(context, 'Đã xoá sạch cơ sở dữ liệu.');
    } catch (e) {
      if (mounted) Ui.error(context, e);
    }
  }

  /// MOCK dùng chung cho các nút chưa có backend thật (Browse Vault, Mở bằng
  /// Obsidian, Xuất/Nhập Vault trong Cài đặt, Cập nhật từ FAP). Chỉ hiện
  /// toast xác nhận đã bấm — không đọc/ghi gì. Xem Prompts_GiaiDoan_2345.md
  /// (Giai đoạn 2, 4, 5) để nối từng nút vào logic thật.
  void _mockAction(String label) {
    Ui.success(context, '$label — bản demo (mock), chưa nối logic thật.');
  }

  // ------------------------------------------------------------------
  // EXPORT / IMPORT VAULT — logic thật, dùng chung backend với tab Vault
  // ------------------------------------------------------------------

  /// Ghi môn trong SQLite thành file `.md` trong Vault.
  ///
  /// Hộp thoại hỏi trước ghi những môn nào — cả CSDL, một tệp môn học, một kỳ,
  /// hay chọn tay. Với file đã tồn tại thì `mergeMarkdown` chỉ ghi đè ba khối
  /// app sở hữu (front matter, "Môn tiên quyết", "Mở ra các môn"); mọi mục
  /// người dùng tự thêm được giữ nguyên.
  Future<void> _exportToVault() async {
    setState(() => _vaultBusy = true);
    try {
      await VaultExportFlow.run(context);
    } finally {
      if (mounted) setState(() => _vaultBusy = false);
    }
  }

  /// Đọc Vault về SQLite, nhưng cho xem trước rồi mới ghi.
  ///
  /// Dùng `planImport` + `applyVaultPlan` thay vì `importFromVault` một phát,
  /// vì luồng nhập có một thao tác làm mất dữ liệu: gỡ những liên kết đã bị
  /// xoá khỏi file `.md`. Người dùng cần thấy danh sách đó trước khi đồng ý.
  Future<void> _importFromVault() async {
    setState(() => _vaultBusy = true);
    try {
      final report = await VaultImportFlow.run(context);
      if (report == null || !mounted) return;
      if (report.warnings.isNotEmpty) {
        Ui.toast(context, '${report.summary} ${report.warnings.join(' ')}');
      }
    } finally {
      if (mounted) setState(() => _vaultBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        return Column(
          children: [
            PageHeader(
              title: 'Cài đặt',
              subtitle: 'Mọi cấu hình chỉ nằm trên máy này, không gửi đi đâu',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _themeCard(),
                  const SizedBox(height: 16),
                  _vaultCard(),
                  const SizedBox(height: 16),
                  _aiCard(),
                  const SizedBox(height: 16),
                  _fapCard(),
                  const SizedBox(height: 16),
                  _intakeCard(),
                  const SizedBox(height: 16),
                  _transcriptCard(),
                  const SizedBox(height: 16),
                  _storageCard(),
                  const SizedBox(height: 16),
                  _architectureCard(),
                  const SizedBox(height: 16),
                  _dangerCard(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _themeCard() {
    final isDark = AppState.instance.isDark;
    return _Section(
      icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
      title: 'Giao diện ứng dụng',
      description:
          'Chọn phong cách giao diện phù hợp với bạn. Mặc định là Obsidian Dark '
          'tối ưu cho mắt khi làm việc lâu.',
      child: SegmentedButton<bool>(
        showSelectedIcon: true,
        segments: const [
          ButtonSegment<bool>(
            value: true,
            icon: Icon(Icons.dark_mode_outlined, size: 16),
            label: Text('Giao diện Tối (Obsidian Black)'),
          ),
          ButtonSegment<bool>(
            value: false,
            icon: Icon(Icons.light_mode_outlined, size: 16),
            label: Text('Giao diện Sáng (Light)'),
          ),
        ],
        selected: {isDark},
        onSelectionChanged: (s) {
          final dark = s.first;
          AppState.instance.setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
        },
      ),
    );
  }

  Widget _aiCard() {
    return _Section(
      icon: Icons.auto_awesome,
      title: 'Trợ lý AI',
      description:
          'App gọi thẳng REST API của nhà cung cấp bằng package http. '
          'API key được lưu cục bộ và không nằm trong source code.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: AppConstants.providerGemini,
                label: Text('Google Gemini'),
              ),
              ButtonSegment(
                value: AppConstants.providerOpenAi,
                label: Text('OpenAI'),
              ),
            ],
            selected: {_provider},
            onSelectionChanged: (s) {
              setState(() {
                _provider = s.first;
                _model.text = _provider == AppConstants.providerOpenAi
                    ? AppConstants.defaultOpenAiModel
                    : AppConstants.defaultGeminiModel;
                // Hai nhà cung cấp có danh sách model phụ khác nhau, giữ lại
                // lựa chọn cũ sẽ thành giá trị không có trong danh sách mới.
                _lightModel = null;
              });
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKey,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              labelText: 'API key',
              hintText: _provider == AppConstants.providerGemini
                  ? 'Lấy tại Google AI Studio'
                  : 'Lấy tại platform.openai.com',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey ? Icons.visibility : Icons.visibility_off,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _model,
            decoration: const InputDecoration(labelText: 'Tên model'),
          ),
          const SizedBox(height: 16),
          _lightModelField(),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Lưu cấu hình'),
              onPressed: _saveAi,
            ),
          ),
        ],
      ),
    );
  }

  /// Khối Obsidian Vault.
  ///
  /// Trỏ tới thư mục Vault và mở nó bằng app Obsidian ngoài.
  ///
  /// Dùng chung `getDirectoryPath` của `file_selector` như `_pickVault()`
  /// trong `vault_page.dart`, và [ObsidianLauncher] cho URI `obsidian://`.
  Future<void> _browseVault() async {
    final path = await getDirectoryPath(confirmButtonText: 'Chọn Vault');
    if (path == null) return;
    await AppState.instance.setVaultPath(path);
    if (!mounted) return;
    Ui.success(context, 'Đã trỏ Vault tới $path');
  }

  /// Mở cả Vault bằng Obsidian; thất bại thì lùi về File Explorer.
  Future<void> _openVaultInObsidian() async {
    final path = AppState.instance.vaultPath;
    if (path == null) return;

    final ok = await ObsidianLauncher.openVault(path);
    if (ok || !mounted) return;

    Ui.error(
      context,
      'Không mở được bằng Obsidian. Thường do một trong hai: máy chưa cài '
      'Obsidian, hoặc thư mục này chưa từng được mở như một Vault trong '
      'Obsidian (Obsidian không tự thêm vault lạ qua URI). Đang mở bằng '
      'File Explorer thay thế.',
    );
    await ObsidianLauncher.openInExplorer(path);
  }

  /// "Xuất ra Vault" và "Nhập từ Vault" dùng chung backend với tab Vault;
  /// "Browse..." và "Mở bằng Obsidian" nay cũng đã chạy thật.
  Widget _vaultCard() {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final vaultPath = AppState.instance.vaultPath;
        return _Section(
          icon: Icons.folder_special,
          title: 'Obsidian Vault',
          description:
              'Trỏ tới đúng thư mục Vault trên máy, mở thẳng bằng app '
              'Obsidian, hoặc đồng bộ hai chiều với CSDL. Muốn mở bằng '
              'Obsidian thì thư mục này phải từng được mở như một Vault '
              'trong Obsidian ít nhất một lần.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _KeyValue(
                label: 'Đường dẫn Vault',
                value: vaultPath ?? '(chưa chọn)',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Browse...'),
                    onPressed: _browseVault,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.launch, size: 18),
                    label: const Text('Mở bằng Obsidian'),
                    onPressed: vaultPath == null ? null : _openVaultInObsidian,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Xuất ra Vault'),
                    onPressed: _vaultBusy || vaultPath == null
                        ? null
                        : _exportToVault,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Nhập từ Vault'),
                    onPressed: _vaultBusy || vaultPath == null
                        ? null
                        : _importFromVault,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// MOCK — Cập nhật từ FAP (Giai đoạn 5, module cào dữ liệu của Huân).
  Widget _fapCard() {
    return _Section(
      icon: Icons.cloud_sync,
      title: 'Cập nhật từ FAP',
      description:
          'Cào chương trình đào tạo / đề cương môn học trực tiếp từ FAP '
          '(module của Huân). Đang ở dạng mock — chờ hoàn thiện phần đăng '
          'nhập giữ session và cào dữ liệu ở Giai đoạn 5.',
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.cloud_download, size: 18),
          label: const Text('Cập nhật từ FAP'),
          onPressed: () => _mockAction('Cập nhật từ FAP'),
        ),
      ),
    );
  }

  /// Trạng thái cổng nhận markdown từ extension Chrome (Giai đoạn 5.2').
  ///
  /// Không có nút bật/tắt: server lên cùng app và chỉ nghe ở loopback, nên
  /// không có gì để người dùng phải quyết định.
  Widget _intakeCard() {
    final intake = MdIntakeService.instance;
    final running = intake.isRunning;
    return _Section(
      icon: Icons.download_for_offline_outlined,
      title: 'Nhận dữ liệu từ Chrome',
      description:
          'Mở trang FAP trong Chrome (đã đăng nhập sẵn) rồi bấm nút của '
          'extension "Page to Markdown Note" — trang sẽ được gửi thẳng vào đây '
          'để xem trước trước khi ghi vào CSDL.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                running ? Icons.check_circle : Icons.error_outline,
                size: 16,
                color: running ? AppColors.success : AppColors.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  intake.statusText,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: running
                        ? AppColors.textPrimary
                        : AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _KeyValue(
            label: 'Thư mục nhận file',
            value: AppState.instance.hasVault
                ? p.join(
                    AppState.instance.vaultPath!,
                    MdIntakeService.vaultSubfolder,
                  )
                : 'fap_inbox trong thư mục dữ liệu ứng dụng '
                    '(chưa chọn Obsidian Vault)',
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Tự động lưu vào CSDL khi nhận từ extension',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Ghi trực tiếp vào SQLite và thông báo nhẹ, không bật modal xác nhận từng môn (tiện lợi khi cào 48 môn).',
              style: TextStyle(fontSize: 12),
            ),
            value: _autoSaveFap,
            onChanged: (val) async {
              await _settings.setAutoSaveFapNotes(val);
              setState(() => _autoSaveFap = val);
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                icon: _batchImporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('Quét & Nhập toàn bộ fap_inbox'),
                onPressed: _batchImporting ? null : _batchImportInbox,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Mở thư mục fap_inbox'),
                onPressed: _openInboxFolder,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Khối Bảng điểm cá nhân.
  ///
  /// Công tắc gửi điểm cho AI mặc định bật, nhưng phần mô tả phải nói thẳng
  /// một câu là điểm số sẽ rời khỏi máy: cả app theo triết lý local-first, nên
  /// đúng chỗ dữ liệu đi ra ngoài thì người dùng phải được biết.
  Widget _transcriptCard() {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final profile = state.academicProfileOrEmpty;
        return _Section(
          icon: Icons.insights_outlined,
          title: 'Bảng điểm cá nhân',
          description:
              'Tải file "StudentTranscript_<MSSV>.xls" ở FAP (Report > '
              'Transcript) rồi chọn file đó ở đây. Điểm được lưu vào một bảng '
              'riêng nên xoá môn khỏi đồ thị không làm mất điểm đã học.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _KeyValue(
                label: 'Dữ liệu hiện có',
                value: state.hasTranscript
                    ? '${state.transcript.length} dòng điểm · GPA '
                          '${profile.gpaLabel} · ${profile.totalCredits} tín chỉ'
                    : '(chưa nhập bảng điểm)',
              ),
              _KeyValue(
                label: 'Lần nhập gần nhất',
                value: _lastTranscriptImport == null
                    ? '(chưa có)'
                    : _formatDateTime(_lastTranscriptImport!),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Gửi bảng điểm kèm câu hỏi cho AI',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Bật thì AI trả lời được "em yếu môn gì" bằng số liệu thật. '
                  'Lưu ý: điểm số của bạn sẽ được gửi tới nhà cung cấp AI bên '
                  'ngoài (Gemini / OpenAI) cùng với câu hỏi. Tắt thì AI chỉ '
                  'còn nhìn thấy đồ thị môn học.',
                  style: TextStyle(fontSize: 12),
                ),
                value: _sendTranscriptToAi,
                onChanged: (val) async {
                  await _settings.setSendTranscriptToAi(val);
                  if (mounted) setState(() => _sendTranscriptToAi = val);
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Nhập bảng điểm từ file FAP'),
                    onPressed: _transcriptBusy ? null : _importTranscript,
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Xoá bảng điểm'),
                    onPressed: _transcriptBusy || !state.hasTranscript
                        ? null
                        : _clearTranscript,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _importTranscript() async {
    setState(() => _transcriptBusy = true);
    try {
      final imported = await TranscriptImportDialog.pickAndShow(context);
      if (imported == true) await _refreshTranscriptStatus();
    } finally {
      if (mounted) setState(() => _transcriptBusy = false);
    }
  }

  Future<void> _clearTranscript() async {
    final ok = await Ui.confirm(
      context,
      title: 'Xoá bảng điểm?',
      message:
          'Toàn bộ ${AppState.instance.transcript.length} dòng điểm sẽ bị xoá '
          'khỏi CSDL. Môn học và liên kết tiên quyết trên đồ thị không bị ảnh '
          'hưởng. Nhập lại file transcript là có lại.',
      confirmLabel: 'Xoá bảng điểm',
      destructive: true,
    );
    if (!ok) return;
    try {
      await AppState.instance.clearTranscript();
      await _refreshTranscriptStatus();
      if (mounted) Ui.success(context, 'Đã xoá bảng điểm.');
    } catch (e) {
      if (mounted) Ui.error(context, e);
    }
  }

  Future<void> _refreshTranscriptStatus() async {
    final at = await DbService.instance.lastTranscriptImportAt();
    if (!mounted) return;
    setState(() => _lastTranscriptImport = at);
  }

  String _formatDateTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  /// Chọn model cho tác vụ phụ (hiện là việc sinh câu hỏi gợi ý mỗi khi mở
  /// một môn).
  ///
  /// Dùng danh sách cố định thay vì ô gõ tự do: gõ sai tên model thì lời gọi
  /// hỏng, mà đây là chỗ người dùng không có cách nào biết mình gõ đúng hay
  /// sai. Chọn nhầm cũng không mất tính năng — app tự lùi về model chính.
  Widget _lightModelField() {
    final options = AppConstants.lightModelsOf(_provider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: _lightModel,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Model cho tác vụ phụ',
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Dùng chung model chính'),
            ),
            for (final option in options)
              DropdownMenuItem<String?>(
                value: option.id,
                child: Text('${option.label}  ·  ${option.id}'),
              ),
          ],
          onChanged: (value) => setState(() => _lightModel = value),
        ),
        const SizedBox(height: 6),
        Text(
          options.isEmpty
              ? 'Chưa có danh sách model phụ đã kiểm chứng cho nhà cung cấp '
                    'này, nên tác vụ phụ vẫn dùng model chính.'
              : 'Việc sinh câu hỏi gợi ý sẽ gọi model này thay vì model chính. '
                    'Google tính hạn mức riêng cho từng model, nên tách ra thì '
                    'việc phụ không còn ăn vào hạn mức dành cho việc trả lời.',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _storageCard() {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        return _Section(
          icon: Icons.storage,
          title: 'Lưu trữ cục bộ',
          description:
              'Một file SQLite duy nhất giữ toàn bộ node và edge. '
              'Không cần cài server, không cần Docker.',
          child: Column(
            children: [
              _KeyValue(
                label: 'File cơ sở dữ liệu',
                value: DbService.instance.databasePath,
              ),
              _KeyValue(
                label: 'Kích thước',
                value: '${(_dbSize / 1024).toStringAsFixed(1)} KB',
              ),
              _KeyValue(
                label: 'Dữ liệu hiện có',
                value:
                    '${state.stats['curriculums'] ?? 0} khung CTĐT · '
                    '${state.stats['subjects'] ?? 0} môn · '
                    '${state.stats['edges'] ?? 0} liên kết · '
                    '${state.stats['orphans'] ?? 0} môn rời rạc',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _architectureCard() {
    return const _Section(
      icon: Icons.architecture,
      title: 'Kiến trúc',
      description:
          'Standalone Desktop App theo triết lý Local-First. Obsidian coi file '
          'trên máy người dùng là nguồn sự thật, nên đưa thêm application '
          'server và database server vào một tiện ích cục bộ là phản kiến '
          'trúc. Toàn bộ hệ thống gói trong một tiến trình Flutter duy nhất.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KeyValue(label: 'Giao diện', value: 'Flutter Desktop (Dart thuần)'),
          _KeyValue(
            label: 'Cơ sở dữ liệu',
            value: 'SQLite nhúng qua sqflite_common_ffi',
          ),
          _KeyValue(
            label: 'Quan hệ dữ liệu',
            value: 'PRIMARY KEY, FOREIGN KEY, UNIQUE, CASCADE, INDEX, JOIN',
          ),
          _KeyValue(label: 'Đọc/ghi Markdown', value: 'dart:io thuần'),
          _KeyValue(label: 'Trực quan đồ thị', value: 'graphview'),
          _KeyValue(label: 'Gọi AI', value: 'http tới Gemini / OpenAI'),
          _KeyValue(label: 'Yêu cầu mạng', value: 'Chỉ khi dùng trợ lý AI'),
        ],
      ),
    );
  }

  Widget _dangerCard() {
    return _Section(
      icon: Icons.warning_amber_rounded,
      title: 'Vùng nguy hiểm',
      description: 'Dùng khi muốn làm sạch dữ liệu để demo lại từ đầu.',
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.error),
          ),
          icon: const Icon(Icons.delete_forever, size: 18),
          label: const Text('Xoá toàn bộ dữ liệu trong SQLite'),
          onPressed: _reset,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  const _Section({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.55,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;

  const _KeyValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
