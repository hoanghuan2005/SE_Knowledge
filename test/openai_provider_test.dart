import 'package:flutter_test/flutter_test.dart';
import 'package:se_knowledge/services/ai_service.dart';
import 'package:se_knowledge/utils/app_constants.dart';

/// Kiểm thử phần riêng của nhà cung cấp OpenAI: hợp đồng tham số theo họ
/// model, và tính nhất quán của các danh sách model trong Cài đặt.
void main() {
  group('họ model quyết định tên tham số', () {
    test('dòng suy luận dùng max_completion_tokens, bỏ temperature', () {
      for (final id in [
        'gpt-6-sol',
        'gpt-6-astra',
        'gpt-6-luna',
        'gpt-5.6-terra',
        'gpt-5.4-mini',
        'gpt-5',
        'o3',
        'o4-mini',
      ]) {
        expect(openAiUsesReasoningParams(id), isTrue, reason: id);
        final body = openAiRequestBody(
          model: id,
          messages: const [],
          maxOutputTokens: 4096,
        );
        expect(body['max_completion_tokens'], 4096, reason: id);
        expect(body.containsKey('max_tokens'), isFalse, reason: id);
        expect(body.containsKey('temperature'), isFalse, reason: id);
      }
    });

    test('dòng cũ giữ nguyên max_tokens và temperature', () {
      for (final id in ['gpt-4o-mini', 'gpt-4.1-mini', 'gpt-4o']) {
        expect(openAiUsesReasoningParams(id), isFalse, reason: id);
        final body = openAiRequestBody(
          model: id,
          messages: const [],
          maxOutputTokens: 4096,
        );
        expect(body['max_tokens'], 4096, reason: id);
        expect(body['temperature'], 0.4, reason: id);
        expect(body.containsKey('max_completion_tokens'), isFalse, reason: id);
      }
    });

    test('không phân biệt hoa thường và khoảng trắng thừa', () {
      expect(openAiUsesReasoningParams('  GPT-6-Sol '), isTrue);
      expect(openAiUsesReasoningParams('GPT-4o-mini'), isFalse);
    });

    test('tên lạ thì chọn hợp đồng cũ, vì đó là dạng phổ biến hơn', () {
      expect(openAiUsesReasoningParams('llama-3'), isFalse);
      expect(openAiUsesReasoningParams(''), isFalse);
    });

    test('luôn bật stream', () {
      for (final id in ['gpt-6-sol', 'gpt-4o-mini']) {
        final body = openAiRequestBody(
          model: id,
          messages: const [],
          maxOutputTokens: 100,
        );
        expect(body['stream'], isTrue, reason: id);
      }
    });
  });

  group('danh sách model trong Cài đặt', () {
    test('hai nhà cung cấp đều có model chính, phụ và dự phòng', () {
      for (final p in [
        AppConstants.providerGemini,
        AppConstants.providerOpenAi,
      ]) {
        expect(AppConstants.chatModelsOf(p), isNotEmpty, reason: p);
        expect(AppConstants.lightModelsOf(p), isNotEmpty, reason: p);
        expect(AppConstants.fallbackModelsOf(p), isNotEmpty, reason: p);
      }
    });

    test('model mặc định nằm trong danh sách chọn được', () {
      for (final p in [
        AppConstants.providerGemini,
        AppConstants.providerOpenAi,
      ]) {
        final ids = AppConstants.chatModelsOf(p).map((m) => m.id);
        expect(ids, contains(AppConstants.defaultModelOf(p)), reason: p);
      }
    });

    test('không có id trùng trong cùng một danh sách', () {
      for (final p in [
        AppConstants.providerGemini,
        AppConstants.providerOpenAi,
      ]) {
        for (final list in [
          AppConstants.chatModelsOf(p).map((m) => m.id).toList(),
          AppConstants.lightModelsOf(p).map((m) => m.id).toList(),
          AppConstants.fallbackModelsOf(p),
        ]) {
          expect(list.toSet().length, list.length, reason: '$p $list');
        }
      }
    });

    test('chuỗi dự phòng bỏ model chính ra khỏi hàng đợi', () {
      final order = fallbackModelOrder(
        mainModel: 'gpt-6-sol',
        candidates: AppConstants.openAiFallbackModels,
      );
      expect(order, isNot(contains('gpt-6-sol')));
      expect(order, isNotEmpty);
    });

    test('dự phòng OpenAI không kéo vào model đắt nhất', () {
      // gpt-6-astra đắt gấp 5 lần gpt-6-sol và đường này chạy tự động, nên
      // người dùng không kịp biết để từ chối.
      expect(AppConstants.openAiFallbackModels, isNot(contains('gpt-6-astra')));
    });
  });
}
