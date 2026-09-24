import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kiểm thử cache nhận xét học lực.
///
/// Sai ở đây tốn kém theo hai chiều ngược nhau: giữ quá lâu thì người dùng
/// đọc nhận xét đã lỗi thời sau khi nhập điểm mới, còn bỏ quá sớm thì mỗi lần
/// mở tab lại gọi AI cho đúng một câu trả lời y hệt.
void main() {
  final settings = SettingsService.instance;

  // `SettingsService` là singleton và giữ lại instance SharedPreferences, nên
  // không nạp lại thì test sau đọc phải dữ liệu test trước.
  Future<void> resetPrefs([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    await settings.init();
  }

  setUp(resetPrefs);

  test('đọc lại được nhận xét đã lưu khi dữ liệu không đổi', () async {
    await settings.setAcademicAiAnswers('sig-1', {'Điểm mạnh': 'Bạn khá Toán'});

    expect(await settings.getAcademicAiAnswers('sig-1'), {
      'Điểm mạnh': 'Bạn khá Toán',
    });
  });

  test('dữ liệu đổi thì bỏ hết nhận xét cũ', () async {
    // Nhập thêm bảng điểm mới ⇒ vân tay đổi ⇒ nhận xét cũ không còn đúng.
    await settings.setAcademicAiAnswers('sig-1', {'Điểm mạnh': 'Bạn khá Toán'});

    expect(await settings.getAcademicAiAnswers('sig-2'), isEmpty);
  });

  test('giữ được nhiều câu hỏi khác nhau cùng lúc', () async {
    await settings.setAcademicAiAnswers('sig-1', {
      'Điểm mạnh': 'A',
      'Rủi ro': 'B',
    });

    final cached = await settings.getAcademicAiAnswers('sig-1');
    expect(cached, hasLength(2));
    expect(cached['Rủi ro'], 'B');
  });

  test('chưa lưu gì thì trả rỗng chứ không ném lỗi', () async {
    expect(await settings.getAcademicAiAnswers('sig-1'), isEmpty);
  });

  test('lưu map rỗng thì xoá sạch cache', () async {
    await settings.setAcademicAiAnswers('sig-1', {'Điểm mạnh': 'A'});
    await settings.setAcademicAiAnswers('sig-1', {});

    expect(await settings.getAcademicAiAnswers('sig-1'), isEmpty);
  });

  test('dữ liệu lưu bị hỏng thì coi như chưa có, không làm chết màn hình', () async {
    await resetPrefs({'ACADEMIC_AI_CACHE': 'day khong phai json'});

    expect(await settings.getAcademicAiAnswers('sig-1'), isEmpty);
  });
}
