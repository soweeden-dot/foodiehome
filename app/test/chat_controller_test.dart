import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiehome/data/foodie_gateway.dart';
import 'package:foodiehome/features/foodie/chat_controller.dart';

class FakeFoodieGateway implements FoodieGateway {
  FakeFoodieGateway(this._replies);

  final List<FoodieReply> _replies;
  final List<({String message, String? conversationId})> calls = [];
  FoodieRequestException? failWith;

  @override
  Future<FoodieReply> sendMessage({
    required String message,
    String? conversationId,
  }) async {
    calls.add((message: message, conversationId: conversationId));
    if (failWith != null) throw failWith!;
    return _replies.removeAt(0);
  }
}

void main() {
  ProviderContainer makeContainer(FakeFoodieGateway gateway) {
    final container = ProviderContainer(
      overrides: [foodieGatewayProvider.overrideWithValue(gateway)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('send appends user entry and Foodie reply with confirmed actions',
      () async {
    final gateway = FakeFoodieGateway([
      const FoodieReply(
        conversationId: 'conv-1',
        text: 'Done — milk is on the list.',
        actions: [
          FoodieAction(
              tool: 'add_grocery_item',
              status: 'executed',
              summary: 'Added "Milk" to the grocery list'),
        ],
      ),
    ]);
    final container = makeContainer(gateway);

    await container.read(chatControllerProvider.notifier).send('add milk');

    final state = container.read(chatControllerProvider);
    expect(state.entries.length, 2);
    expect(state.entries[0].role, 'user');
    expect(state.entries[1].role, 'foodie');
    // Actions come from the server's audit results, not from prose parsing.
    expect(state.entries[1].actions.single.executed, isTrue);
    expect(state.conversationId, 'conv-1');
    expect(state.sending, isFalse);
  });

  test('conversation id is carried into subsequent sends', () async {
    final gateway = FakeFoodieGateway([
      const FoodieReply(conversationId: 'conv-1', text: 'Hi!', actions: []),
      const FoodieReply(conversationId: 'conv-1', text: 'Again!', actions: []),
    ]);
    final container = makeContainer(gateway);
    final controller = container.read(chatControllerProvider.notifier);

    await controller.send('hello');
    await controller.send('hello again');

    expect(gateway.calls[0].conversationId, isNull);
    expect(gateway.calls[1].conversationId, 'conv-1');
  });

  test('failed action in reply is surfaced as not executed', () async {
    final gateway = FakeFoodieGateway([
      const FoodieReply(
        conversationId: 'conv-1',
        text: 'Done! Milk is on the list.', // prose claims success…
        actions: [
          FoodieAction(
              tool: 'add_grocery_item',
              status: 'failed',
              summary: 'Failed: the tool failed unexpectedly'),
        ],
      ),
    ]);
    final container = makeContainer(gateway);

    await container.read(chatControllerProvider.notifier).send('add milk');

    // …but the UI's record of truth marks it failed.
    final entry = container.read(chatControllerProvider).entries[1];
    expect(entry.actions.single.executed, isFalse);
  });

  test('structured server errors become error entries, chat stays usable',
      () async {
    final gateway = FakeFoodieGateway([])
      ..failWith = const FoodieRequestException(
          'no_household', 'join a household before using Foodie');
    final container = makeContainer(gateway);

    await container.read(chatControllerProvider.notifier).send('hi');

    final state = container.read(chatControllerProvider);
    expect(state.entries.length, 2);
    expect(state.entries[1].isError, isTrue);
    expect(state.entries[1].text, contains('join a household'));
    expect(state.sending, isFalse);
  });

  test('blank input is ignored', () async {
    final gateway = FakeFoodieGateway([]);
    final container = makeContainer(gateway);

    await container.read(chatControllerProvider.notifier).send('   ');

    expect(container.read(chatControllerProvider).entries, isEmpty);
    expect(gateway.calls, isEmpty);
  });
}
