/// Wrapper chuẩn cho kết quả trả về từ API Backend.
/// T là kiểu dữ liệu của payload (data).
class BaseResponse<T> {
  final bool success;
  final String message;
  final T? data;
  final int? statusCode;

  BaseResponse({
    required this.success,
    required this.message,
    this.data,
    this.statusCode,
  });

  factory BaseResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic json)? fromJsonT,
  ) {
    return BaseResponse<T>(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      data: json['data'] != null && fromJsonT != null
          ? fromJsonT(json['data'])
          : null,
      statusCode: json['statusCode'] as int?,
    );
  }

  Map<String, dynamic> toJson(Map<String, dynamic> Function(T value)? toJsonT) {
    return {
      'success': success,
      'message': message,
      'data': data != null && toJsonT != null ? toJsonT(data as T) : data,
      'statusCode': statusCode,
    };
  }
}
