import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../data/foodie_gateway.dart';
import '../../data/supabase_foodie_gateway.dart';

final foodieGatewayProvider = Provider<FoodieGateway>(
  (ref) => SupabaseFoodieGateway(Supabase.instance.client),
);

/// One visible entry in the chat transcript.
class ChatEntry {
  const ChatEntry.user(this.text)
      : role = 'user',
        actions = const [],
        isError = false;

  const ChatEntry.foodie(this.text, this.actions) //
      : role = 'foodie',
        isError = false;

  const ChatEntry.error(this.text)
      : role = 'error',
        actions = const [],
        isError = true;

  final String role;
  final String text;

  /// Confirmed tool executions from the server — the source of truth for
  /// "what actually happened", regardless of the reply prose.
  final List<FoodieAction> actions;
  final bool isError;
}

class ChatState {
  const ChatState({
    this.entries = const [],
    this.sending = false,
    this.conversationId,
  });

  final List<ChatEntry> entries;
  final bool sending;
  final String? conversationId;

  ChatState copyWith({
    List<ChatEntry>? entries,
    bool? sending,
    String? conversationId,
  }) =>
      ChatState(
        entries: entries ?? this.entries,
        sending: sending ?? this.sending,
        conversationId: conversationId ?? this.conversationId,
      );
}

class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState();

  Future<void> send(String text) async {
    final message = text.trim();
    if (message.isEmpty || state.sending) return;

    state = state.copyWith(
      entries: [...state.entries, ChatEntry.user(message)],
      sending: true,
    );

    try {
      final reply = await ref.read(foodieGatewayProvider).sendMessage(
            message: message,
            conversationId: state.conversationId,
          );
      state = state.copyWith(
        entries: [...state.entries, ChatEntry.foodie(reply.text, reply.actions)],
        sending: false,
        conversationId: reply.conversationId,
      );
    } on FoodieRequestException catch (e) {
      state = state.copyWith(
        entries: [...state.entries, ChatEntry.error(e.message)],
        sending: false,
      );
    } catch (_) {
      state = state.copyWith(
        entries: [
          ...state.entries,
          const ChatEntry.error('Foodie is unreachable right now.'),
        ],
        sending: false,
      );
    }
  }
}

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);
