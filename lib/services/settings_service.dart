import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_constants.dart';

/// Lưu cấu hình cục bộ: đường dẫn Obsidian Vault, nhà cung cấp AI, API key.
///
/// API key KHÔNG được hardcode trong source và KHÔNG bị commit lên Git.
/// Người dùng tự nhập trong màn hình Cài đặt, giá trị nằm lại trên máy họ.
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // --- Obsidian Vault ---

  Future<String?> getVaultPath() async =>
      (await _p).getString(AppConstants.keyVaultPath);

  Future<void> setVaultPath(String? path) async {
    final prefs = await _p;
    if (path == null || path.isEmpty) {
      await prefs.remove(AppConstants.keyVaultPath);
    } else {
      await prefs.setString(AppConstants.keyVaultPath, path);
    }
  }

  // --- AI ---

  Future<String> getAiProvider() async =>
      (await _p).getString(AppConstants.keyAiProvider) ??
      AppConstants.providerGemini;

  Future<void> setAiProvider(String provider) async =>
      (await _p).setString(AppConstants.keyAiProvider, provider);

  Future<String?> getApiKey() async =>
      (await _p).getString(AppConstants.keyAiApiKey);

  Future<void> setApiKey(String? key) async {
    final prefs = await _p;
    final value = key?.trim() ?? '';
    if (value.isEmpty) {
      await prefs.remove(AppConstants.keyAiApiKey);
    } else {
      await prefs.setString(AppConstants.keyAiApiKey, value);
    }
  }

  Future<String> getModel() async {
    final prefs = await _p;
    final saved = prefs.getString(AppConstants.keyAiModel);
    if (saved != null && saved.isNotEmpty) return saved;
    final provider = await getAiProvider();
    return provider == AppConstants.providerOpenAi
        ? AppConstants.defaultOpenAiModel
        : AppConstants.defaultGeminiModel;
  }

  Future<void> setModel(String? model) async {
    final prefs = await _p;
    final value = model?.trim() ?? '';
    if (value.isEmpty) {
      await prefs.remove(AppConstants.keyAiModel);
    } else {
      await prefs.setString(AppConstants.keyAiModel, value);
    }
  }

  // --- Theme ---

  Future<String> getThemeMode() async =>
      (await _p).getString(AppConstants.keyThemeMode) ?? 'dark';

  Future<void> setThemeMode(String mode) async =>
      (await _p).setString(AppConstants.keyThemeMode, mode);
}
