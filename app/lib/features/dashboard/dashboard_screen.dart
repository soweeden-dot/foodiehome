// Home dashboard BOUNDARY — the future Apolosign-style glanceable dashboard
// (Stream 5) mounts here. This placeholder proves the route/layout seam and
// keeps an always-visible Ask Foodie entry point, nothing more.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/session.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final householdName =
        session is Ready ? session.household.name : 'Household';
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(householdName, style: theme.textTheme.displaySmall),
          const SizedBox(height: 8),
          Text(
            'Dashboard cards arrive in Stream 5.',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Ask Foodie', style: TextStyle(fontSize: 18)),
            ),
            onPressed: () => context.go('/foodie'),
          ),
        ],
      ),
    );
  }
}
