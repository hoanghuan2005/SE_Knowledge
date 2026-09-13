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
import '../widgets/vault_import_plan_dialog.dart';

/// Trạng thái hiển thị (thuần UI) cho nút "Test kết nối" ở khối Trợ lý AI.
///
/// MOCK: chưa gọi API thật. Khi làm phần "Cài đặt — Test connect Gemini API"
/// (xem Prompts_GiaiDoan_2345.md, Giai đoạn 3), thay `_mockTestConnection()`
/// bằng lời gọi `AiService.instance.testConnection(...)` thật và map kết quả
/// (thành công/thất bại) vào đúng 2 case success/failure bên dưới.
enum _MockConnStatus { idle, testing, success, failure }

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
  bool _obscureKey = true;
  bool _loaded = false;
  int _dbSize = 0;

  /// Khoá hai nút Xuất/Nhập Vault trong lúc đang chạy, tránh bấm chồng nhau
  /// làm hai lượt ghi cùng đụng vào một thư mục.
  bool _vaultBusy = false;

  // --- MOCK: trạng thái demo cho các nút chưa nối logic thật ---
  // Xem Prompts_GiaiDoan_2345.md để biết nút nào ứng với giai đoạn nào.
  _MockConnStatus _connStatus = _MockConnStatus.idle;
  bool _mockNextOk = true;

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
    final size = await DbService.instance.databaseSizeInBytes();
    if (!mounted) return;
    setState(() {
      _provider = provider;
      _apiKey.text = key ?? '';
      _model.text = model;
      _dbSize = size;
      _loaded = true;
    });
  }

  Future<void> _saveAi() async {
    await _settings.setAiProvider(_provider);
    await _settings.setApiKey(_apiKey.text);
    await _settings.setModel(_model.text);
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

  /// MOCK — Test connect (Giai đoạn 3, Prompts_GiaiDoan_2345.md).
  ///
  /// Chưa gọi Gemini/OpenAI thật, chỉ giả lập độ trễ mạng rồi luân phiên
  /// tick xanh / tick đỏ để xem trước giao diện. Khi làm thật: gọi
  /// `AiService.instance.testConnection(provider, apiKey, model)`, set
  /// `success` nếu request trả 200, `failure` cho mọi lỗi (401, timeout,...).
  Future<void> _mockTestConnection() async {
    setState(() => _connStatus = _MockConnStatus.testing);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _connStatus = _mockNextOk ? _MockConnStatus.success : _MockConnStatus.failure;
      _mockNextOk = !_mockNextOk;
    });
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

  /// Ghi toàn bộ môn trong SQLite thành file `.md` trong Vault.
  ///
  /// `exportAll` gọi `mergeMarkdown` cho file đã tồn tại, nên chỉ ba khối app
  /// sở hữu (front matter, "Môn tiên quyết", "Mở ra các môn") bị ghi đè; mọi
  /// mục người dùng tự thêm được giữ nguyên.
  Future<void> _exportToVault() async {
    final ok = await Ui.confirm(
      context,
      title: 'Ghi đồ thị ra Vault?',
      message:
          'Mỗi môn trong CSDL sẽ thành một file <MÃ MÔN>.md, kèm front matter '
          'và các liên kết [[...]]. Phần ghi chú bạn tự viết trong file vẫn '
          'được giữ lại.',
      confirmLabel: 'Ghi ra Vault',
    );
    if (!ok || !mounted) return;

    setState(() => _vaultBusy = true);
    try {
      final count = await AppState.instance.exportToVault();
      if (mounted) Ui.success(context, 'Đã ghi $count file .md ra Vault.');
    } catch (e) {
      if (mounted) Ui.error(context, e);
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
      final plan = await AppState.instance.planImportFromVault();
      if (!mounted) return;

      if (plan.isEmpty) {
        Ui.toast(context, 'Vault không có thay đổi nào so với CSDL.');
        return;
      }

      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => VaultImportPlanDialog(plan: plan),
      );
      if (ok != true || !mounted) return;

      final report = await AppState.instance.applyVaultPlan(plan);
      if (!mounted) return;
      if (report.warnings.isEmpty) {
        Ui.success(context, report.summary);
      } else {
        Ui.toast(context, '${report.summary} ${report.warnings.join(' ')}');
      }
    } catch (e) {
      if (mounted) Ui.error(context, e);
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
            const PageHeader(
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _connStatusBadge(),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: _connStatus == _MockConnStatus.testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check, size: 18),
                    label: const Text('Test kết nối'),
                    onPressed: _connStatus == _MockConnStatus.testing
                        ? null
                        : _mockTestConnection,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Lưu cấu hình'),
                    onPressed: _saveAi,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// MOCK — dải trạng thái tick xanh/tick đỏ cho "Test kết nối" ở trên.
  Widget _connStatusBadge() {
    switch (_connStatus) {
      case _MockConnStatus.idle:
        return const SizedBox.shrink();
      case _MockConnStatus.testing:
        return Text(
          'Đang kiểm tra…',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        );
      case _MockConnStatus.success:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.check_circle, size: 18, color: Colors.green),
            SizedBox(width: 6),
            Text(
              'Kết nối OK (demo)',
              style: TextStyle(fontSize: 12.5, color: Colors.green),
            ),
          ],
        );
      case _MockConnStatus.failure:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cancel, size: 18, color: AppColors.error),
            const SizedBox(width: 6),
            Text(
              'Kết nối thất bại (demo)',
              style: TextStyle(fontSize: 12.5, color: AppColors.error),
            ),
          ],
        );
    }
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
        ],
      ),
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
