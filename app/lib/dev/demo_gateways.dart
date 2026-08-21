// LOCAL PREVIEW ONLY — in-memory gateway implementations used exclusively
// by lib/main_demo.dart to let the Home Dashboard be reviewed in a browser
// without a live Supabase connection (the live-infrastructure freeze is in
// force, and this sandbox cannot reach the real project anyway). None of
// this ships in the real app; production always boots through main.dart
// against the real Supabase-backed gateways. Seeded content below is
// clearly-labeled sample data for visual review, not a claim about any
// real household's state.
library;

import '../data/auth_gateway.dart';
import '../data/fermentation_gateway.dart';
import '../data/foodie_gateway.dart';
import '../data/grocery_gateway.dart';
import '../data/home_care_gateway.dart';
import '../data/household_gateway.dart';
import '../data/inventory_gateway.dart';
import '../domain/fermentation.dart';
import '../domain/grocery.dart';
import '../domain/home_care.dart';
import '../domain/household.dart';
import '../domain/inventory.dart';
import '../domain/recurrence.dart';

class DemoAuthGateway implements AuthGateway {
  String? _userId = 'demo-user';

  @override
  String? get currentUserId => _userId;

  @override
  Stream<String?> authUserIdChanges() => Stream.value(_userId);

  @override
  Future<void> signInWithPassword({required String email, required String password}) async {
    _userId = 'demo-user';
  }

  @override
  Future<void> signUp({required String email, required String password, String? displayName}) async {
    _userId = 'demo-user';
  }

  @override
  Future<void> signOut() async => _userId = null;
}

class DemoHouseholdGateway implements HouseholdGateway {
  final List<Household> _households = const [
    Household(id: 'demo-hh', name: 'Sofia & Sam', createdBy: 'demo-user', inviteCode: 'demo123'),
  ];

  @override
  Future<List<Household>> fetchMyHouseholds() async => _households;

  @override
  Future<Household> createHousehold(String name) async => _households.first;

  @override
  Future<String> redeemInvite(String code) async => _households.first.id;

  @override
  Future<void> leaveHousehold(String householdId) async {}

  @override
  Future<String> regenerateInviteCode(String householdId) async => 'demo123';

  @override
  Future<List<HouseholdMember>> fetchMembers(String householdId) async => const [
        HouseholdMember(displayName: 'Sofia', isAdmin: true),
        HouseholdMember(displayName: 'Sam', isAdmin: false),
      ];
}

/// No live foodie-agent Edge Function is deployed under the current freeze
/// (and this sandbox can't reach one anyway) — this returns a canned,
/// clearly-labeled reply so "Ask Foodie" is safe to tap in the preview
/// without implying a real AI response.
class DemoFoodieGateway implements FoodieGateway {
  @override
  Future<FoodieReply> sendMessage({required String message, String? conversationId}) async {
    return FoodieReply(
      conversationId: conversationId ?? 'demo-conversation',
      text: 'This is a local dashboard preview — Foodie chat is not connected here '
          '(live infrastructure is frozen and this preview uses in-memory sample data).',
      actions: const [],
    );
  }
}

class DemoGroceryGateway implements GroceryGateway {
  final List<GroceryItem> _items = [
    const GroceryItem(id: 'g1', name: 'Milk', quantity: 1, unit: 'l'),
    const GroceryItem(id: 'g2', name: 'Eggs', quantity: 12, unit: 'piece'),
    const GroceryItem(id: 'g3', name: 'Rye flour', checked: true),
  ];
  int _counter = 0;

  @override
  Future<GroceryListSnapshot> fetchGroceryList(String householdId) async =>
      GroceryListSnapshot(listId: 'demo-list', listName: 'Groceries', items: List.of(_items));

  @override
  Future<GroceryItem> addItem(String householdId,
      {required String name, double? quantity, String? unit, String? notes}) async {
    final item = GroceryItem(id: 'g-new-${++_counter}', name: name, quantity: quantity, unit: unit, notes: notes);
    _items.add(item);
    return item;
  }
}

class DemoInventoryGateway implements InventoryGateway {
  final List<InventoryLocation> _locations = const [
    InventoryLocation(id: 'loc-fridge', name: 'Fridge', kind: 'fridge'),
    InventoryLocation(id: 'loc-pantry', name: 'Pantry', kind: 'pantry'),
  ];
  final List<InventoryItem> _items = [
    InventoryItem(
      id: 'i1',
      name: 'Yogurt',
      locationName: 'Fridge',
      quantity: 4,
      unit: 'piece',
      expiresOn: DateTime.now().add(const Duration(days: 2)),
    ),
    InventoryItem(
      id: 'i2',
      name: 'Leftover soup',
      locationName: 'Fridge',
      expiresOn: DateTime.now().subtract(const Duration(days: 1)),
    ),
    const InventoryItem(id: 'i3', name: 'Rice', locationName: 'Pantry', quantity: 2, unit: 'kg'),
  ];
  int _counter = 0;

