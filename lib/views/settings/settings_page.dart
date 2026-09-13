import 'package:flutter/material.dart';

import '../../services/db_service.dart';
import '../../services/settings_service.dart';
import '../../state/app_state.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_constants.dart';
import '../../utils/ui_helpers.dart';

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
                  _aiCard(),
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
                label: 'Obsidian Vault',
                value: state.vaultPath ?? '(chưa chọn)',
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
