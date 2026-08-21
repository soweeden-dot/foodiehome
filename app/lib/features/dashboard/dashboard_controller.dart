import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/dashboard.dart';
import '../auth/session.dart';
import '../fermentation/fermentation_controller.dart';
import '../grocery/grocery_controller.dart';
import '../home_care/home_care_controller.dart';
import '../inventory/inventory_controller.dart';

/// Composes the already-fetched domain controllers into one
/// [DashboardSnapshot] via the pure [aggregateDashboard] function — no
/// network or model calls happen here beyond the same reads each domain
/// screen already performs. Reactive by construction: whenever a domain
/// controller refreshes after its own mutation (e.g. completing a cleaning
/// task), this rebuilds automatically because `ref.watch(...future)`
/// creates a live dependency — no manual invalidation needed here.
class DashboardController extends AsyncNotifier<DashboardSnapshot> {
  @override
  Future<DashboardSnapshot> build() async {
    final session = await ref.watch(sessionProvider.future);
    if (session is! Ready) return DashboardSnapshot.empty;
    final householdId = session.household.id;

    final grocery = await ref.watch(groceryControllerProvider.future);
    final inventory = await ref.watch(inventoryControllerProvider.future);
    final cleaningTasks = await ref.watch(cleaningControllerProvider.future);
    final trackedComponents = await ref.watch(trackedComponentsControllerProvider.future);
    final maintenanceIssues = await ref.watch(maintenanceIssuesControllerProvider.future);
    final fermentationProjects = await ref.watch(fermentationControllerProvider.future);

    // Sourdough next-feed-due needs each starter's last feeding, which
    // lives in its log history — not on the lightweight project list.
    // Households normally track very few starters, so fetching detail per
    // sourdough project here (rather than adding a new gateway method) is
    // the right-sized answer for this phase.
    final fermentationGateway = ref.watch(fermentationGatewayProvider);
    final sourdoughProjects = fermentationProjects.where((p) => p.isSourdough).toList();
    final sourdoughDetails = await Future.wait(
      sourdoughProjects.map((p) => fermentationGateway.fetchProject(householdId, p.id)),
    );
    final lastFeedingByProjectId = {
      for (final detail in sourdoughDetails) detail.project.id: detail.lastFeeding?.loggedAt,
    };

    return aggregateDashboard(
      grocery: grocery,
      inventory: inventory,
      cleaningTasks: cleaningTasks,
      trackedComponents: trackedComponents,
      maintenanceIssues: maintenanceIssues,
      fermentationProjects: fermentationProjects,
      lastFeedingByProjectId: lastFeedingByProjectId,
    );
  }
}

final dashboardControllerProvider =
    AsyncNotifierProvider<DashboardController, DashboardSnapshot>(DashboardController.new);
