/// Hằng số dùng chung trong toàn bộ app.
class AppConstants {
  AppConstants._();

  // --- Thông tin ứng dụng ---
  static const String appName = 'SE Knowledge';
  static const String appTagline = 'Bản đồ tri thức môn học — Local First';
  static const String appVersion = '1.0.0';

  // --- Khoá lưu cấu hình cục bộ (SharedPreferences) ---
  static const String keyVaultPath = 'OBSIDIAN_VAULT_PATH';
  static const String keyExportSubFolder = 'OBSIDIAN_EXPORT_SUBFOLDER';
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

  /// Khoá lưu model dành cho tác vụ phụ, tách theo từng nhà cung cấp.
  static const String keyAiLightModel = 'AI_LIGHT_MODEL';

  /// Model chọn được cho tác vụ phụ (hiện chỉ có việc sinh câu hỏi gợi ý).
  ///
  /// Mục đích chính KHÔNG phải tiết kiệm tiền — sau khi cắt ngữ cảnh và
  /// prompt thì lời gọi đó chỉ còn ~292 token, rẻ tới mức không đáng bàn.
  /// Mục đích là **tách hạn mức**: Gemini tính RPM/TPM/RPD riêng cho từng
  /// model, nên đẩy việc phụ sang model khác thì nó thôi ăn vào hạn mức của
  /// model đang dùng để trả lời người dùng — đúng thứ đã gây lỗi 503 quá tải.
  ///
  /// Danh sách chép từ trang model chính thức, chỉ giữ nhóm sinh văn bản: đã
  /// bỏ TTS, Live, Transcribe, image và các bản Pro (đắt hơn model chính thì
  /// ngược mục đích).
  static const List<({String id, String label})> geminiLightModels = [
    (id: 'gemini-3.5-flash-lite', label: 'Gemini 3.5 Flash-Lite'),
    (id: 'gemini-3.1-flash-lite', label: 'Gemini 3.1 Flash-Lite'),
    (id: 'gemini-2.5-flash-lite', label: 'Gemini 2.5 Flash-Lite'),
    (id: 'gemini-3.5-flash', label: 'Gemini 3.5 Flash'),
    (id: 'gemini-2.5-flash', label: 'Gemini 2.5 Flash'),
  ];

  /// Chưa có danh sách ID đã kiểm chứng cho OpenAI, nên để trống — giao diện
  /// sẽ chỉ hiện mục "dùng model chính" thay vì bịa ra tên model.
  static const List<({String id, String label})> openAiLightModels = [];

  static List<({String id, String label})> lightModelsOf(String provider) =>
      provider == providerOpenAi ? openAiLightModels : geminiLightModels;

  /// Model dùng khi model chính quá tải, thử theo đúng thứ tự này.
  ///
  /// Khác với [geminiLightModels] ở mục đích nên cũng khác ở tiêu chí chọn:
  /// danh sách kia tối ưu cho rẻ và nhanh vì chỉ sinh câu hỏi gợi ý, còn
  /// danh sách này phải **thay thế model chính để trả lời người dùng**, nên
  /// ưu tiên bản Flash đầy đủ trước bản Lite.
  ///
  /// Có sẵn danh sách này để tính năng chạy được mà không cần người dùng cấu
  /// hình gì — 503 ập tới giữa buổi demo thì không kịp vào Cài đặt.
  static const List<String> geminiFallbackModels = [
    'gemini-3.5-flash',
    'gemini-2.5-flash',
    'gemini-3.5-flash-lite',
  ];

  static const List<String> openAiFallbackModels = [];

  static List<String> fallbackModelsOf(String provider) =>
      provider == providerOpenAi ? openAiFallbackModels : geminiFallbackModels;

  // --- Kích thước cửa sổ desktop ---
  static const double minWindowWidth = 1000;
  static const double minWindowHeight = 640;

  // --- Padding / bán kính bo góc ---
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double borderRadius = 12.0;
}
