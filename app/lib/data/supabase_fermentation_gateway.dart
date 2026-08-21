import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/fermentation.dart';
import 'fermentation_gateway.dart';

class SupabaseFermentationGateway implements FermentationGateway {
  SupabaseFermentationGateway(this._client);

  final SupabaseClient _client;

  static const _projectColumns =
      'id, project_type, name, status, started_at, ended_at, current_stage, target_params, next_check_at, notes';
  static const _logColumns = 'id, project_id, logged_at, log_type, payload, notes, author';

  static FermentationProject _projectFromRow(Map<String, dynamic> row) => FermentationProject(
        id: row['id'] as String,
        projectType: row['project_type'] as String,
        name: row['name'] as String,
        status: FermentationStatusWire.fromWire(row['status'] as String),
        startedAt: DateTime.parse(row['started_at'] as String),
        endedAt: row['ended_at'] == null ? null : DateTime.parse(row['ended_at'] as String),
        currentStage: row['current_stage'] as String?,
        targetParams: (row['target_params'] as Map<String, dynamic>?) ?? const {},
        nextCheckAt: row['next_check_at'] == null ? null : DateTime.parse(row['next_check_at'] as String),
        notes: row['notes'] as String?,
      );

  static FermentationLog _logFromRow(Map<String, dynamic> row) => FermentationLog(
        id: row['id'] as String,
        projectId: row['project_id'] as String,
        loggedAt: DateTime.parse(row['logged_at'] as String),
        logType: FermentationLogTypeWire.fromWire(row['log_type'] as String),
        payload: (row['payload'] as Map<String, dynamic>?) ?? const {},
        notes: row['notes'] as String?,
        author: row['author'] as String,
      );

  @override
  Future<List<FermentationProject>> fetchProjects(
    String householdId, {
    FermentationStatus? status,
  }) async {
    var query = _client
        .from('fermentation_projects')
        .select(_projectColumns)
        .eq('household_id', householdId)
        .isFilter('deleted_at', null);
    query = query.eq('status', (status ?? FermentationStatus.active).toWire());
    final rows = await query.order('started_at', ascending: false);
    return rows.map(_projectFromRow).toList();
  }

  @override
  Future<FermentationProjectDetail> fetchProject(String householdId, String projectId) async {
    final projectFuture = _client
        .from('fermentation_projects')
        .select(_projectColumns)
        .eq('id', projectId)
        .eq('household_id', householdId)
        .isFilter('deleted_at', null)
        .maybeSingle();
    final logsFuture = _client
        .from('fermentation_logs')
        .select(_logColumns)
        .eq('household_id', householdId)
        .eq('project_id', projectId)
        .order('logged_at', ascending: false);

    final results = await Future.wait([projectFuture, logsFuture]);
    final projectRow = results[0] as Map<String, dynamic>?;
    if (projectRow == null) {
      throw StateError('fermentation project not found');
    }
    final logRows = results[1] as List<Map<String, dynamic>>;
    return FermentationProjectDetail(
      project: _projectFromRow(projectRow),
      logs: logRows.map(_logFromRow).toList(),
    );
  }

  @override
  Future<FermentationProject> createProject(
    String householdId, {
    required String projectType,
    required String name,
    Map<String, dynamic>? targetParams,
    DateTime? nextCheckAt,
    String? notes,
  }) async {
    final result = await _client.rpc<dynamic>(
      'foodie_create_fermentation_project',
      params: {
        'p_household': householdId,
        'p_project_type': projectType.trim(),
        'p_name': name.trim(),
        'p_target_params': targetParams,
        'p_next_check_at': nextCheckAt?.toIso8601String(),
        'p_notes': notes,
      },
    );
    return _projectFromRow(result as Map<String, dynamic>);
  }

  @override
  Future<FermentationLog> logEvent(
    String householdId,
    String projectId, {
    required FermentationLogType logType,
    Map<String, dynamic>? payload,
    String? notes,
  }) async {
    final result = await _client.rpc<dynamic>(
      'foodie_log_fermentation_event',
      params: {
        'p_household': householdId,
        'p_project_id': projectId,
        'p_log_type': logType.toWire(),
        'p_payload': payload,
        'p_notes': notes,
      },
    );
    return _logFromRow(result as Map<String, dynamic>);
  }

  @override
  Future<FermentationLog> logSourdoughFeeding(
    String householdId,
    String projectId, {
    required double starterG,
    required double flourG,
    required double waterG,
    String? flourType,
    double? discardG,
    String? notes,
  }) async {
    final result = await _client.rpc<dynamic>(
      'foodie_log_sourdough_feeding',
      params: {
        'p_household': householdId,
        'p_project_id': projectId,
        'p_starter_g': starterG,
        'p_flour_g': flourG,
        'p_water_g': waterG,
        'p_flour_type': flourType,
        'p_discard_g': discardG,
        'p_notes': notes,
      },
    );
    return _logFromRow(result as Map<String, dynamic>);
  }

  @override
  Future<FermentationProject> updateStage(
    String householdId,
    String projectId, {
    String? currentStage,
    FermentationStatus? status,
    DateTime? nextCheckAt,
    String? notes,
  }) async {
    final result = await _client.rpc<dynamic>(
      'foodie_update_fermentation_stage',
      params: {
        'p_household': householdId,
        'p_project_id': projectId,
        'p_current_stage': currentStage,
        'p_status': status?.toWire(),
        'p_next_check_at': nextCheckAt?.toIso8601String(),
        'p_notes': notes,
      },
    );
    return _projectFromRow(result as Map<String, dynamic>);
  }
}
