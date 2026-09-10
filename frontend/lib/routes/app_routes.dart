import 'package:flutter/material.dart';
import '../screens/home/home_screen.dart';
import '../screens/not_found_screen.dart';
import '../screens/splash/splash_screen.dart';

/// Quản lý toàn bộ điều hướng (Routing) trong ứng dụng.
/// Các thành viên khi tạo màn hình mới chỉ cần:
/// 1. Khai báo thêm tên route dạng `static const String screenName = '/screenName';`
/// 2. Thêm case tương ứng vào hàm [onGenerateRoute].
class AppRoutes {
  AppRoutes._();

  // Route constants
  static const String initial = splash;
  static const String splash = '/splash';
  static const String home = '/home';
  static const String login = '/login';
  static const String register = '/register';

  /// Bộ điều hướng tập trung của ứng dụng
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    // Nhận arguments truyền vào nếu có: final args = settings.arguments;

    switch (settings.name) {
      case splash:
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
          settings: settings,
        );

      case home:
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );

      // Thêm các case mới ở đây:
      // case login:
      //   return MaterialPageRoute(
      //     builder: (_) => const LoginScreen(),
      //     settings: settings,
      //   );

      default:
        return MaterialPageRoute(
          builder: (_) => NotFoundScreen(routeName: settings.name),
          settings: settings,
        );
    }
  }
}
