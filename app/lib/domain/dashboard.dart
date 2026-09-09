/// Deterministic, zero-AI dashboard aggregation.
///
/// [aggregateDashboard] is a PURE function: given already-fetched domain
/// snapshots (grocery, inventory, cleaning, tracked components, maintenance
/// issues, fermentation projects), it computes what's due/overdue/expiring
/// right now. No I/O, no model calls, no network — this is deliberate
/// architecture, not an implementation shortcut. See docs/DECISIONS.md's
/// AI/cost architecture entry: Foodie's deterministic features must never
/// require AI, and the dashboard specifically must use zero model calls.
///
/// Designed to be reusable later by Foodie's morning-brief contribution,
/// Katie's All-Agents coordinator, and a future notification worker — none
/// of that is wired up yet (per explicit scope: "do not connect those
/// systems yet"). Keeping this a pure function of typed inputs, with no
/// dependency on Riverpod, Supabase, or any UI concern, is what makes that
/// future reuse possible without a rewrite.
library;

import 'fermentation.dart';
import 'grocery.dart';
import 'home_care.dart';
import 'inventory.dart';
import 'sourdough.dart' as sourdough;

class SourdoughFeedStatus {
  const SourdoughFeedStatus({
    required this.project,
    required this.nextFeedDue,
    required this.overdue,
  });

  final FermentationProject project;
  final DateTime? nextFeedDue;
  final bool overdue;
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.groceryUncheckedCount,
    required this.expiringSoonItems,
    required this.expiredItems,
    required this.cleaningDueOrOverdue,
    required this.filtersDueOrOverdue,
    required this.openMaintenanceIssues,
    required this.activeFermentationProjects,
    required this.sourdoughFeedStatuses,
    this.itemCountByLocationKind = const {},
  });

  final int groceryUncheckedCount;
  final List<InventoryItem> expiringSoonItems;
  final List<InventoryItem> expiredItems;

  /// Stocked-item counts grouped by `InventoryLocation.kind`
  /// (pantry/fridge/freezer/other) — powers the dashboard's glanceable stat
  /// tiles without the dashboard needing to know about locations directly.
  final Map<String, int> itemCountByLocationKind;

  int get fridgeCount => itemCountByLocationKind['fridge'] ?? 0;
  int get freezerCount => itemCountByLocationKind['freezer'] ?? 0;
  int get pantryCount => itemCountByLocationKind['pantry'] ?? 0;

  /// Cleaning tasks whose computed next-due date is today or earlier. Note:
  /// the rollover algorithm (recurrence.dart) already resolves a
  /// genuinely-stale due date forward to the nearest household cleaning
  /// day, so "overdue" in practice collapses into "due today" here — that's
  /// the rollover design working as intended, not a gap in this bucket.
  final List<CleaningTask> cleaningDueOrOverdue;

  /// Tracked components (filters) due within the next two weeks or already
  /// overdue. Unlike cleaning, filters have no rollover — a missed
  /// replacement stays genuinely overdue until logged.
  final List<TrackedComponent> filtersDueOrOverdue;

  final List<MaintenanceIssue> openMaintenanceIssues;
  final List<FermentationProject> activeFermentationProjects;
  final List<SourdoughFeedStatus> sourdoughFeedStatuses;

  /// Count of things that need a household member's attention right now —
  /// the "Today" glance number.
  int get attentionCount =>
      expiredItems.length +
      cleaningDueOrOverdue.length +
      filtersDueOrOverdue.length +
      openMaintenanceIssues.length +
      sourdoughFeedStatuses.where((s) => s.overdue).length;

  bool get isAllClear => attentionCount == 0 && groceryUncheckedCount == 0;

  static const empty = DashboardSnapshot(
    groceryUncheckedCount: 0,
    expiringSoonItems: [],
    expiredItems: [],
    cleaningDueOrOverdue: [],
    filtersDueOrOverdue: [],
    openMaintenanceIssues: [],
    activeFermentationProjects: [],
    sourdoughFeedStatuses: [],
  );
}

DashboardSnapshot aggregateDashboard({
  required GroceryListSnapshot grocery,
  required InventorySnapshot inventory,
  required List<CleaningTask> cleaningTasks,
  required List<TrackedComponent> trackedComponents,
  required List<MaintenanceIssue> maintenanceIssues,
  required List<FermentationProject> fermentationProjects,
  Map<String, DateTime?> lastFeedingByProjectId = const {},
  DateTime? asOf,
  int filterDueSoonDays = 14,
}) {
  final now = asOf ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final expiringSoon = inventory.items.where((i) => i.isExpiringSoon(asOf: now)).toList();
  final expired = inventory.items.where((i) => i.isExpired(asOf: now)).toList();

  final locationKindByName = {
    for (final location in inventory.locations) location.name: location.kind,
  };
  final itemCountByLocationKind = <String, int>{};
  for (final item in inventory.items) {
    final kind = locationKindByName[item.locationName] ?? 'other';
    itemCountByLocationKind[kind] = (itemCountByLocationKind[kind] ?? 0) + 1;
  }

  final cleaningDueOrOverdue = cleaningTasks.where((task) {
    final due = task.nextDueOn(asOf: now);
    return due != null && !due.isAfter(today);
  }).toList();

  final filterHorizon = today.add(Duration(days: filterDueSoonDays));
  final filtersDueOrOverdue = trackedComponents.where((component) {
    final due = component.nextDueOn(asOf: now);
    return due != null && !due.isAfter(filterHorizon);
  }).toList();

  final openIssues = maintenanceIssues
      .where((issue) => issue.status != MaintenanceIssueStatus.resolved)
      .toList();

  final sourdoughStatuses = fermentationProjects.where((p) => p.isSourdough).map((project) {
    final lastFed = lastFeedingByProjectId[project.id];
    final nextDue = sourdough.computeNextFeedDue(
      lastFedAt: lastFed,
      feedIntervalHours: project.feedIntervalHours,
    );
    return SourdoughFeedStatus(
      project: project,
      nextFeedDue: nextDue,
      overdue: sourdough.isFeedOverdue(nextDue, now),
    );
  }).toList();

  return DashboardSnapshot(
    groceryUncheckedCount: grocery.uncheckedCount,
    expiringSoonItems: expiringSoon,
    expiredItems: expired,
    cleaningDueOrOverdue: cleaningDueOrOverdue,
    filtersDueOrOverdue: filtersDueOrOverdue,
    openMaintenanceIssues: openIssues,
    activeFermentationProjects: fermentationProjects,
    sourdoughFeedStatuses: sourdoughStatuses,
    itemCountByLocationKind: itemCountByLocationKind,
  );
}
