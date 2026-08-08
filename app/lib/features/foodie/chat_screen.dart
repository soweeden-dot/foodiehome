// PROVISIONAL UI — a minimal authenticated chat surface to exercise the
// Stream 3 agent pipeline. The real Foodie UI is a later stream.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_controller.dart';

class FoodieChatScreen extends ConsumerStatefulWidget {
  const FoodieChatScreen({super.key});

  @override
  ConsumerState<FoodieChatScreen> createState() => _FoodieChatScreenState();
}

class _FoodieChatScreenState extends ConsumerState<FoodieChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    _input.clear();
    ref.read(chatControllerProvider.notifier).send(text);
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);

    // Keep the transcript pinned to the newest message.
    ref.listen(chatControllerProvider, (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Foodie (test chat)')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: chat.entries.length,
              itemBuilder: (context, index) =>
                  _EntryBubble(entry: chat.entries[index]),
            ),
          ),
          if (chat.sending) const LinearProgressIndicator(minHeight: 2),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !chat.sending,
                      decoration:
                          const InputDecoration(hintText: 'Ask Foodie…'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: chat.sending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryBubble extends StatelessWidget {
  const _EntryBubble({required this.entry});

  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = entry.role == 'user';
    final color = entry.isError
        ? theme.colorScheme.errorContainer
        : isUser
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.text),
            // Confirmed actions — rendered from the server's audit results,
            // never inferred from the reply text.
            for (final action in entry.actions)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      action.executed ? Icons.check_circle : Icons.error,
                      size: 16,
                      color: action.executed
                          ? Colors.green.shade700
                          : theme.colorScheme.error,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(action.summary,
                          style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
