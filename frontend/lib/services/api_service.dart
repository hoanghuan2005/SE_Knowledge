import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/base_response.dart';
import '../utils/app_constants.dart';

/// Base API Service để gửi các HTTP request tới Backend.
/// Có thể mở rộng sử dụng thư viện `http` hoặc `dio` tùy nhu cầu team.
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  final String baseUrl = AppConstants.baseUrl;

  /// Lấy headers mặc định (kèm token nếu đã đăng nhập)
  Map<String, String> getHeaders({String? token}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Hàm mẫu GET request
  Future<BaseResponse<T>> get<T>({
    required String endpoint,
    String? token,
    T Function(dynamic json)? fromJsonT,
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = AppConstants.connectTimeout;

      final uri = Uri.parse('$baseUrl$endpoint');
      final request = await client.getUrl(uri);

      getHeaders(token: token).forEach((key, value) {
        request.headers.set(key, value);
      });

      final response = await request.close().timeout(AppConstants.receiveTimeout);
      final responseBody = await response.transform(utf8.decoder).join();
      final json = jsonDecode(responseBody) as Map<String, dynamic>;

      return BaseResponse<T>.fromJson(json, fromJsonT);
    } on SocketException {
      return BaseResponse<T>(
        success: false,
        message: 'Không thể kết nối tới máy chủ. Vui lòng kiểm tra mạng.',
      );
    } on TimeoutException {
      return BaseResponse<T>(
        success: false,
        message: 'Kết nối quá thời gian quy định (Timeout).',
      );
    } catch (e) {
      return BaseResponse<T>(
        success: false,
        message: 'Đã xảy ra lỗi: ${e.toString()}',
      );
    }
  }

  /// Hàm mẫu POST request
  Future<BaseResponse<T>> post<T>({
    required String endpoint,
    required Map<String, dynamic> body,
    String? token,
    T Function(dynamic json)? fromJsonT,
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = AppConstants.connectTimeout;

      final uri = Uri.parse('$baseUrl$endpoint');
      final request = await client.postUrl(uri);

      getHeaders(token: token).forEach((key, value) {
        request.headers.set(key, value);
      });

      final bodyBytes = utf8.encode(jsonEncode(body));
      request.add(bodyBytes);

      final response = await request.close().timeout(AppConstants.receiveTimeout);
      final responseBody = await response.transform(utf8.decoder).join();
      final json = jsonDecode(responseBody) as Map<String, dynamic>;

      return BaseResponse<T>.fromJson(json, fromJsonT);
    } on SocketException {
      return BaseResponse<T>(
        success: false,
        message: 'Không thể kết nối tới máy chủ. Vui lòng kiểm tra mạng.',
      );
    } on TimeoutException {
      return BaseResponse<T>(
        success: false,
        message: 'Kết nối quá thời gian quy định (Timeout).',
      );
    } catch (e) {
      return BaseResponse<T>(
        success: false,
        message: 'Đã xảy ra lỗi: ${e.toString()}',
      );
    }
  }
}