  @override
  Future<InventorySnapshot> fetchInventory(String householdId) async =>
      InventorySnapshot(locations: List.of(_locations), items: List.of(_items));

  @override
  Future<InventoryItem> addItem(
    String householdId, {
    required String name,
    String? locationName,
    double? quantity,
    String? unit,
    SupplyLevel? level,
    DateTime? expiresOn,
    String? notes,
  }) async {
    final item = InventoryItem(
      id: 'i-new-${++_counter}',
      name: name,
      locationName: locationName,
      quantity: quantity,
      unit: unit,
      level: level,
      expiresOn: expiresOn,
      notes: notes,
    );
    _items.add(item);
    return item;
  }

  @override
  Future<InventoryItem> updateItem(
    String householdId,
    String itemId, {
    double? quantity,
    String? unit,
    SupplyLevel? level,
    DateTime? expiresOn,
    DateTime? openedOn,
    String? notes,
  }) async {
    final index = _items.indexWhere((i) => i.id == itemId);
    final updated = _items[index].copyWith(
      quantity: quantity,
      unit: unit,
      level: level,
      expiresOn: expiresOn,
      openedOn: openedOn,
      notes: notes,
    );
    _items[index] = updated;
    return updated;
  }

  @override
  Future<void> removeItem(String householdId, String itemId) async {
    _items.removeWhere((i) => i.id == itemId);
  }
}

class DemoHomeCareGateway implements HomeCareGateway {
  final List<CleaningTask> _cleaningTasks = [
    CleaningTask(
      id: 'c1',
      name: 'Vacuum living room',
      area: 'Living room',
      recurrence: const RecurrenceSummary(intervalUnit: RecurrenceIntervalUnit.week, intervalCount: 1, weekday: 0),
      lastCompletedOn: DateTime.now().subtract(const Duration(days: 10)),
    ),
    CleaningTask(
      id: 'c2',
      name: 'Clean bathroom',
      area: 'Bathroom',
      recurrence: const RecurrenceSummary(intervalUnit: RecurrenceIntervalUnit.week, intervalCount: 1, weekday: 3),
      lastCompletedOn: DateTime.now().subtract(const Duration(days: 3)),
    ),
  ];
  final List<TrackedComponent> _trackedComponents = [
    TrackedComponent(
      id: 't1',
      systemName: 'Kitchen fridge',
      componentName: 'Water filter',
      kind: 'filter',
      installedOn: DateTime.now().subtract(const Duration(days: 100)),
      replaceIntervalDays: 90,
      sparesCount: 1,
    ),
  ];
  final List<MaintenanceIssue> _maintenanceIssues = [
    MaintenanceIssue(
      id: 'm1',
      title: 'Leaky kitchen faucet',
      area: 'Kitchen',
      status: MaintenanceIssueStatus.open,
      reportedAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
  ];

  @override
  Future<List<CleaningTask>> fetchCleaningTasks(String householdId) async => List.of(_cleaningTasks);

  @override
  Future<void> completeCleaningTask(String householdId, String taskId, {String? notes}) async {
    final index = _cleaningTasks.indexWhere((t) => t.id == taskId);
    final t = _cleaningTasks[index];
    _cleaningTasks[index] = CleaningTask(
      id: t.id,
      name: t.name,
      area: t.area,
      recurrence: t.recurrence,
      assignedUserName: t.assignedUserName,
      suppliesNeeded: t.suppliesNeeded,
      lastCompletedOn: DateTime.now(),
    );
  }

  @override
  Future<void> skipCleaningTask(String householdId, String taskId, {String? reason}) async {}

  @override
  Future<List<TrackedComponent>> fetchTrackedComponents(String householdId) async => List.of(_trackedComponents);

  @override
  Future<void> logFilterReplacement(String householdId, String componentId, {String? notes}) async {
    final index = _trackedComponents.indexWhere((c) => c.id == componentId);
    final c = _trackedComponents[index];
    _trackedComponents[index] = TrackedComponent(
      id: c.id,
      systemName: c.systemName,
      componentName: c.componentName,
      kind: c.kind,
      installedOn: c.installedOn,
      replaceIntervalDays: c.replaceIntervalDays,
      sparesCount: (c.sparesCount - 1).clamp(0, 1 << 30),
      lastReplacedOn: DateTime.now(),
    );
  }

  @override
  Future<List<MaintenanceIssue>> fetchMaintenanceIssues(String householdId, {MaintenanceIssueStatus? status}) async =>
      _maintenanceIssues.where((i) => status == null || i.status == status).toList();

  @override
  Future<MaintenanceIssue> reportMaintenanceIssue(String householdId,
      {required String title, String? area, String? description}) async {
    final issue = MaintenanceIssue(
      id: 'm-new-${_maintenanceIssues.length + 1}',
      title: title,
      area: area,
      description: description,
      status: MaintenanceIssueStatus.open,
      reportedAt: DateTime.now(),
    );
    _maintenanceIssues.add(issue);
    return issue;
  }

  @override
  Future<void> resolveMaintenanceIssue(String householdId, String issueId, {String? notes}) async {
    final index = _maintenanceIssues.indexWhere((i) => i.id == issueId);
    final current = _maintenanceIssues[index];
    _maintenanceIssues[index] = MaintenanceIssue(
      id: current.id,
      title: current.title,
      area: current.area,
      description: current.description,
      status: MaintenanceIssueStatus.resolved,
      reportedAt: current.reportedAt,
      resolvedAt: DateTime.now(),
      notes: notes ?? current.notes,
    );
  }
}

class DemoFermentationGateway implements FermentationGateway {
  final List<FermentationProject> _projects = [
    FermentationProject(
      id: 'f1',
      projectType: 'sourdough_starter',
      name: 'Rustic Rye',
      status: FermentationStatus.active,
      startedAt: DateTime.now().subtract(const Duration(days: 20)),
      currentStage: null,
      targetParams: const {'state': 'active', 'feed_interval_hours': 24},
    ),
    FermentationProject(
      id: 'f2',
      projectType: 'cacao',
      name: 'Backyard Cacao Batch 1',
      status: FermentationStatus.active,
      startedAt: DateTime.now().subtract(const Duration(days: 3)),
      currentStage: 'fermenting',
    ),
  ];
  final List<FermentationLog> _logs = [
    FermentationLog(
      id: 'l1',
      projectId: 'f1',
      loggedAt: DateTime.now().subtract(const Duration(hours: 30)),
      logType: FermentationLogType.feeding,
      payload: const {'starterG': 10, 'flourG': 50, 'waterG': 50, 'flourType': 'rye'},
      author: 'user',
    ),
  ];
  int _logCounter = 1;

