import 'package:flutter/material.dart';

import '../../services/db_service.dart';
import '../../services/settings_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_constants.dart';
import '../../utils/ui_helpers.dart';

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

  /// MOCK — Browse Vault / Mở bằng Obsidian / Xuất-Nhập Vault
  /// (Giai đoạn 2 và 4, Prompts_GiaiDoan_2345.md).
  ///
  /// "Xuất ra Vault" và "Nhập từ Vault" thực ra đã có sẵn logic thật ở
  /// `AppState.instance.exportToVault()` / `importFromVault()` (dùng trong
  /// `vault_page.dart`) — chỉ cần đổi `_mockAction(...)` thành gọi 2 hàm đó
  /// là xong. "Browse..." cần `file_selector` (`getDirectoryPath`, xem
  /// `_pickVault()` trong `vault_page.dart`). "Mở bằng Obsidian" cần thêm
  /// package `url_launcher` để mở `obsidian://open?path=...`.
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
              'Obsidian, hoặc đồng bộ hai chiều với CSDL. Các nút bên dưới '
              'đang là bản mock — sẽ nối logic thật dần theo từng giai đoạn.',
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
                    onPressed: () => _mockAction('Browse thư mục Vault'),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.launch, size: 18),
                    label: const Text('Mở bằng Obsidian'),
                    onPressed: () => _mockAction('Mở Vault bằng app Obsidian'),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Xuất ra Vault'),
                    onPressed: () => _mockAction('Xuất dữ liệu ra Vault'),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Nhập từ Vault'),
                    onPressed: () => _mockAction('Nhập dữ liệu từ Vault'),
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
