import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/services/settings_service.dart';
import 'package:se_knowledge/utils/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kiểm thử việc tách cấu hình theo từng nhà cung cấp.
///
/// Đây là lỗi đã gặp thật: đổi tab Gemini ↔ OpenAI mà ô API key vẫn hiện key
/// của bên kia, và bấm Lưu lúc đó ghi đè key cũ sang slot của provider mới —
/// tức mất key đã lưu trước đó.
void main() {
  final settings = SettingsService.instance;

  // `SettingsService` là singleton và giữ lại instance SharedPreferences, nên
  // không nạp lại thì test sau đọc phải dữ liệu test trước.
  Future<void> resetPrefs([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    await settings.init();
  }

  setUp(resetPrefs);

  const gemini = AppConstants.providerGemini;
  const openAi = AppConstants.providerOpenAi;

  test('mỗi nhà cung cấp giữ API key riêng', () async {
    await settings.setApiKey('khoa-gemini', gemini);
    await settings.setApiKey('khoa-openai', openAi);

    expect(await settings.getApiKey(gemini), 'khoa-gemini');
    expect(await settings.getApiKey(openAi), 'khoa-openai');
  });

  test('lưu key bên này không đụng vào key bên kia', () async {
    await settings.setApiKey('khoa-gemini', gemini);
    await settings.setApiKey('khoa-openai', openAi);
    await settings.setApiKey('khoa-openai-moi', openAi);

    expect(await settings.getApiKey(gemini), 'khoa-gemini');
    expect(await settings.getApiKey(openAi), 'khoa-openai-moi');
  });

  test('đổi provider đang chọn thì đọc đúng key của provider đó', () async {
    await settings.setApiKey('khoa-gemini', gemini);
    await settings.setApiKey('khoa-openai', openAi);

    await settings.setAiProvider(openAi);
    expect(await settings.getApiKey(), 'khoa-openai');

    await settings.setAiProvider(gemini);
    expect(await settings.getApiKey(), 'khoa-gemini');
  });

  test('chưa đặt key cho một bên thì bên đó trả về null', () async {
    await settings.setApiKey('chi-co-gemini', gemini);
    expect(await settings.getApiKey(openAi), isNull);
  });

  test('model và model phụ cũng tách theo nhà cung cấp', () async {
    await settings.setModel('gemini-3.6-flash', gemini);
    await settings.setModel('gpt-6-sol', openAi);
    await settings.setLightModel('gemini-2.5-flash-lite', gemini);
    await settings.setLightModel('gpt-5-nano', openAi);

    expect(await settings.getModel(gemini), 'gemini-3.6-flash');
    expect(await settings.getModel(openAi), 'gpt-6-sol');
    expect(await settings.getLightModel(gemini), 'gemini-2.5-flash-lite');
    expect(await settings.getLightModel(openAi), 'gpt-5-nano');
  });

  test('chưa đặt gì thì mỗi bên nhận model mặc định của mình', () async {
    expect(await settings.getModel(gemini), AppConstants.defaultGeminiModel);
    expect(await settings.getModel(openAi), AppConstants.defaultOpenAiModel);
  });
}
