import '../utils/app_constants.dart';

/// Base Service quản lý lưu trữ Local Storage / In-memory Session.
/// Khi team bổ sung dependency `shared_preferences` hoặc `flutter_secure_storage`,
/// các thành viên có thể gắn logic thật vào các hàm này.
class LocalStorageService {
  LocalStorageService._();
  static final LocalStorageService instance = LocalStorageService._();

  // In-memory cache mẫu
  final Map<String, dynamic> _memoryCache = {};

  Future<void> saveToken(String token) async {
    _memoryCache[AppConstants.keyAccessToken] = token;
  }

  Future<String?> getToken() async {
    return _memoryCache[AppConstants.keyAccessToken] as String?;
  }

  Future<void> clearAll() async {
    _memoryCache.clear();
  }
}
