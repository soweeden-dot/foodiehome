// PROVISIONAL UI — functional fermentation project list + create flow;
// visual polish is not the goal of this phase (see the Inventory phase's
// screens for the same caveat).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/fermentation.dart';
import 'fermentation_controller.dart';
import 'fermentation_project_screen.dart';

class FermentationScreen extends ConsumerWidget {
  const FermentationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(fermentationControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Fermentation')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Start a new project',
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const _NewProjectDialog(),
        ),
        child: const Icon(Icons.add),
      ),
      body: switch (projects) {
        AsyncData(value: final list) => list.isEmpty
            ? const _EmptyState(
                icon: Icons.science_outlined,
                title: 'No active fermentation projects',
                message: 'Tap + to start tracking a sourdough starter, a cacao batch, or anything else fermenting.',
              )
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, index) => _ProjectTile(project: list[index]),
              ),
        AsyncError(error: final error) => Center(child: Text('Could not load fermentation projects: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project});

  final FermentationProject project;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      project.projectType,
      if (project.currentStage != null) project.currentStage!,
      project.status.label,
    ];

    return ListTile(
      leading: Icon(project.isSourdough ? Icons.bakery_dining_outlined : Icons.science_outlined),
      title: Text(project.name),
      subtitle: Text(subtitleParts.join(' · ')),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FermentationProjectScreen(projectId: project.id),
      )),
    );
  }
}

class _NewProjectDialog extends ConsumerStatefulWidget {
  const _NewProjectDialog();

  @override
  ConsumerState<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends ConsumerState<_NewProjectDialog> {
  final _name = TextEditingController();
  final _customType = TextEditingController();
  String _projectType = 'sourdough_starter';
  bool _busy = false;
  String? _error;

  static const _knownTypes = {
    'sourdough_starter': 'Sourdough starter',
    'cacao': 'Cacao',
    'other': 'Other',
  };

  @override
  void dispose() {
    _name.dispose();
    _customType.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    final projectType = _projectType == 'other' ? _customType.text.trim() : _projectType;
    if (projectType.isEmpty) {
      setState(() => _error = 'Fermentation type is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final targetParams = _projectType == 'sourdough_starter'
          ? {'state': 'active', 'feed_interval_hours': 24}
          : null;
      await ref.read(fermentationControllerProvider.notifier).createProject(
            projectType: projectType,
            name: _name.text.trim(),
            targetParams: targetParams,
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
      title: const Text('Start a fermentation project'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _projectType,
            decoration: const InputDecoration(labelText: 'Type'),
            items: _knownTypes.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (value) => setState(() => _projectType = value ?? _projectType),
          ),
          if (_projectType == 'other') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customType,
              decoration: const InputDecoration(labelText: 'Fermentation type'),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            autofocus: true,
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
          child: const Text('Start'),
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
