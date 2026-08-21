// PROVISIONAL UI — functional filter/component replacement tracking; visual
// polish is not the goal of this phase.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/home_care.dart';
import 'home_care_controller.dart';

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Tracked replaceable components (filters, batteries, cartridges, ...) —
/// mounted at the "/supplies" destination reserved in Stream 4.
class FiltersScreen extends ConsumerWidget {
  const FiltersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final components = ref.watch(trackedComponentsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Filters & Supplies')),
      body: switch (components) {
        AsyncData(value: final list) => list.isEmpty
            ? const _EmptyState(
                icon: Icons.filter_alt_outlined,
                title: 'Nothing tracked yet',
                message: 'Filters, batteries, and cartridges set up for this household will show up here.',
              )
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, index) => _ComponentTile(component: list[index]),
              ),
        AsyncError(error: final error) => Center(child: Text('Could not load components: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _ComponentTile extends ConsumerStatefulWidget {
  const _ComponentTile({required this.component});

  final TrackedComponent component;

  @override
  ConsumerState<_ComponentTile> createState() => _ComponentTileState();
}

class _ComponentTileState extends ConsumerState<_ComponentTile> {
  bool _busy = false;

  Future<void> _logReplacement() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(trackedComponentsControllerProvider.notifier)
          .logReplacement(widget.component.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final component = widget.component;
    final due = component.nextDueOn();
    final overdue = component.isOverdue();

    final subtitleParts = <String>[
      component.kind,
      'Spares on hand: ${component.sparesCount}',
      if (due != null) (overdue ? 'Overdue — was due ${_iso(due)}' : 'Due ${_iso(due)}'),
    ];

    return ListTile(
      leading: Icon(
        overdue ? Icons.warning_amber_outlined : Icons.filter_alt_outlined,
        color: overdue ? theme.colorScheme.error : theme.colorScheme.outline,
      ),
      title: Text('${component.systemName} — ${component.componentName}'),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: _busy
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : TextButton(
              onPressed: _logReplacement,
              child: const Text('Log replacement'),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
