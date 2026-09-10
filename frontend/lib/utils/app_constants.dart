/// Định nghĩa các hằng số dùng chung trong toàn bộ app.
class AppConstants {
  AppConstants._();

  // Thông tin ứng dụng
  static const String appName = 'SE Knowledge';
  static const String appVersion = '1.0.0';

  // API Configs
  static const String baseUrl = 'http://10.0.2.2:5000/api'; // 10.0.2.2 cho Android Emulator
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);

  // Storage keys (SharedPreferences / SecureStorage)
  static const String keyAccessToken = 'ACCESS_TOKEN';
  static const String keyRefreshToken = 'REFRESH_TOKEN';
  static const String keyUserData = 'USER_DATA';
  static const String keyThemeMode = 'THEME_MODE';

  // UI Paddings & Margins
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double borderRadius = 12.0;
}
