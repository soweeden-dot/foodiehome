import 'package:supabase_flutter/supabase_flutter.dart';

import 'foodie_gateway.dart';

class SupabaseFoodieGateway implements FoodieGateway {
  SupabaseFoodieGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<FoodieReply> sendMessage({
    required String message,
    String? conversationId,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'foodie-agent',
        body: {
          'message': message,
          'conversation_id': ?conversationId,
        },
      );
      return FoodieReply.fromJson(response.data as Map<String, dynamic>);
    } on FunctionException catch (e) {
      final error = (e.details is Map<String, dynamic>)
          ? (e.details as Map<String, dynamic>)['error']
          : null;
      if (error is Map<String, dynamic>) {
        throw FoodieRequestException(
          error['code'] as String? ?? 'internal',
          error['message'] as String? ?? 'Foodie hit an error.',
        );
      }
      throw const FoodieRequestException(
          'internal', 'Foodie is unreachable right now.');
    }
  }
}
