// The production navigation shell. One StatefulShellRoute body, three
// explicit chromes selected by resolveShellLayout:
//   phone   → bottom NavigationBar (primary destinations + "More" sheet)
//   tablet  → NavigationRail with every destination
//   kitchen → simplified large-format column (big targets, reduced surfaces)
//
// The chrome only ever changes HOW destinations are presented. Routing, auth
// redirects, and data access are identical in all three — Kitchen Mode is
// presentation, not privilege.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/kitchen_mode.dart';
import '../../core/shell_layout.dart';
import 'destinations.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kitchenMode = ref.watch(kitchenModeProvider).value ?? false;
    final width = MediaQuery.sizeOf(context).width;
    final layout = resolveShellLayout(width: width, kitchenMode: kitchenMode);

    return switch (layout) {
      ShellLayout.phone => _PhoneShell(shell: navigationShell),
      ShellLayout.tablet => _TabletShell(shell: navigationShell),
      ShellLayout.kitchen => _KitchenShell(shell: navigationShell),
    };
  }
}

void _goToBranch(StatefulNavigationShell shell, AppDestination destination) {
  final index = appDestinations.indexOf(destination);
  shell.goBranch(index, initialLocation: index == shell.currentIndex);
}

// ---------------------------------------------------------------------------
// Phone: bottom bar with the primary destinations + a More sheet.
// ---------------------------------------------------------------------------
class _PhoneShell extends StatelessWidget {
  const _PhoneShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final primary = phonePrimaryDestinations();
    final overflow = phoneOverflowDestinations();
    final currentRoute = appDestinations[shell.currentIndex].route;
    final primaryIndex =
        primary.indexWhere((d) => d.route == currentRoute);

    return Scaffold(
      key: const Key('phoneShell'),
      body: SafeArea(child: shell),
      bottomNavigationBar: NavigationBar(
        // When a "More" destination is active, highlight the More item.
        selectedIndex: primaryIndex >= 0 ? primaryIndex : primary.length,
        destinations: [
          for (final destination in primary)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label,
            ),
          const NavigationDestination(
            icon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
        onDestinationSelected: (index) {
          if (index < primary.length) {
            _goToBranch(shell, primary[index]);
          } else {
            showModalBottomSheet<void>(
              context: context,
              builder: (sheetContext) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final destination in overflow)
                      ListTile(
                        leading: Icon(destination.icon),
                        title: Text(destination.label),
                        selected: destination.route == currentRoute,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _goToBranch(shell, destination);
                        },
                      ),
                  ],
                ),
              ),
            );
          }
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tablet: navigation rail with all destinations (planning posture).
// ---------------------------------------------------------------------------
class _TabletShell extends StatelessWidget {
  const _TabletShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('tabletShell'),
      body: SafeArea(
        child: Row(
          children: [
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      selectedIndex: shell.currentIndex,
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final destination in appDestinations)
                          NavigationRailDestination(
                            icon: Icon(destination.icon),
                            label: Text(destination.label),
                          ),
                      ],
                      onDestinationSelected: (index) =>
                          _goToBranch(shell, appDestinations[index]),
                    ),
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kitchen: simplified large-format shell. Few destinations, big targets,
// dashboard-first. Settings is reachable only through the small gear so the
// mode can be exited on-device; nothing here bypasses auth or RLS.
// ---------------------------------------------------------------------------
class _KitchenShell extends StatelessWidget {
  const _KitchenShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final destinations = kitchenDestinations();
    final theme = Theme.of(context);
    final currentRoute = appDestinations[shell.currentIndex].route;

    return Scaffold(
      key: const Key('kitchenShell'),
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 132,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  for (final destination in destinations)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: _KitchenNavButton(
                        destination: destination,
                        selected: destination.route == currentRoute,
                        onTap: () => _goToBranch(shell, destination),
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    onPressed: () => context.go('/settings'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Expanded(child: shell),
          ],
        ),
      ),
    );
  }
}

class _KitchenNavButton extends StatelessWidget {
  const _KitchenNavButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 112,
          height: 92, // large touch target for across-the-kitchen taps
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(destination.icon, size: 36),
              const SizedBox(height: 6),
              Text(destination.label,
                  style: theme.textTheme.labelLarge,
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
