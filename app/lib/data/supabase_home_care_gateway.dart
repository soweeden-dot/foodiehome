import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/home_care.dart';
import '../domain/recurrence.dart';
import 'home_care_gateway.dart';

class SupabaseHomeCareGateway implements HomeCareGateway {
  SupabaseHomeCareGateway(this._client);

  final SupabaseClient _client;

  static DateTime? _parseDate(dynamic value) =>
      value == null ? null : DateTime.parse(value as String);

  static RecurrenceIntervalUnit _parseIntervalUnit(String value) => switch (value) {
        'day' => RecurrenceIntervalUnit.day,
        'week' => RecurrenceIntervalUnit.week,
        'month' => RecurrenceIntervalUnit.month,
        'year' => RecurrenceIntervalUnit.year,
        _ => throw ArgumentError('unknown interval_unit: $value'),
      };

  @override
  Future<List<CleaningTask>> fetchCleaningTasks(String householdId) async {
    final tasksFuture = _client
        .from('cleaning_tasks')
        .select(
          'id, name, area, supplies_needed, recurrence_rules(interval_unit, interval_count, weekday), profiles(display_name)',
        )
        .eq('household_id', householdId)
        .eq('is_active', true)
        .isFilter('deleted_at', null)
        .order('created_at');
    final completionsFuture = _client
        .from('cleaning_completions')
        .select('task_id, completed_at')
        .eq('household_id', householdId)
        .eq('outcome', 'completed')
        .order('completed_at', ascending: false);

    final results = await Future.wait([tasksFuture, completionsFuture]);
    final taskRows = results[0];
    final completionRows = results[1];

    final lastCompletedByTask = <String, DateTime>{};
    for (final row in completionRows) {
      final taskId = row['task_id'] as String;
      lastCompletedByTask.putIfAbsent(taskId, () => _parseDate(row['completed_at'])!);
    }

    return taskRows.map((row) {
      final rule = row['recurrence_rules'] as Map<String, dynamic>?;
      final profile = row['profiles'] as Map<String, dynamic>?;
      return CleaningTask(
        id: row['id'] as String,
        name: row['name'] as String,
        area: row['area'] as String?,
        recurrence: rule == null
            ? null
            : RecurrenceSummary(
                intervalUnit: _parseIntervalUnit(rule['interval_unit'] as String),
                intervalCount: rule['interval_count'] as int,
                weekday: rule['weekday'] as int?,
              ),
        assignedUserName: profile?['display_name'] as String?,
        suppliesNeeded: ((row['supplies_needed'] as List?) ?? const [])
            .map((e) => e as String)
            .toList(),
        lastCompletedOn: lastCompletedByTask[row['id']],
      );
    }).toList();
  }

  @override
  Future<void> completeCleaningTask(String householdId, String taskId, {String? notes}) async {
    await _client.rpc<dynamic>(
      'foodie_complete_cleaning_task',
      params: {'p_household': householdId, 'p_task_id': taskId, 'p_notes': notes},
    );
  }

  @override
  Future<void> skipCleaningTask(String householdId, String taskId, {String? reason}) async {
    await _client.rpc<dynamic>(
      'foodie_skip_cleaning_task',
      params: {'p_household': householdId, 'p_task_id': taskId, 'p_reason': reason},
    );
  }

  @override
  Future<List<TrackedComponent>> fetchTrackedComponents(String householdId) async {
    final componentsFuture = _client
        .from('tracked_components')
        .select('id, system_name, component_name, kind, installed_on, replace_interval_days, spares_count')
        .eq('household_id', householdId)
        .isFilter('deleted_at', null)
        .order('system_name');
    final replacementsFuture = _client
        .from('component_replacements')
        .select('component_id, replaced_on')
        .eq('household_id', householdId)
        .order('replaced_on', ascending: false);

    final results = await Future.wait([componentsFuture, replacementsFuture]);
    final componentRows = results[0];
    final replacementRows = results[1];

    final lastReplacedByComponent = <String, DateTime>{};
    for (final row in replacementRows) {
      final componentId = row['component_id'] as String;
      lastReplacedByComponent.putIfAbsent(componentId, () => _parseDate(row['replaced_on'])!);
    }

    return componentRows
        .map((row) => TrackedComponent(
              id: row['id'] as String,
              systemName: row['system_name'] as String,
              componentName: row['component_name'] as String,
              kind: row['kind'] as String,
              installedOn: _parseDate(row['installed_on']),
              replaceIntervalDays: row['replace_interval_days'] as int?,
              sparesCount: row['spares_count'] as int,
              lastReplacedOn: lastReplacedByComponent[row['id']],
            ))
        .toList();
  }

  @override
  Future<void> logFilterReplacement(String householdId, String componentId, {String? notes}) async {
    await _client.rpc<dynamic>(
      'foodie_log_filter_replacement',
      params: {'p_household': householdId, 'p_component_id': componentId, 'p_notes': notes},
    );
  }

  static MaintenanceIssue _issueFromRow(Map<String, dynamic> row) => MaintenanceIssue(
        id: row['id'] as String,
        title: row['title'] as String,
        area: row['area'] as String?,
        description: row['description'] as String?,
        status: MaintenanceIssueStatusWire.fromWire(row['status'] as String),
        reportedAt: _parseDate(row['reported_at'])!,
        resolvedAt: _parseDate(row['resolved_at']),
        notes: row['notes'] as String?,
      );

  @override
  Future<List<MaintenanceIssue>> fetchMaintenanceIssues(
    String householdId, {
    MaintenanceIssueStatus? status,
  }) async {
    var query = _client
        .from('maintenance_issues')
        .select('id, title, area, description, status, reported_at, resolved_at, notes')
        .eq('household_id', householdId)
        .isFilter('deleted_at', null);
    if (status != null) query = query.eq('status', status.toWire());
    final rows = await query.order('reported_at', ascending: false);
    return rows.map(_issueFromRow).toList();
  }

  @override
  Future<MaintenanceIssue> reportMaintenanceIssue(
    String householdId, {
    required String title,
    String? area,
    String? description,
  }) async {
    final result = await _client.rpc<dynamic>(
      'foodie_report_maintenance_issue',
      params: {
        'p_household': householdId,
        'p_title': title.trim(),
        'p_area': area,
        'p_description': description,
      },
    );
    return _issueFromRow(result as Map<String, dynamic>);
  }

  @override
  Future<void> resolveMaintenanceIssue(String householdId, String issueId, {String? notes}) async {
    await _client.rpc<dynamic>(
      'foodie_resolve_maintenance_issue',
      params: {'p_household': householdId, 'p_issue_id': issueId, 'p_notes': notes},
    );
  }
}
