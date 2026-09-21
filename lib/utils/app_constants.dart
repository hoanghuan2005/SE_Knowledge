/// Hằng số dùng chung trong toàn bộ app.
class AppConstants {
  AppConstants._();

  // --- Thông tin ứng dụng ---
  static const String appName = 'SE Knowledge';
  static const String appTagline = 'Bản đồ tri thức môn học — Local First';
  static const String appVersion = '1.0.0';

  // --- Khoá lưu cấu hình cục bộ (SharedPreferences) ---
  static const String keyVaultPath = 'OBSIDIAN_VAULT_PATH';
  static const String keyAiProvider = 'AI_PROVIDER';
  static const String keyAiApiKey = 'AI_API_KEY';
  static const String keyAiModel = 'AI_MODEL';
  static const String keyThemeMode = 'THEME_MODE';

  // --- Nhà cung cấp AI ---
  static const String providerGemini = 'gemini';
  static const String providerOpenAi = 'openai';

  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta';
  static const String openAiBaseUrl = 'https://api.openai.com/v1';

  static const String defaultGeminiModel = 'gemini-3.6-flash';
  static const String defaultOpenAiModel = 'gpt-4o-mini';

  // --- Kích thước cửa sổ desktop ---
  static const double minWindowWidth = 1000;
  static const double minWindowHeight = 640;

  // --- Padding / bán kính bo góc ---
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double borderRadius = 12.0;
}
