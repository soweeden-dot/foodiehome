import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../data/home_care_gateway.dart';
import '../../data/supabase_home_care_gateway.dart';
import '../../domain/home_care.dart';
import '../auth/session.dart';

final homeCareGatewayProvider = Provider<HomeCareGateway>(
  (ref) => SupabaseHomeCareGateway(Supabase.instance.client),
);

/// Current household's cleaning tasks. Refetches whenever the session
/// changes, and after every mutation — same simple, correct pattern as
/// InventoryController.
class CleaningController extends AsyncNotifier<List<CleaningTask>> {
  @override
  Future<List<CleaningTask>> build() async {
    final session = await ref.watch(sessionProvider.future);
    if (session is! Ready) return const [];
    return ref.watch(homeCareGatewayProvider).fetchCleaningTasks(session.household.id);
  }

  Future<String> _householdId() async {
    final session = await ref.read(sessionProvider.future);
    if (session is! Ready) {
      throw StateError('cannot manage cleaning tasks without an active household');
    }
    return session.household.id;
  }

  Future<void> completeTask(String taskId, {String? notes}) async {
    final householdId = await _householdId();
    await ref.read(homeCareGatewayProvider).completeCleaningTask(householdId, taskId, notes: notes);
    ref.invalidateSelf();
    await future;
  }

  Future<void> skipTask(String taskId, {String? reason}) async {
    final householdId = await _householdId();
    await ref.read(homeCareGatewayProvider).skipCleaningTask(householdId, taskId, reason: reason);
    ref.invalidateSelf();
    await future;
  }
}

final cleaningControllerProvider =
    AsyncNotifierProvider<CleaningController, List<CleaningTask>>(CleaningController.new);

/// Current household's tracked components (filters, batteries, etc.).
class TrackedComponentsController extends AsyncNotifier<List<TrackedComponent>> {
  @override
  Future<List<TrackedComponent>> build() async {
    final session = await ref.watch(sessionProvider.future);
    if (session is! Ready) return const [];
    return ref.watch(homeCareGatewayProvider).fetchTrackedComponents(session.household.id);
  }

  Future<String> _householdId() async {
    final session = await ref.read(sessionProvider.future);
    if (session is! Ready) {
      throw StateError('cannot manage tracked components without an active household');
    }
    return session.household.id;
  }

  Future<void> logReplacement(String componentId, {String? notes}) async {
    final householdId = await _householdId();
    await ref.read(homeCareGatewayProvider).logFilterReplacement(householdId, componentId, notes: notes);
    ref.invalidateSelf();
    await future;
  }
}

final trackedComponentsControllerProvider =
    AsyncNotifierProvider<TrackedComponentsController, List<TrackedComponent>>(
        TrackedComponentsController.new);

/// Current household's maintenance issues (all statuses; the screen filters
/// client-side so switching tabs doesn't re-fetch).
class MaintenanceIssuesController extends AsyncNotifier<List<MaintenanceIssue>> {
  @override
  Future<List<MaintenanceIssue>> build() async {
    final session = await ref.watch(sessionProvider.future);
    if (session is! Ready) return const [];
    return ref.watch(homeCareGatewayProvider).fetchMaintenanceIssues(session.household.id);
  }

  Future<String> _householdId() async {
    final session = await ref.read(sessionProvider.future);
    if (session is! Ready) {
      throw StateError('cannot manage maintenance issues without an active household');
    }
    return session.household.id;
  }

  Future<void> reportIssue({required String title, String? area, String? description}) async {
    final householdId = await _householdId();
    await ref.read(homeCareGatewayProvider).reportMaintenanceIssue(
          householdId,
          title: title,
          area: area,
          description: description,
        );
    ref.invalidateSelf();
    await future;
  }

  Future<void> resolveIssue(String issueId, {String? notes}) async {
    final householdId = await _householdId();
    await ref.read(homeCareGatewayProvider).resolveMaintenanceIssue(householdId, issueId, notes: notes);
    ref.invalidateSelf();
    await future;
  }
}

final maintenanceIssuesControllerProvider =
    AsyncNotifierProvider<MaintenanceIssuesController, List<MaintenanceIssue>>(
        MaintenanceIssuesController.new);
