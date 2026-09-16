import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';


class FlmAuthResult {
  final String cookie;
  final String? html;
  final String? actualUrl;
  final bool isSuccess;
  final String? errorMessage;

  const FlmAuthResult({
    required this.cookie,
    this.html,
    this.actualUrl,
    this.isSuccess = true,
    this.errorMessage,
  });

  factory FlmAuthResult.failure(String message) => FlmAuthResult(
        cookie: '',
        isSuccess: false,
        errorMessage: message,
      );
}

/// Dịch vụ mở In-App WebView đăng nhập Google FPT và tự động trích xuất Cookie & Khung chương trình
class FlmAuthService {
  FlmAuthService._();
  static final FlmAuthService instance = FlmAuthService._();

  static const String _cookiePrefKey = 'flm_saved_cookie';

  /// Kiểm tra xem WebView2 có sẵn trên hệ thống hay không
  Future<String?> checkWebviewAvailabilityError() async {
    try {
      final available = await WebviewWindow.isWebviewAvailable();
      if (!available) {
        return 'Hệ thống chưa cài đặt Microsoft Edge WebView2 Runtime. Vui lòng cài đặt từ trang Microsoft.';
      }
      return null;
    } catch (e) {
      final err = e.toString();
      if (err.contains('MissingPluginException') || err.contains('No implementation found')) {
        return 'Cần khởi động lại app: Hãy bấm "q" trong terminal rồi chạy lại "flutter run -d windows" để biên dịch C++ plugin mới!';
      }
      return 'Lỗi kiểm tra WebView: $err';
    }
  }

  Future<bool> isWebviewAvailable() async {
    return (await checkWebviewAvailabilityError()) == null;
  }

