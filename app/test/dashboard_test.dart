import 'package:flutter_test/flutter_test.dart';
import 'package:foodiehome/domain/dashboard.dart';
import 'package:foodiehome/domain/fermentation.dart';
import 'package:foodiehome/domain/grocery.dart';
import 'package:foodiehome/domain/home_care.dart';
import 'package:foodiehome/domain/inventory.dart';
import 'package:foodiehome/domain/recurrence.dart';

void main() {
  final today = DateTime.utc(2026, 8, 21); // a Friday

  test('all-empty inputs produce an all-clear, zero-attention snapshot', () {
    final snapshot = aggregateDashboard(
      grocery: GroceryListSnapshot.empty,
      inventory: InventorySnapshot.empty,
      cleaningTasks: const [],
      trackedComponents: const [],
      maintenanceIssues: const [],
      fermentationProjects: const [],
      asOf: today,
    );

    expect(snapshot.isAllClear, isTrue);
    expect(snapshot.attentionCount, 0);
    expect(snapshot.groceryUncheckedCount, 0);
  });

  test('grocery unchecked count reflects only unchecked items', () {
    final snapshot = aggregateDashboard(
      grocery: const GroceryListSnapshot(
        listId: 'list-1',
        listName: 'Groceries',
        items: [
          GroceryItem(id: '1', name: 'Milk', checked: false),
          GroceryItem(id: '2', name: 'Eggs', checked: true),
        ],
      ),
      inventory: InventorySnapshot.empty,
      cleaningTasks: const [],
      trackedComponents: const [],
      maintenanceIssues: const [],
      fermentationProjects: const [],
      asOf: today,
    );

    expect(snapshot.groceryUncheckedCount, 1);
    expect(snapshot.isAllClear, isFalse);
  });

  test('expiring-soon and expired inventory items are bucketed separately', () {
    final snapshot = aggregateDashboard(
      grocery: GroceryListSnapshot.empty,
      inventory: InventorySnapshot(
        locations: const [],
        items: [
          InventoryItem(id: '1', name: 'Old milk', expiresOn: DateTime.utc(2026, 8, 20)), // expired
          InventoryItem(id: '2', name: 'Yogurt', expiresOn: DateTime.utc(2026, 8, 22)), // expiring soon
          InventoryItem(id: '3', name: 'Frozen peas', expiresOn: DateTime.utc(2027, 1, 1)), // fine
        ],
      ),
      cleaningTasks: const [],
      trackedComponents: const [],
      maintenanceIssues: const [],
      fermentationProjects: const [],
      asOf: today,
    );

    expect(snapshot.expiredItems.map((i) => i.name), ['Old milk']);
    expect(snapshot.expiringSoonItems.map((i) => i.name), ['Yogurt']);
    expect(snapshot.attentionCount, 1); // only the expired one counts
  });

  test('cleaning task due today (or rolled-forward-to-today) is bucketed; a future one is not', () {
    final dueToday = CleaningTask(
      id: 'task-1',
      name: 'Vacuum',
      recurrence: const RecurrenceSummary(
        intervalUnit: RecurrenceIntervalUnit.week,
        intervalCount: 1,
        weekday: 5, // Friday — today
      ),
      lastCompletedOn: DateTime.utc(2026, 8, 14), // last Friday
    );
    final dueNextWeek = CleaningTask(
      id: 'task-2',
      name: 'Mop',
      recurrence: const RecurrenceSummary(
        intervalUnit: RecurrenceIntervalUnit.week,
        intervalCount: 1,
        weekday: 5,
      ),
      lastCompletedOn: DateTime.utc(2026, 8, 21), // fed today, next due in a week
    );

    final snapshot = aggregateDashboard(
      grocery: GroceryListSnapshot.empty,
      inventory: InventorySnapshot.empty,
      cleaningTasks: [dueToday, dueNextWeek],
      trackedComponents: const [],
      maintenanceIssues: const [],
      fermentationProjects: const [],
      asOf: today,
    );

    expect(snapshot.cleaningDueOrOverdue.map((t) => t.id), ['task-1']);
    expect(snapshot.attentionCount, 1);
  });

  test(
    'a long-overdue cleaning task rolls forward to the nearest cleaning day, not "today" if that day has passed',
    () {
      final longOverdue = CleaningTask(
        id: 'task-1',
        name: 'Clean bathroom',
        recurrence: const RecurrenceSummary(
          intervalUnit: RecurrenceIntervalUnit.week,
          intervalCount: 1,
          weekday: 3, // Wednesday
        ),
        lastCompletedOn: DateTime.utc(2026, 7, 1), // long overdue
      );

      final snapshot = aggregateDashboard(
        grocery: GroceryListSnapshot.empty,
        inventory: InventorySnapshot.empty,
        cleaningTasks: [longOverdue],
        trackedComponents: const [],
        maintenanceIssues: const [],
        fermentationProjects: const [],
        asOf: today, // a Friday — not one of the household's cleaning days
      );

      // The rollover algorithm resolves a stale due date to the nearest
      // upcoming {Wednesday, Sunday} from today (today included); since
      // today (Friday) isn't one of those days, it lands on the coming
      // Sunday — not bucketed as "due today", which is the rollover
      // design working as intended (see recurrence.dart).
      expect(snapshot.cleaningDueOrOverdue, isEmpty);
    },
  );

  test('filter due within the horizon is bucketed; one far out is not', () {
    final dueSoon = TrackedComponent(
      id: 'comp-1',
      systemName: 'Fridge',
      componentName: 'Water filter',
      kind: 'filter',
      replaceIntervalDays: 90,
      lastReplacedOn: DateTime.utc(2026, 5, 25), // due ~Aug 23, within 14 days of Aug 21
    );
    final dueFar = TrackedComponent(
      id: 'comp-2',
      systemName: 'Bedroom',
      componentName: 'Air purifier filter',
      kind: 'filter',
      replaceIntervalDays: 180,
      lastReplacedOn: DateTime.utc(2026, 8, 1),
    );
    final overdue = TrackedComponent(
      id: 'comp-3',
      systemName: 'Vacuum',
      componentName: 'HEPA filter',
      kind: 'filter',
      replaceIntervalDays: 30,
      lastReplacedOn: DateTime.utc(2026, 6, 1), // long overdue, no rollover for filters
    );

    final snapshot = aggregateDashboard(
      grocery: GroceryListSnapshot.empty,
      inventory: InventorySnapshot.empty,
      cleaningTasks: const [],
      trackedComponents: [dueSoon, dueFar, overdue],
      maintenanceIssues: const [],
      fermentationProjects: const [],
      asOf: today,
    );

    expect(
      snapshot.filtersDueOrOverdue.map((c) => c.id).toSet(),
      {'comp-1', 'comp-3'},
    );
  });

  test('open maintenance issues are bucketed; resolved ones are excluded', () {
    final open = MaintenanceIssue(
      id: 'issue-1',
      title: 'Leaky faucet',
      status: MaintenanceIssueStatus.open,
      reportedAt: today,
    );
    final resolved = MaintenanceIssue(
      id: 'issue-2',
      title: 'Fixed light',
      status: MaintenanceIssueStatus.resolved,
      reportedAt: today,
    );

    final snapshot = aggregateDashboard(
      grocery: GroceryListSnapshot.empty,
      inventory: InventorySnapshot.empty,
      cleaningTasks: const [],
      trackedComponents: const [],
      maintenanceIssues: [open, resolved],
      fermentationProjects: const [],
      asOf: today,
    );

    expect(snapshot.openMaintenanceIssues.map((i) => i.id), ['issue-1']);
    expect(snapshot.attentionCount, 1);
  });

  test('sourdough feed status: overdue when past due, not computed for cacao', () {
    final starter = FermentationProject(
      id: 'proj-1',
      projectType: 'sourdough_starter',
      name: 'Rustic Rye',
      status: FermentationStatus.active,
      startedAt: today,
      targetParams: const {'state': 'active', 'feed_interval_hours': 24},
    );
    final cacao = FermentationProject(
      id: 'proj-2',
      projectType: 'cacao',
      name: 'Batch 1',
      status: FermentationStatus.active,
      startedAt: today,
    );

    final snapshot = aggregateDashboard(
      grocery: GroceryListSnapshot.empty,
      inventory: InventorySnapshot.empty,
      cleaningTasks: const [],
      trackedComponents: const [],
      maintenanceIssues: const [],
      fermentationProjects: [starter, cacao],
      lastFeedingByProjectId: {'proj-1': today.subtract(const Duration(hours: 30))},
      asOf: today,
    );

    expect(snapshot.activeFermentationProjects, [starter, cacao]);
    expect(snapshot.sourdoughFeedStatuses, hasLength(1)); // only the sourdough project
    expect(snapshot.sourdoughFeedStatuses.single.project.id, 'proj-1');
    expect(snapshot.sourdoughFeedStatuses.single.overdue, isTrue);
    expect(snapshot.attentionCount, 1);
  });

  test('sourdough with no feeding history yet has no next-feed-due and is not overdue', () {
    final starter = FermentationProject(
      id: 'proj-1',
      projectType: 'sourdough_starter',
      name: 'Rustic Rye',
      status: FermentationStatus.active,
      startedAt: today,
      targetParams: const {'state': 'active', 'feed_interval_hours': 24},
    );

    final snapshot = aggregateDashboard(
      grocery: GroceryListSnapshot.empty,
      inventory: InventorySnapshot.empty,
      cleaningTasks: const [],
      trackedComponents: const [],
      maintenanceIssues: const [],
      fermentationProjects: [starter],
      asOf: today,
    );

    expect(snapshot.sourdoughFeedStatuses.single.nextFeedDue, isNull);
    expect(snapshot.sourdoughFeedStatuses.single.overdue, isFalse);
    expect(snapshot.attentionCount, 0);
  });
}