  @override
  Future<List<FermentationProject>> fetchProjects(String householdId, {FermentationStatus? status}) async {
    final filterStatus = status ?? FermentationStatus.active;
    return _projects.where((p) => p.status == filterStatus).toList();
  }

  @override
  Future<FermentationProjectDetail> fetchProject(String householdId, String projectId) async {
    final project = _projects.firstWhere((p) => p.id == projectId);
    final logs = _logs.where((l) => l.projectId == projectId).toList()
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    return FermentationProjectDetail(project: project, logs: logs);
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
    final project = FermentationProject(
      id: 'f-new-${_projects.length + 1}',
      projectType: projectType,
      name: name,
      status: FermentationStatus.active,
      startedAt: DateTime.now(),
      targetParams: targetParams ?? const {},
      nextCheckAt: nextCheckAt,
      notes: notes,
    );
    _projects.add(project);
    return project;
  }

  @override
  Future<FermentationLog> logEvent(
    String householdId,
    String projectId, {
    required FermentationLogType logType,
    Map<String, dynamic>? payload,
    String? notes,
  }) async {
    final log = FermentationLog(
      id: 'l-new-${++_logCounter}',
      projectId: projectId,
      loggedAt: DateTime.now(),
      logType: logType,
      payload: payload ?? const {},
      notes: notes,
      author: 'user',
    );
    _logs.add(log);
    return log;
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
    final log = FermentationLog(
      id: 'l-new-${++_logCounter}',
      projectId: projectId,
      loggedAt: DateTime.now(),
      logType: FermentationLogType.feeding,
      payload: {
        'starterG': starterG,
        'flourG': flourG,
        'waterG': waterG,
        'flourType': ?flourType,
        'discardG': ?discardG,
      },
      notes: notes,
      author: 'user',
    );
    _logs.add(log);
    return log;
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
    final index = _projects.indexWhere((p) => p.id == projectId);
    final current = _projects[index];
    final updated = FermentationProject(
      id: current.id,
      projectType: current.projectType,
      name: current.name,
      status: status ?? current.status,
      startedAt: current.startedAt,
      endedAt: (status == FermentationStatus.completed || status == FermentationStatus.discarded)
          ? (current.endedAt ?? DateTime.now())
          : current.endedAt,
      currentStage: currentStage ?? current.currentStage,
      targetParams: current.targetParams,
      nextCheckAt: nextCheckAt ?? current.nextCheckAt,
      notes: current.notes,
    );
    _projects[index] = updated;
    return updated;
  }
}
