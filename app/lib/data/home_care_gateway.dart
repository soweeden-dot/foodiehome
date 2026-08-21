import '../domain/home_care.dart';

/// Data access for Cleaning + Home Care. Backed by Supabase (RLS scopes
/// every query to the caller's household; mutations go through the
/// foodie_* SQL functions from migration 15 — same trust model as
/// InventoryGateway). Next-due dates are never fetched pre-computed — the
/// domain models compute them from recurrence.dart at read time.
abstract interface class HomeCareGateway {
  Future<List<CleaningTask>> fetchCleaningTasks(String householdId);

  Future<void> completeCleaningTask(String householdId, String taskId, {String? notes});

  Future<void> skipCleaningTask(String householdId, String taskId, {String? reason});

  Future<List<TrackedComponent>> fetchTrackedComponents(String householdId);

  Future<void> logFilterReplacement(String householdId, String componentId, {String? notes});

  Future<List<MaintenanceIssue>> fetchMaintenanceIssues(
    String householdId, {
    MaintenanceIssueStatus? status,
  });

  Future<MaintenanceIssue> reportMaintenanceIssue(
    String householdId, {
    required String title,
    String? area,
    String? description,
  });

  Future<void> resolveMaintenanceIssue(String householdId, String issueId, {String? notes});
}
