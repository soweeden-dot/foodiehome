/// Client boundary for talking to the foodie-agent Edge Function.
///
/// [FoodieAction] entries reflect ACTUAL tool executions reported by the
/// server's audit pipeline — the UI shows these as the record of what
/// happened, independent of the model's prose.
library;

class FoodieAction {
  const FoodieAction({
    required this.tool,
    required this.status,
    required this.summary,
  });

  final String tool;
  final String status; // 'executed' | 'failed'
  final String summary;

  bool get executed => status == 'executed';

  factory FoodieAction.fromJson(Map<String, dynamic> json) => FoodieAction(
        tool: json['tool'] as String? ?? 'unknown',
        status: json['status'] as String? ?? 'failed',
        summary: json['summary'] as String? ?? '',
      );
}

class FoodieReply {
  const FoodieReply({
    required this.conversationId,
    required this.text,
    required this.actions,
  });

  final String conversationId;
  final String text;
  final List<FoodieAction> actions;

  factory FoodieReply.fromJson(Map<String, dynamic> json) => FoodieReply(
        conversationId: json['conversationId'] as String,
        text: json['text'] as String? ?? '',
        actions: (json['actions'] as List<dynamic>? ?? const [])
            .map((a) => FoodieAction.fromJson(a as Map<String, dynamic>))
            .toList(),
      );
}

/// Thrown for structured server errors (never raw transport details).
class FoodieRequestException implements Exception {
  const FoodieRequestException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

abstract interface class FoodieGateway {
  Future<FoodieReply> sendMessage({
    required String message,
    String? conversationId,
  });
}
