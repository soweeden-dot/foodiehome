import '../domain/fermentation.dart';

/// Data access for Fermentation Tracking. Backed by Supabase (RLS scopes
/// every query to the caller's household; mutations go through the
/// foodie_* SQL functions from migration 16 — same trust model as
/// HomeCareGateway). Sourdough and cacao share this one interface —
/// specialization lives in domain/fermentation.dart's convenience getters
/// and domain/sourdough.dart's pure computations, not separate gateways.
abstract interface class FermentationGateway {
  /// Defaults to active projects only when [status] is omitted.
  Future<List<FermentationProject>> fetchProjects(String householdId, {FermentationStatus? status});

  /// Full detail including complete log history, newest first.
  Future<FermentationProjectDetail> fetchProject(String householdId, String projectId);

  Future<FermentationProject> createProject(
    String householdId, {
    required String projectType,
    required String name,
    Map<String, dynamic>? targetParams,
    DateTime? nextCheckAt,
    String? notes,
  });

  Future<FermentationLog> logEvent(
    String householdId,
    String projectId, {
    required FermentationLogType logType,
    Map<String, dynamic>? payload,
    String? notes,
  });

  Future<FermentationLog> logSourdoughFeeding(
    String householdId,
    String projectId, {
    required double starterG,
    required double flourG,
    required double waterG,
    String? flourType,
    double? discardG,
    String? notes,
  });

  Future<FermentationProject> updateStage(
    String householdId,
    String projectId, {
    String? currentStage,
    FermentationStatus? status,
    DateTime? nextCheckAt,
    String? notes,
  });
}
