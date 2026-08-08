// Settings — account/device surface. Deliberately excluded from Kitchen Mode
// navigation (reachable there only via the small gear affordance, so the mode
// can be turned off on the device itself).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kitchen_mode.dart';
import '../auth/session.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    final kitchenMode = ref.watch(kitchenModeProvider).value ?? false;
    final household = session is Ready ? session.household : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Device', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          title: const Text('Kitchen Device Mode'),
          subtitle: const Text(
              'Large-format household display for this device only. '
              'Other devices are unaffected.'),
          value: kitchenMode,
          onChanged: (value) =>
              ref.read(kitchenModeProvider.notifier).setEnabled(value),
        ),
        const Divider(height: 32),
        Text('Household', style: Theme.of(context).textTheme.titleMedium),
        if (household != null) ...[
          ListTile(
            title: const Text('Name'),
            subtitle: Text(household.name),
          ),
          if (household.inviteCode != null)
            ListTile(
              title: const Text('Invite code'),
              subtitle: SelectableText(household.inviteCode!),
            ),
        ],
        const Divider(height: 32),
        Text('Account', style: Theme.of(context).textTheme.titleMedium),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => ref.read(sessionActionsProvider).signOut(),
        ),
      ],
    );
  }
}
