import 'package:shared_preferences/shared_preferences.dart';

import '../models/graph_settings.dart';
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
    await _migrateLegacyAiConfig();
  }

  /// Bản cũ lưu chung một API key / model cho mọi provider, nên đổi tab
  /// Gemini <-> OpenAI vẫn hiện lại cùng một key. Di chuyển giá trị cũ (nếu
  /// có) sang đúng slot của provider đang chọn lúc đó, chạy một lần duy nhất.
  Future<void> _migrateLegacyAiConfig() async {
    final prefs = _prefs!;
    final legacyKey = prefs.getString(AppConstants.keyAiApiKey);
    final legacyModel = prefs.getString(AppConstants.keyAiModel);
    if (legacyKey == null && legacyModel == null) return;

    final provider =
        prefs.getString(AppConstants.keyAiProvider) ?? AppConstants.providerGemini;
    if (legacyKey != null) {
      await prefs.setString(_apiKeyStorageKey(provider), legacyKey);
      await prefs.remove(AppConstants.keyAiApiKey);
    }
    if (legacyModel != null) {
      await prefs.setString(_modelStorageKey(provider), legacyModel);
      await prefs.remove(AppConstants.keyAiModel);
    }
  }

  String _apiKeyStorageKey(String provider) => '${AppConstants.keyAiApiKey}_$provider';
  String _modelStorageKey(String provider) => '${AppConstants.keyAiModel}_$provider';
  String _lightModelStorageKey(String provider) =>
      '${AppConstants.keyAiLightModel}_$provider';

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

  /// Thư mục con trong Vault mà lần "Ghi ra Vault" gần nhất đã dùng.
  ///
  /// Nhớ lại để người dùng không phải gõ lại mỗi lần — và quan trọng hơn, để
  /// lần ghi sau không vô tình rơi về gốc Vault rồi đẻ ra một bộ file trùng.
  Future<String?> getExportSubFolder() async =>
      (await _p).getString(AppConstants.keyExportSubFolder);

  Future<void> setExportSubFolder(String? folder) async {
    final prefs = await _p;
    if (folder == null || folder.isEmpty) {
      await prefs.remove(AppConstants.keyExportSubFolder);
    } else {
      await prefs.setString(AppConstants.keyExportSubFolder, folder);
    }
  }

  // --- AI ---

  Future<String> getAiProvider() async =>
      (await _p).getString(AppConstants.keyAiProvider) ??
      AppConstants.providerGemini;

  Future<void> setAiProvider(String provider) async =>
      (await _p).setString(AppConstants.keyAiProvider, provider);

  /// [provider] mặc định là provider đang được chọn nếu không truyền vào.
  /// Mỗi provider (Gemini / OpenAI) có API key riêng, đổi tab không còn dùng
  /// chung một key nữa.
  Future<String?> getApiKey([String? provider]) async {
    final p = provider ?? await getAiProvider();
    return (await _p).getString(_apiKeyStorageKey(p));
  }

  Future<void> setApiKey(String? key, [String? provider]) async {
    final prefs = await _p;
    final p = provider ?? await getAiProvider();
    final value = key?.trim() ?? '';
    if (value.isEmpty) {
      await prefs.remove(_apiKeyStorageKey(p));
    } else {
      await prefs.setString(_apiKeyStorageKey(p), value);
    }
  }

  /// Tương tự [getApiKey]: model cũng lưu riêng theo từng provider.
  Future<String> getModel([String? provider]) async {
    final prefs = await _p;
    final p = provider ?? await getAiProvider();
    final saved = prefs.getString(_modelStorageKey(p));
    if (saved != null && saved.isNotEmpty) return saved;
    return p == AppConstants.providerOpenAi
        ? AppConstants.defaultOpenAiModel
        : AppConstants.defaultGeminiModel;
  }

  /// Model dành cho tác vụ phụ. Rỗng nghĩa là dùng chung model chính.
  ///
  /// Mục đích là tách hạn mức gọi (Gemini tính RPM/TPM/RPD riêng theo từng
  /// model), để việc sinh câu hỏi gợi ý không ăn vào hạn mức của model đang
  /// dùng để trả lời người dùng.
  Future<String?> getLightModel([String? provider]) async {
    final p = provider ?? await getAiProvider();
    final saved = (await _p).getString(_lightModelStorageKey(p));
    return saved != null && saved.isNotEmpty ? saved : null;
  }

  Future<void> setLightModel(String? model, [String? provider]) async {
    final prefs = await _p;
    final p = provider ?? await getAiProvider();
    final value = model?.trim() ?? '';
    if (value.isEmpty) {
      await prefs.remove(_lightModelStorageKey(p));
    } else {
      await prefs.setString(_lightModelStorageKey(p), value);
    }
  }

  Future<void> setModel(String? model, [String? provider]) async {
    final prefs = await _p;
    final p = provider ?? await getAiProvider();
    final value = model?.trim() ?? '';
    if (value.isEmpty) {
      await prefs.remove(_modelStorageKey(p));
    } else {
      await prefs.setString(_modelStorageKey(p), value);
    }
  }

  // --- Theme ---

  Future<String> getThemeMode() async =>
      (await _p).getString(AppConstants.keyThemeMode) ?? 'dark';

  Future<void> setThemeMode(String mode) async =>
      (await _p).setString(AppConstants.keyThemeMode, mode);

  // --- Graph Settings ---

  static const String _keyGraphSettings = 'graph_custom_settings';

  Future<GraphSettings> getGraphSettings() async {
    final raw = (await _p).getString(_keyGraphSettings);
    if (raw == null || raw.isEmpty) return GraphSettings.defaults;
    return GraphSettings.fromJson(raw);
  }

  Future<void> setGraphSettings(GraphSettings settings) async {
    final prefs = await _p;
    await prefs.setString(_keyGraphSettings, settings.toJson());
  }

  // --- FAP / FLM Auto-Save ---

  Future<bool> getAutoSaveFapNotes() async =>
      (await _p).getBool('auto_save_fap_notes') ?? true;

  Future<void> setAutoSaveFapNotes(bool value) async =>
      (await _p).setBool('auto_save_fap_notes', value);

  // --- Bảng điểm cá nhân ---

  /// Có gửi bảng điểm kèm câu hỏi cho AI không. Mặc định bật vì đó là điều
  /// làm câu trả lời có ích, nhưng vẫn phải tắt được: điểm số sẽ rời khỏi máy
  /// và đi tới nhà cung cấp AI bên ngoài, người dùng có quyền quyết định.
  Future<bool> getSendTranscriptToAi() async =>
      (await _p).getBool('send_transcript_to_ai') ?? true;

  Future<void> setSendTranscriptToAi(bool value) async =>
      (await _p).setBool('send_transcript_to_ai', value);

  /// GPA tốt nghiệp người dùng đặt làm mục tiêu. 8.0 là mốc Giỏi của FPTU.
  Future<double> getTargetGpa() async =>
      (await _p).getDouble('target_gpa') ?? 8.0;

  Future<void> setTargetGpa(double value) async =>
      (await _p).setDouble('target_gpa', value);
}

