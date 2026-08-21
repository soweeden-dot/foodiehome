// PROVISIONAL UI — functional project detail: log history, sourdough
// feeding, generic events, stage/status updates. Visual polish is not the
// goal of this phase.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/fermentation.dart';
import '../../domain/sourdough.dart' as sourdough;
import 'fermentation_controller.dart';

String _formatDateTime(DateTime d) {
  final local = d.toLocal();
  final date =
      '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}

class FermentationProjectScreen extends ConsumerWidget {
  const FermentationProjectScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(fermentationProjectControllerProvider(projectId));

    return Scaffold(
      appBar: AppBar(
        title: Text(detail.value?.project.name ?? 'Fermentation project'),
      ),
      body: switch (detail) {
        AsyncData(value: final d) => _ProjectBody(
          projectId: projectId,
          detail: d,
        ),
        AsyncError(error: final error) => Center(
          child: Text('Could not load project: $error'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _ProjectBody extends ConsumerWidget {
  const _ProjectBody({required this.projectId, required this.detail});

  final String projectId;
  final FermentationProjectDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = detail.project;
    final lastFeeding = detail.lastFeeding;
    final nextFeedDue = project.isSourdough
        ? sourdough.computeNextFeedDue(
            lastFedAt: lastFeeding?.loggedAt,
            feedIntervalHours: project.feedIntervalHours,
          )
        : null;
    final feedOverdue = sourdough.isFeedOverdue(nextFeedDue, DateTime.now());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text(project.projectType)),
            Chip(label: Text(project.status.label)),
            if (project.currentStage != null)
              Chip(label: Text(project.currentStage!)),
          ],
        ),
        const SizedBox(height: 12),
        Text('Started ${_formatDateTime(project.startedAt)}'),
        if (project.nextCheckAt != null)
          Text('Next check-in: ${_formatDateTime(project.nextCheckAt!)}'),
        if (project.notes != null) ...[
          const SizedBox(height: 8),
          Text(project.notes!, style: Theme.of(context).textTheme.bodyMedium),
        ],
        if (project.isSourdough) ...[
          const Divider(height: 32),
          Text('Sourdough', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (lastFeeding != null) ...[
            Text(
              'Last fed ${_formatDateTime(lastFeeding.loggedAt)}: '
              '${lastFeeding.starterG?.toStringAsFixed(0)}g starter, '
              '${lastFeeding.flourG?.toStringAsFixed(0)}g flour, '
              '${lastFeeding.waterG?.toStringAsFixed(0)}g water',
            ),
            Text(
              'Hydration ${sourdough.computeHydrationPercent(sourdough.FeedingMeasurements(starterG: lastFeeding.starterG!, flourG: lastFeeding.flourG!, waterG: lastFeeding.waterG!)).toStringAsFixed(1)}% · Ratio ${sourdough.computeFeedRatio(sourdough.FeedingMeasurements(starterG: lastFeeding.starterG!, flourG: lastFeeding.flourG!, waterG: lastFeeding.waterG!))}',
            ),
          ] else
            const Text('No feedings logged yet.'),
          if (nextFeedDue != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                feedOverdue
                    ? 'Feeding overdue — was due ${_formatDateTime(nextFeedDue)}'
                    : 'Next feed due ${_formatDateTime(nextFeedDue)}',
                style: TextStyle(
                  color: feedOverdue
                      ? Theme.of(context).colorScheme.error
                      : null,
                  fontWeight: feedOverdue ? FontWeight.bold : null,
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.restaurant_outlined),
            label: const Text('Log feeding'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _LogFeedingDialog(projectId: projectId),
            ),
          ),
        ],
        const Divider(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text('Log event'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _LogEventDialog(projectId: projectId),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.timeline_outlined),
                label: const Text('Update stage'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _UpdateStageDialog(
                    projectId: projectId,
                    project: project,
                  ),
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 32),
        Text('History', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (detail.logs.isEmpty)
          const Text('No events logged yet.')
        else
          ...detail.logs.map((log) => _LogTile(log: log)),
      ],
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});

  final FermentationLog log;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (log.logType == FermentationLogType.feeding) {
      parts.add(
        '${log.starterG?.toStringAsFixed(0)}g / ${log.flourG?.toStringAsFixed(0)}g / '
        '${log.waterG?.toStringAsFixed(0)}g',
      );
      if (log.flourType != null) parts.add(log.flourType!);
    } else if (log.payload.isNotEmpty) {
      parts.add(
        log.payload.entries.map((e) => '${e.key}: ${e.value}').join(', '),
      );
    }
    if (log.notes != null) parts.add(log.notes!);

    return ListTile(
      dense: true,
      leading: const Icon(Icons.circle, size: 10),
      title: Text(log.logType.label),
      subtitle: Text(
        [
          _formatDateTime(log.loggedAt),
          if (parts.isNotEmpty) parts.join(' · '),
        ].join('\n'),
      ),
      isThreeLine: parts.isNotEmpty,
    );
  }
}

class _LogFeedingDialog extends ConsumerStatefulWidget {
  const _LogFeedingDialog({required this.projectId});

  final String projectId;

  @override
  ConsumerState<_LogFeedingDialog> createState() => _LogFeedingDialogState();
}

class _LogFeedingDialogState extends ConsumerState<_LogFeedingDialog> {
  final _starter = TextEditingController();
  final _flour = TextEditingController();
  final _water = TextEditingController();
  final _flourType = TextEditingController();
  final _discard = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _starter.dispose();
    _flour.dispose();
    _water.dispose();
    _flourType.dispose();
    _discard.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final starterG = double.tryParse(_starter.text.trim());
    final flourG = double.tryParse(_flour.text.trim());
    final waterG = double.tryParse(_water.text.trim());
    if (starterG == null || starterG <= 0) {
      setState(() => _error = 'Starter amount must be a positive number.');
      return;
    }
    if (flourG == null || flourG <= 0) {
      setState(() => _error = 'Flour amount must be a positive number.');
      return;
    }
    if (waterG == null || waterG <= 0) {
      setState(() => _error = 'Water amount must be a positive number.');
      return;
    }
    final discardG = _discard.text.trim().isEmpty
        ? null
        : double.tryParse(_discard.text.trim());

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(
            fermentationProjectControllerProvider(widget.projectId).notifier,
          )
          .logSourdoughFeeding(
            starterG: starterG,
            flourG: flourG,
            waterG: waterG,
            flourType: _flourType.text.trim().isEmpty
                ? null
                : _flourType.text.trim(),
            discardG: discardG,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
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
      title: const Text('Log a feeding'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _starter,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Starter (g)'),
                    autofocus: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _flour,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Flour (g)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _water,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Water (g)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _flourType,
              decoration: const InputDecoration(
                labelText: 'Flour type (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _discard,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Discard (g, optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Notes (e.g. rise/peak observations)',
              ),
              maxLines: 2,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Log feeding'),
        ),
      ],
    );
  }
}

