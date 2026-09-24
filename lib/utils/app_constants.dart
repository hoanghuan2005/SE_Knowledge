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
  static const String defaultOpenAiModel = 'gpt-6-sol';

  /// Model chọn được cho việc trả lời người dùng, tách theo nhà cung cấp.
  ///
  /// Nhãn kèm **giá vào / giá ra cho 1 triệu token** vì đây là thông tin duy
  /// nhất giúp chọn có cơ sở: chênh lệch giữa hai đầu danh sách tới 100 lần,
  /// mà chỉ nhìn tên thì không đoán được. Một câu chat của app tốn ~900 token
  /// vào và ~800 token ra, nên `gpt-6-luna` rơi vào khoảng 0.05 cent/câu còn
  /// `gpt-6-astra` khoảng 4 cent/câu.
  ///
  /// Không liệt kê bản Pro (`gpt-5.5-pro` 180 USD/1M token ra) và các model
  /// chuyên code (`gpt-5.3-codex`): đắt hoặc lệch mục đích so với việc giải
  /// thích lộ trình học bằng tiếng Việt.
  static const List<({String id, String label})> openAiChatModels = [
    (id: 'gpt-6-sol', label: 'GPT-6 Sol — \$2 / \$10'),
    (id: 'gpt-6-astra', label: 'GPT-6 Astra — \$10 / \$50 (mạnh nhất)'),
    (id: 'gpt-6-luna', label: 'GPT-6 Luna — \$0.10 / \$0.50 (rẻ nhất)'),
    (id: 'gpt-5.6-sol', label: 'GPT-5.6 Sol — \$4 / \$20'),
    (id: 'gpt-5.6-terra', label: 'GPT-5.6 Terra — \$2 / \$12'),
    (id: 'gpt-5.6-luna', label: 'GPT-5.6 Luna — \$0.20 / \$1.20'),
    (id: 'gpt-5.5', label: 'GPT-5.5 — \$5 / \$30'),
    (id: 'gpt-5.4', label: 'GPT-5.4 — \$2.50 / \$15'),
    (id: 'gpt-5.4-mini', label: 'GPT-5.4 Mini — \$0.75 / \$4.50'),
    (id: 'gpt-5.1', label: 'GPT-5.1 — \$1.25 / \$10'),
    (id: 'gpt-4.1-mini', label: 'GPT-4.1 Mini — \$0.40 / \$1.60'),
    (id: 'gpt-4o-mini', label: 'GPT-4o Mini — \$0.15 / \$0.60'),
  ];

  /// Gemini chưa có bảng giá đối chiếu trong tay nên nhãn để trơn — thà thiếu
  /// thông tin còn hơn ghi một con số không kiểm chứng được.
  static const List<({String id, String label})> geminiChatModels = [
    (id: 'gemini-3.6-flash', label: 'Gemini 3.6 Flash'),
    (id: 'gemini-3.5-flash', label: 'Gemini 3.5 Flash'),
    (id: 'gemini-2.5-flash', label: 'Gemini 2.5 Flash'),
    (id: 'gemini-3.5-flash-lite', label: 'Gemini 3.5 Flash-Lite'),
    (id: 'gemini-3.1-flash-lite', label: 'Gemini 3.1 Flash-Lite'),
    (id: 'gemini-2.5-flash-lite', label: 'Gemini 2.5 Flash-Lite'),
  ];

  static List<({String id, String label})> chatModelsOf(String provider) =>
      provider == providerOpenAi ? openAiChatModels : geminiChatModels;

  static String defaultModelOf(String provider) =>
      provider == providerOpenAi ? defaultOpenAiModel : defaultGeminiModel;

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

  /// Bên OpenAI tiêu chí chọn khác Gemini: hạn mức tính trên cả tổ chức chứ
  /// không tách theo từng model, nên ở đây lý do thuần là **giá**. Chọn các
  /// model rẻ nhất còn viết được tiếng Việt gọn gàng — việc phụ chỉ là sinh 4
  /// câu hỏi gợi ý, không cần suy luận.
  static const List<({String id, String label})> openAiLightModels = [
    (id: 'gpt-6-luna', label: 'GPT-6 Luna — \$0.10 / \$0.50'),
    (id: 'gpt-5-nano', label: 'GPT-5 nano — \$0.05 / \$0.40 (rẻ nhất)'),
    (id: 'gpt-4.1-nano', label: 'GPT-4.1 nano — \$0.10 / \$0.40'),
    (id: 'gpt-5.4-nano', label: 'GPT-5.4 nano — \$0.20 / \$1.25'),
    (id: 'gpt-5.6-luna', label: 'GPT-5.6 Luna — \$0.20 / \$1.20'),
    (id: 'gpt-4o-mini', label: 'GPT-4o Mini — \$0.15 / \$0.60'),
  ];

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

  /// Cùng tiêu chí với [geminiFallbackModels]: hai model đủ mạnh để thay chỗ
  /// model chính trước, model rẻ để cuối cùng — thà trả lời gọn còn hơn báo
  /// lỗi. `gpt-6-astra` cố tình không có mặt: nó đắt gấp 5 lần `gpt-6-sol`,
  /// mà đường này chạy tự động nên người dùng không kịp biết để từ chối.
  static const List<String> openAiFallbackModels = [
    'gpt-6-sol',
    'gpt-5.6-sol',
    'gpt-6-luna',
  ];

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
