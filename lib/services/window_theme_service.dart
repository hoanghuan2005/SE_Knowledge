import 'package:flutter/services.dart';

/// Đồng bộ màu thanh tiêu đề cửa sổ (viền do Windows vẽ, ngoài tầm với của
/// Flutter) theo đúng theme Tối/Sáng người dùng chọn trong Cài đặt.
///
/// Mặc định `flutter create` sinh ra chỉ đọc theme HỆ ĐIỀU HÀNH lúc mở cửa sổ
/// (`Win32Window::UpdateTheme`), không biết gì tới theme riêng của app. Kênh
/// này báo xuống native mỗi khi `AppState` đổi theme để thanh tiêu đề luôn
/// khớp với phần nội dung Flutter bên dưới.
class WindowThemeService {
  WindowThemeService._();

  static const MethodChannel _channel = MethodChannel('se_knowledge/window_theme');

  /// Không có tác dụng trên nền tảng khác Windows — gọi nhầm chỉ bị bỏ qua.
  static Future<void> setDarkTitleBar(bool isDark) async {
    try {
      await _channel.invokeMethod('setDarkTitleBar', isDark);
    } on MissingPluginException {
      // Chạy trên nền tảng không có runner Windows (test, web...).
    }
  }
}