  /// Lấy Cookie đã lưu trong SharedPreferences từ phiên trước
  Future<String?> getSavedCookie() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_cookiePrefKey);
    } catch (e) {
      dev.log('Lỗi đọc saved cookie: $e');
      return null;
    }
  }

  /// Xoá Cookie đã lưu trong máy
  Future<void> clearSavedCookie() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cookiePrefKey);
    } catch (e) {
      dev.log('Lỗi xoá saved cookie: $e');
    }
  }

  /// Làm sạch chuỗi trả về từ JavaScript (unquote & unescape JSON string nếu có)
  String _cleanJsString(String? raw) {
    if (raw == null) return '';
    final trimmed = raw.trim();
    if (trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.length >= 2) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is String) return decoded;
      } catch (_) {
        return trimmed.substring(1, trimmed.length - 1);
      }
    }
    return trimmed;
  }

  /// Mở cửa sổ WebView2 điều hướng đến FLM:
  /// - Người dùng đăng nhập Google bằng email @fpt.edu.vn.
  /// - Giữ cửa sổ mở để người dùng đăng nhập và điều hướng đến Khung chương trình mong muốn.
  /// - Có nút nổi "⚡ LẤY KHUNG NÀY" trực tiếp trên trang web để người dùng bấm bất cứ lúc nào.
  /// - Tự động phát hiện khi đã vào trang CurriculumDetails có bảng môn học hợp lệ.
  /// - Trích xuất Cookie chính thức (.AspNet.cookies), URL thực tế và mã HTML đã render.
  Future<FlmAuthResult> loginAndExtractCookie({
    String targetUrl = 'https://flm.fpt.edu.vn/gui/role/student/CurriculumDetails?curid=3005',
    ValueChanged<String>? onStatusUpdate,
  }) async {
    final availabilityError = await checkWebviewAvailabilityError();
    if (availabilityError != null) {
      return FlmAuthResult.failure(availabilityError);
    }

    try {
      onStatusUpdate?.call('Đang khởi tạo cửa sổ WebView2...');

      // Lưu trữ profile riêng cho WebView2 để duy trì đăng nhập Google cho các lần sau
      final supportDir = await getApplicationSupportDirectory();
      final webviewDataDir = Directory(p.join(supportDir.path, 'flm_webview_data'));
      if (!await webviewDataDir.exists()) {
        await webviewDataDir.create(recursive: true);
      }

      final webview = await WebviewWindow.create(
        configuration: CreateConfiguration(
          userDataFolderWindows: webviewDataDir.path,
          title: 'Đăng nhập FPT FLM & Lấy Khung chương trình',
          titleBarTopPadding: Platform.isMacOS ? 20 : 0,
        ),
      );

      final completer = Completer<FlmAuthResult>();
      Timer? pollTimer;
      bool hasCaptured = false;
      bool hasAutoNavigatedToTarget = false;

      // Xử lý khi người dùng bấm nút đóng cửa sổ (X)
      webview.onClose.then((_) {
        pollTimer?.cancel();
        if (!completer.isCompleted && !hasCaptured) {
          completer.complete(
            FlmAuthResult.failure('Cửa sổ đăng nhập đã được đóng.'),
          );
        }
      });

      // Hàm trích xuất dữ liệu hoàn chỉnh và hoàn tất
      Future<void> captureAndComplete({bool isManual = false}) async {
        if (hasCaptured || completer.isCompleted) return;

        try {
          final cookies = await webview.getAllCookies();

          // Kiểm tra xem đã thực sự đăng nhập chưa
          final hasAuthCookie = cookies.any((c) =>
              c.name == '.AspNet.cookies' ||
              c.name.startsWith('.AspNet.') ||
              c.name.toLowerCase().contains('fedauth'));

          if (!hasAuthCookie && !isManual) {
            // Chưa đăng nhập thì không thể capture tự động
            return;
          }

          hasCaptured = true;
          pollTimer?.cancel();
          onStatusUpdate?.call('Đang bóc tách dữ liệu từ trang web FLM...');

          // Lấy URL trang web hiện tại
          final rawUrl = await webview.evaluateJavaScript('window.location.href');
          final currentUrl = _cleanJsString(rawUrl);

          // Lấy toàn bộ mã nguồn HTML đã render trong DOM
          final rawHtml =
              await webview.evaluateJavaScript('document.documentElement.outerHTML');
          final htmlContent = _cleanJsString(rawHtml);

          // Thu thập các cookie của FLM
          final relevantCookies = cookies.where((c) {
            return c.domain.contains('flm.fpt.edu.vn') ||
                c.name == '.AspNet.cookies' ||
                c.name.startsWith('.AspNet.') ||
                c.name == 'ASP.NET_SessionId' ||
                c.name == 'cf_clearance';
          }).toList();

          final cookieListToUse =
              relevantCookies.isNotEmpty ? relevantCookies : cookies;

          final cookieString = cookieListToUse
              .map((c) => '${c.name}=${c.value}')
              .join('; ');

          // Lưu cookie vào cache cục bộ
          if (cookieString.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_cookiePrefKey, cookieString);
          }

          try {
            webview.close();
          } catch (_) {}

          if (!completer.isCompleted) {
            completer.complete(FlmAuthResult(
              cookie: cookieString,
              html: htmlContent.isNotEmpty ? htmlContent : null,
              actualUrl: currentUrl.isNotEmpty ? currentUrl : targetUrl,
            ));
          }
        } catch (e, stack) {
          dev.log('Lỗi trích xuất từ WebView: $e', stackTrace: stack);
          hasCaptured = false; // Cho phép thử lại
        }
      }

      // Cấu hình User-Agent tiêu chuẩn để Google Login không từ chối WebView2
      try {
        await webview.setApplicationNameForUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0',
        );
      } catch (_) {}

      // QUAN TRỌNG: Luôn trả về true trong callback điều hướng để WebView2 không huỷ bỏ request
      webview.setOnUrlRequestCallback((url) {
        dev.log('WebView navigating to: $url');
        return true;
      });

      // Tiêm script tối ưu hoá trang đăng nhập FLM & tạo nút nổi "⚡ LẤY KHUNG NÀY"
      const helperScript = '''
      (function() {
        // 1. Hiển thị thông báo alert của FLM thành khung cảnh báo trực quan
        window.alert = function(msg) {
          var box = document.getElementById('flm-alert-box');
          if (!box) {
            box = document.createElement('div');
            box.id = 'flm-alert-box';
            box.style.cssText = 'position:fixed;top:16px;left:50%;transform:translateX(-50%);background:#ef4444;color:#fff;padding:10px 20px;border-radius:12px;z-index:2147483647;font-weight:600;font-size:13px;box-shadow:0 8px 25px rgba(0,0,0,0.45);font-family:Segoe UI,sans-serif;';
            document.body.appendChild(box);
          }
          box.innerText = '⚠️ ' + msg;
          setTimeout(function() { if (box) box.remove(); }, 4500);
        };

        // 2. Tối ưu trang đăng nhập https://flm.fpt.edu.vn/login
        function setupLoginHelpers() {
          var currentHref = window.location.href;

          // A. Xử lý khi ở trang đăng nhập chính của FLM
          if (currentHref.includes('flm.fpt.edu.vn') && (currentHref.includes('/login') || currentHref.includes('/Login'))) {
            var select = document.getElementById('drSelectEduLevel');
            if (select && (!select.value || select.value === '')) {
              select.value = 'fptu';
              localStorage.setItem('SelectedEduLevel', 'fptu');
              var evt = new Event('change', { bubbles: true });
              select.dispatchEvent(evt);
            }

            // Thay thế nút Google GIS (vốn bị WebView2 chặn popup) bằng nút chuyển hướng OAuth chuẩn
            var googleWrapper = document.querySelector('.google-signin-wrapper');
            if (googleWrapper && !document.getElementById('flm-oauth-google-btn')) {
              var oldGsi = googleWrapper.querySelector('.g_id_signin');
              if (oldGsi) oldGsi.style.display = 'none';

              var oauthBtn = document.createElement('button');
              oauthBtn.id = 'flm-oauth-google-btn';
              oauthBtn.type = 'button';
              oauthBtn.innerHTML = '<svg style="width:18px;height:18px;margin-right:8px;vertical-align:middle;" viewBox="0 0 24 24"><path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/><path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/><path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z"/><path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"/></svg><span style="vertical-align:middle;">Đăng nhập bằng Google (@fpt.edu.vn)</span>';
              oauthBtn.style.cssText = 'display:flex;align-items:center;justify-content:center;background:#ffffff;color:#374151;font-weight:600;font-size:14px;border:1.5px solid #d1d5db;border-radius:24px;padding:8px 18px;cursor:pointer;box-shadow:0 2px 6px rgba(0,0,0,0.08);width:100%;max-width:300px;height:42px;margin:0 auto;';
              oauthBtn.onmouseover = function() { oauthBtn.style.background = '#f9fafb'; oauthBtn.style.borderColor = '#9ca3af'; };
              oauthBtn.onmouseout = function() { oauthBtn.style.background = '#ffffff'; oauthBtn.style.borderColor = '#d1d5db'; };
              oauthBtn.onclick = function(e) {
                e.preventDefault();
                window.location.href = '/Home/Login?educationLevel=fptu';
              };
              googleWrapper.appendChild(oauthBtn);
            }
          }

          // B. Tự động chuyển tiếp trên cổng FEID (feid.fpt.edu.vn) vào thẳng Google
          if (currentHref.includes('feid.fpt.edu.vn')) {
            var googleLink = document.querySelector('a[href*="scheme=Google"]');
            if (googleLink && !googleLink.dataset.autoTriggered) {
              googleLink.dataset.autoTriggered = 'true';
              googleLink.click();
            }
          }
        }

        // 3. Tạo nút nổi "⚡ LẤY KHUNG NÀY"
        function injectHelper() {
          setupLoginHelpers();

          if (!document.body || document.getElementById('flm-se-knowledge-helper')) return;
          var banner = document.createElement('div');
          banner.id = 'flm-se-knowledge-helper';
          banner.style.cssText = 'position:fixed;bottom:20px;right:20px;z-index:2147483647;display:flex;align-items:center;gap:10px;background:rgba(24,24,27,0.95);backdrop-filter:blur(8px);color:#f4f4f5;padding:8px 16px;border-radius:24px;box-shadow:0 8px 30px rgba(0,0,0,0.6);border:1.5px solid #22c55e;font-family:Segoe UI,sans-serif;font-size:12px;';
          
          var text = document.createElement('span');
          text.innerText = '🎓 SE Knowledge: Mở CTĐT rồi bấm ->';
          
          var btn = document.createElement('button');
          btn.innerText = '⚡ LẤY KHUNG NÀY';
          btn.style.cssText = 'background:#22c55e;color:#052e16;font-weight:700;border:none;padding:6px 14px;border-radius:16px;cursor:pointer;font-size:12px;transition:0.2s;';
          btn.onmouseover = function() { btn.style.background = '#4ade80'; };
          btn.onmouseout = function() { btn.style.background = '#22c55e'; };
          btn.onclick = function(e) {
            e.preventDefault();
            e.stopPropagation();
            if (window.chrome && window.chrome.webview) {
              window.chrome.webview.postMessage(JSON.stringify({action: 'CAPTURE_NOW'}));
            }
          };
          
          banner.appendChild(text);
          banner.appendChild(btn);
          document.body.appendChild(banner);
        }

        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', injectHelper);
        } else {
          injectHelper();
        }
        setInterval(injectHelper, 1200);
      })();
      ''';

      webview.addScriptToExecuteOnDocumentCreated(helperScript);

      // Nhận tin nhắn khi người dùng bấm nút nổi trên trang web
      webview.addOnWebMessageReceivedCallback((message) {
        dev.log('Nhận tín hiệu từ WebView JS: $message');
        if (message.contains('CAPTURE_NOW')) {
          onStatusUpdate?.call('Người dùng bấm lấy khung chương trình! Đang xử lý...');
          captureAndComplete(isManual: true);
        }
      });

      // Vòng lặp kiểm tra thông minh trạng thái đăng nhập và bảng dữ liệu (mỗi 1.5 giây)
      pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
        if (hasCaptured || completer.isCompleted) {
          timer.cancel();
          return;
        }

        try {
          final cookies = await webview.getAllCookies();

          // 1. Kiểm tra xem người dùng đã đăng nhập Google thành công chưa
          final hasAuthCookie = cookies.any((c) =>
              c.name == '.AspNet.cookies' ||
              c.name.startsWith('.AspNet.') ||
              c.name.toLowerCase().contains('fedauth'));

          if (!hasAuthCookie) {
            onStatusUpdate?.call('Vui lòng bấm "Sign in with Google" trên trang đăng nhập FLM...');
            return;
          }

          // 2. Người dùng ĐÃ đăng nhập!
          final rawUrl = await webview.evaluateJavaScript('window.location.href');
          final currentUrl = _cleanJsString(rawUrl);

          final isCurriculumPage = currentUrl.contains('CurriculumDetails') ||
              currentUrl.contains('/curriculum') ||
              currentUrl.contains('curid=');

          if (!isCurriculumPage) {
            // Nếu người dùng vừa đăng nhập xong mà đang ở trang Login/Home,
            // tự động chuyển hướng họ vào targetUrl mong muốn
            if (!hasAutoNavigatedToTarget &&
                targetUrl.contains('CurriculumDetails') &&
                !targetUrl.contains('login')) {
              hasAutoNavigatedToTarget = true;
              onStatusUpdate?.call('Đăng nhập thành công! Đang tự động mở Khung chương trình...');
              webview.launch(targetUrl, triggerOnUrlRequestEvent: false);
              return;
            } else {
              onStatusUpdate?.call('Đã đăng nhập! Hãy mở Khung chương trình cần lấy rồi bấm "LẤY KHUNG NÀY"...');
              return;
            }
          }

          // 3. Nếu ĐANG ở trang CurriculumDetails:
          // Kiểm tra xem bảng môn học đã hiển thị đầy đủ trong DOM chưa
          final hasTableCheck = await webview.evaluateJavaScript(
            '(document.querySelectorAll("table tr").length > 3).toString()',
          );
          final hasTable = _cleanJsString(hasTableCheck) == 'true';

          if (hasTable) {
            onStatusUpdate?.call('Đã phát hiện bảng môn học! Đang tự động nạp dữ liệu...');
            timer.cancel();
            await captureAndComplete();
          } else {
            onStatusUpdate?.call('Đang tải nội dung Khung chương trình...');
          }
        } catch (e) {
          dev.log('Lỗi kiểm tra chu kỳ WebView: $e');
        }
      });

      // Mở trang đăng nhập FLM chính thức (https://flm.fpt.edu.vn/login)
      // Sử dụng triggerOnUrlRequestEvent: false để tải ngay lập tức không bị huỷ
      const officialLoginUrl = 'https://flm.fpt.edu.vn/login';
      final initialUrl = targetUrl.contains('login') ? targetUrl : officialLoginUrl;
      onStatusUpdate?.call('Đang mở trang đăng nhập FLM ($initialUrl)...');
      webview.launch(initialUrl, triggerOnUrlRequestEvent: false);

      return await completer.future;
    } catch (e, stack) {
      dev.log('Lỗi khởi tạo WebView: $e', stackTrace: stack);
      return FlmAuthResult.failure('Không thể mở WebView: $e');
    }
  }
}

