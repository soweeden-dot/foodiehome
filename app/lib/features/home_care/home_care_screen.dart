// PROVISIONAL UI — functional cleaning + maintenance screens; visual polish
// and Dashboard integration are later phases (see the Inventory phase's
// screens for the same caveat).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/home_care.dart';
import 'home_care_controller.dart';

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Cleaning + apartment maintenance, as two tabs of one section — matches
/// the single "/home-care" destination reserved in Stream 4.
class HomeCareScreen extends StatelessWidget {
  const HomeCareScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Home Care'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Cleaning'), Tab(text: 'Maintenance')],
          ),
        ),
        body: const TabBarView(
          children: [_CleaningTab(), _MaintenanceTab()],
        ),
      ),
    );
  }
}

class _CleaningTab extends ConsumerWidget {
  const _CleaningTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(cleaningControllerProvider);
    return switch (tasks) {
      AsyncData(value: final list) => list.isEmpty
          ? const _EmptyState(
              icon: Icons.cleaning_services_outlined,
              title: 'No cleaning tasks yet',
              message: 'Cleaning tasks set up for this household will show up here.',
            )
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, index) => _CleaningTaskTile(task: list[index]),
            ),
      AsyncError(error: final error) => Center(child: Text('Could not load cleaning tasks: $error')),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _CleaningTaskTile extends ConsumerStatefulWidget {
  const _CleaningTaskTile({required this.task});

  final CleaningTask task;

  @override
  ConsumerState<_CleaningTaskTile> createState() => _CleaningTaskTileState();
}

class _CleaningTaskTileState extends ConsumerState<_CleaningTaskTile> {
  bool _busy = false;

  Future<void> _complete() async {
    setState(() => _busy = true);
    try {
      await ref.read(cleaningControllerProvider.notifier).completeTask(widget.task.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    setState(() => _busy = true);
    try {
      await ref.read(cleaningControllerProvider.notifier).skipTask(widget.task.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;
    final due = task.nextDueOn();
    final overdue = task.isOverdue();

    final subtitleParts = <String>[
      if (task.area != null) task.area!,
      if (task.recurrence != null) task.recurrence!.label,
      if (task.assignedUserName != null) 'Assigned: ${task.assignedUserName}',
      if (due != null) (overdue ? 'Overdue — was due ${_iso(due)}' : 'Due ${_iso(due)}'),
      if (task.suppliesNeeded.isNotEmpty) 'Needs: ${task.suppliesNeeded.join(', ')}',
    ];

    return ListTile(
      leading: Icon(
        overdue ? Icons.warning_amber_outlined : Icons.check_circle_outline,
        color: overdue ? theme.colorScheme.error : theme.colorScheme.outline,
      ),
      title: Text(task.name),
      subtitle: Text(subtitleParts.join(' · ')),
      isThreeLine: subtitleParts.join(' · ').length > 40,
      trailing: _busy
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_next_outlined),
                  tooltip: 'Skip for now',
                  onPressed: _skip,
                ),
                IconButton(
                  icon: const Icon(Icons.done),
                  tooltip: 'Mark completed',
                  onPressed: _complete,
                ),
              ],
            ),
    );
  }
}

class _MaintenanceTab extends ConsumerWidget {
  const _MaintenanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = ref.watch(maintenanceIssuesControllerProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'Report an issue',
        onPressed: () => showReportMaintenanceIssueDialog(context),
        child: const Icon(Icons.add),
      ),
      body: switch (issues) {
        AsyncData(value: final list) => list.isEmpty
            ? const _EmptyState(
                icon: Icons.build_outlined,
                title: 'No maintenance issues',
                message: 'Tap + to report something that needs fixing.',
              )
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, index) => _MaintenanceIssueTile(issue: list[index]),
              ),
        AsyncError(error: final error) => Center(child: Text('Could not load maintenance issues: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _MaintenanceIssueTile extends ConsumerStatefulWidget {
  const _MaintenanceIssueTile({required this.issue});

  final MaintenanceIssue issue;

  @override
  ConsumerState<_MaintenanceIssueTile> createState() => _MaintenanceIssueTileState();
}

class _MaintenanceIssueTileState extends ConsumerState<_MaintenanceIssueTile> {
  bool _busy = false;

  Future<void> _resolve() async {
    setState(() => _busy = true);
    try {
      await ref.read(maintenanceIssuesControllerProvider.notifier).resolveIssue(widget.issue.id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final issue = widget.issue;
    final resolved = issue.status == MaintenanceIssueStatus.resolved;

    final subtitleParts = <String>[
      if (issue.area != null) issue.area!,
      issue.status.label,
      if (issue.description != null) issue.description!,
    ];

    return ListTile(
      leading: Icon(
        resolved ? Icons.check_circle_outline : Icons.error_outline,
        color: resolved ? theme.colorScheme.outline : theme.colorScheme.error,
      ),
      title: Text(issue.title),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: resolved
          ? null
          : _busy
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
                  icon: const Icon(Icons.done),
                  tooltip: 'Mark resolved',
                  onPressed: _resolve,
                ),
    );
  }
}

/// Reusable "report a maintenance issue" dialog — the Home Care screen's
/// FAB and the dashboard's "Report maintenance issue" quick action both
/// open this.
Future<void> showReportMaintenanceIssueDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _ReportIssueDialog());
}

class _ReportIssueDialog extends ConsumerStatefulWidget {
  const _ReportIssueDialog();

  @override
  ConsumerState<_ReportIssueDialog> createState() => _ReportIssueDialogState();
}

class _ReportIssueDialogState extends ConsumerState<_ReportIssueDialog> {
  final _title = TextEditingController();
  final _area = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _area.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(maintenanceIssuesControllerProvider.notifier).reportIssue(
            title: _title.text.trim(),
            area: _area.text.trim().isEmpty ? null : _area.text.trim(),
            description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report a maintenance issue'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _area,
            decoration: const InputDecoration(labelText: 'Area (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description (optional)'),
            maxLines: 2,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Report'),
        ),
      ],
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