const _genericLogTypes = {
  FermentationLogType.observation: 'Observation',
  FermentationLogType.turning: 'Turn/stir',
  FermentationLogType.temperature: 'Temperature',
};

class _LogEventDialog extends ConsumerStatefulWidget {
  const _LogEventDialog({required this.projectId});

  final String projectId;

  @override
  ConsumerState<_LogEventDialog> createState() => _LogEventDialogState();
}

class _LogEventDialogState extends ConsumerState<_LogEventDialog> {
  FermentationLogType _logType = FermentationLogType.observation;
  final _tempC = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _tempC.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    Map<String, dynamic>? payload;
    if (_logType == FermentationLogType.temperature) {
      final tempC = double.tryParse(_tempC.text.trim());
      if (tempC == null) {
        setState(() => _error = 'Temperature must be a number.');
        return;
      }
      payload = {'temp_c': tempC};
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(
            fermentationProjectControllerProvider(widget.projectId).notifier,
          )
          .logEvent(
            logType: _logType,
            payload: payload,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
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
      title: const Text('Log an event'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<FermentationLogType>(
            isExpanded: true,
            initialValue: _logType,
            decoration: const InputDecoration(labelText: 'Type'),
            items: _genericLogTypes.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (value) => setState(() => _logType = value ?? _logType),
          ),
          if (_logType == FermentationLogType.temperature) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _tempC,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Temperature (°C)'),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(
              labelText: 'Notes',
              helperText:
                  'Smell, appearance, liquid/drainage, anything worth recording',
            ),
            maxLines: 3,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
          child: const Text('Log event'),
        ),
      ],
    );
  }
}

class _UpdateStageDialog extends ConsumerStatefulWidget {
  const _UpdateStageDialog({required this.projectId, required this.project});

  final String projectId;
  final FermentationProject project;

  @override
  ConsumerState<_UpdateStageDialog> createState() => _UpdateStageDialogState();
}

class _UpdateStageDialogState extends ConsumerState<_UpdateStageDialog> {
  late final _stage = TextEditingController(
    text: widget.project.currentStage ?? '',
  );
  final _notes = TextEditingController();
  late FermentationStatus? _status = widget.project.status;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _stage.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final newStage = _stage.text.trim();
      await ref
          .read(
            fermentationProjectControllerProvider(widget.projectId).notifier,
          )
          .updateStage(
            currentStage:
                newStage.isEmpty || newStage == widget.project.currentStage
                ? null
                : newStage,
            status: _status == widget.project.status ? null : _status,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
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
      title: const Text('Update stage / status'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _stage,
            decoration: const InputDecoration(
              labelText: 'Current stage',
              hintText: "e.g. 'drying', 'day 3'",
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<FermentationStatus>(
            isExpanded: true,
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: FermentationStatus.values
                .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                .toList(),
            onChanged: (value) => setState(() => _status = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 2,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
          child: const Text('Save'),
        ),
      ],
    );
  }
}
