// PROVISIONAL UI — proves the signed-in + household state end to end.
// Replaced by the real app shell in Stream 4.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/household.dart';
import '../auth/session.dart';

class HomePlaceholderScreen extends ConsumerWidget {
  const HomePlaceholderScreen({super.key, required this.household});

  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(sessionActionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(household.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: actions.signOut,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Household ready.'),
            const SizedBox(height: 8),
            if (household.inviteCode != null)
              SelectableText('Invite code: ${household.inviteCode}'),
            const SizedBox(height: 8),
            const Text('App shell arrives in Stream 4.'),
          ],
        ),
      ),
    );
  }
}
