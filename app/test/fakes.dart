import 'dart:async';

import 'package:foodiehome/core/kitchen_mode.dart';
import 'package:foodiehome/data/auth_gateway.dart';
import 'package:foodiehome/data/fermentation_gateway.dart';
import 'package:foodiehome/data/foodie_gateway.dart';
import 'package:foodiehome/data/grocery_gateway.dart';
import 'package:foodiehome/data/home_care_gateway.dart';
import 'package:foodiehome/data/household_gateway.dart';
import 'package:foodiehome/data/inventory_gateway.dart';
import 'package:foodiehome/domain/fermentation.dart';
import 'package:foodiehome/domain/grocery.dart';
import 'package:foodiehome/domain/home_care.dart';
import 'package:foodiehome/domain/household.dart';
import 'package:foodiehome/domain/inventory.dart';

class FakeAuthGateway implements AuthGateway {
  // Not an async* generator: listeners must be registered synchronously so an
  // emission between "listen" and a generator's yield* can never be dropped.
  final _listeners = <StreamController<String?>>[];
  String? _userId;

  /// Emails registered via [signUp] (or seeded by tests).
  final Map<String, String> accounts = {};

  @override
  String? get currentUserId => _userId;

  @override
  Stream<String?> authUserIdChanges() {
    late final StreamController<String?> controller;
    controller = StreamController<String?>(
      onListen: () {
        controller.add(_userId);
        _listeners.add(controller);
      },
      onCancel: () => _listeners.remove(controller),
    );
    return controller.stream;
  }

  void _set(String? id) {
    _userId = id;
    for (final controller in List.of(_listeners)) {
      controller.add(id);
    }
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (accounts[email.trim()] != password) {
      throw StateError('invalid credentials');
    }
    _set('user-${email.trim()}');
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    accounts[email.trim()] = password;
    _set('user-${email.trim()}');
  }

  @override
  Future<void> signOut() async => _set(null);
}

class FakeHouseholdGateway implements HouseholdGateway {
  FakeHouseholdGateway({this.knownInviteCode = 'abc123'});

  final String knownInviteCode;
  final List<Household> memberships = [];
  int createCalls = 0;

  @override
  Future<List<Household>> fetchMyHouseholds() async => List.of(memberships);

  @override
  Future<Household> createHousehold(String name) async {
    createCalls++;
    final household = Household(
      id: 'hh-${memberships.length + 1}',
      name: name,
      createdBy: 'creator',
      inviteCode: knownInviteCode,
    );
    memberships.add(household);
    return household;
  }

  @override
  Future<String> redeemInvite(String code) async {
    if (code != knownInviteCode) {
      throw StateError('invalid invite code');
    }
    const joined = Household(
      id: 'hh-joined',
      name: 'Joined household',
      createdBy: 'someone-else',
      inviteCode: 'abc123',
    );
    memberships.add(joined);
    return joined.id;
  }

  @override
  Future<void> leaveHousehold(String householdId) async {
    memberships.removeWhere((h) => h.id == householdId);
  }

  @override
  Future<String> regenerateInviteCode(String householdId) async => 'newcode';

  List<HouseholdMember> members = const [
    HouseholdMember(displayName: 'Alice', isAdmin: true),
  ];

  @override
  Future<List<HouseholdMember>> fetchMembers(String householdId) async =>
      List.of(members);
}

/// In-memory stand-in for one device's local storage. Two separate
/// instances simulate two separate physical devices — nothing is shared
/// between them, which is exactly the property Kitchen Mode depends on.
class FakeDeviceKeyValueStore implements DeviceKeyValueStore {
  FakeDeviceKeyValueStore({bool? kitchenMode})
      : _values = {'device.kitchen_mode': ?kitchenMode};

  final Map<String, bool> _values;

  @override
  Future<bool?> getBool(String key) async => _values[key];

  @override
  Future<void> setBool(String key, bool value) async => _values[key] = value;
}

class FakeFoodieGateway implements FoodieGateway {
  FakeFoodieGateway([List<FoodieReply>? replies]) : _replies = replies ?? [];

  final List<FoodieReply> _replies;
  final List<({String message, String? conversationId})> calls = [];

  @override
  Future<FoodieReply> sendMessage({
    required String message,
    String? conversationId,
  }) async {
    calls.add((message: message, conversationId: conversationId));
    if (_replies.isEmpty) {
      return const FoodieReply(
          conversationId: 'conv-fake', text: 'Hi!', actions: []);
    }
    return _replies.removeAt(0);
  }
}

class FakeInventoryGateway implements InventoryGateway {
  final List<InventoryLocation> locations = [];
  final List<InventoryItem> items = [];
  int idCounter = 0;
  Object? failNextCall;

  void _maybeThrow() {
    final error = failNextCall;
    if (error != null) {
      failNextCall = null;
      throw error;
    }
  }

  String _resolveLocation(String? name) {
    if (name == null || name.trim().isEmpty) return '';
    final trimmed = name.trim();
    final existing = locations.where(
        (l) => l.name.toLowerCase() == trimmed.toLowerCase());
    if (existing.isNotEmpty) return existing.first.name;
    locations.add(InventoryLocation(
        id: 'loc-${locations.length + 1}', name: trimmed, kind: 'other'));
    return trimmed;
  }

  @override
  Future<InventorySnapshot> fetchInventory(String householdId) async {
    _maybeThrow();
    return InventorySnapshot(locations: List.of(locations), items: List.of(items));
  }

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
    _maybeThrow();
    final resolvedLocation =
        locationName == null ? null : _resolveLocation(locationName);
    final item = InventoryItem(
      id: 'inv-${++idCounter}',
      name: name,
      locationName: resolvedLocation,
      quantity: quantity,
      unit: unit,
      level: level,
      expiresOn: expiresOn,
      notes: notes,
    );
    items.add(item);
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
    _maybeThrow();
    final index = items.indexWhere((i) => i.id == itemId);
    if (index == -1) {
      throw StateError('inventory item not found');
    }
    final updated = items[index].copyWith(
      quantity: quantity,
      unit: unit,
      level: level,
      expiresOn: expiresOn,
      openedOn: openedOn,
      notes: notes,
    );
    items[index] = updated;
    return updated;
  }

  @override
  Future<void> removeItem(String householdId, String itemId) async {
    _maybeThrow();
    final removed = items.any((i) => i.id == itemId);
    if (!removed) {
      throw StateError('inventory item not found');
    }
    items.removeWhere((i) => i.id == itemId);
  }
}

class FakeHomeCareGateway implements HomeCareGateway {
  final List<CleaningTask> cleaningTasks = [];
  final List<TrackedComponent> trackedComponents = [];
  final List<MaintenanceIssue> maintenanceIssues = [];
  int idCounter = 0;
  Object? failNextCall;

  void _maybeThrow() {
    final error = failNextCall;
    if (error != null) {
      failNextCall = null;
      throw error;
    }
  }

  @override
  Future<List<CleaningTask>> fetchCleaningTasks(String householdId) async {
    _maybeThrow();
    return List.of(cleaningTasks);
  }

  @override
  Future<void> completeCleaningTask(String householdId, String taskId, {String? notes}) async {
    _maybeThrow();
    final index = cleaningTasks.indexWhere((t) => t.id == taskId);
    if (index == -1) throw StateError('cleaning task not found');
    cleaningTasks[index] = CleaningTask(
      id: cleaningTasks[index].id,
      name: cleaningTasks[index].name,
      area: cleaningTasks[index].area,
      recurrence: cleaningTasks[index].recurrence,
      assignedUserName: cleaningTasks[index].assignedUserName,
      suppliesNeeded: cleaningTasks[index].suppliesNeeded,
      lastCompletedOn: DateTime.now(),
    );
  }

  @override
  Future<void> skipCleaningTask(String householdId, String taskId, {String? reason}) async {
    _maybeThrow();
    if (!cleaningTasks.any((t) => t.id == taskId)) {
      throw StateError('cleaning task not found');
    }
  }

  @override
  Future<List<TrackedComponent>> fetchTrackedComponents(String householdId) async {
    _maybeThrow();
    return List.of(trackedComponents);
  }

  @override
  Future<void> logFilterReplacement(String householdId, String componentId, {String? notes}) async {
    _maybeThrow();
    final index = trackedComponents.indexWhere((c) => c.id == componentId);
    if (index == -1) throw StateError('tracked component not found');
    final current = trackedComponents[index];
    trackedComponents[index] = TrackedComponent(
      id: current.id,
      systemName: current.systemName,
      componentName: current.componentName,
      kind: current.kind,
      installedOn: current.installedOn,
      replaceIntervalDays: current.replaceIntervalDays,
      sparesCount: (current.sparesCount - 1).clamp(0, 1 << 30),
      lastReplacedOn: DateTime.now(),
    );
  }

  @override
  Future<List<MaintenanceIssue>> fetchMaintenanceIssues(
    String householdId, {
    MaintenanceIssueStatus? status,
  }) async {
    _maybeThrow();
    return maintenanceIssues.where((i) => status == null || i.status == status).toList();
  }

  @override
  Future<MaintenanceIssue> reportMaintenanceIssue(
    String householdId, {
    required String title,
    String? area,
    String? description,
  }) async {
    _maybeThrow();
    final issue = MaintenanceIssue(
      id: 'issue-${++idCounter}',
      title: title,
      area: area,
      description: description,
      status: MaintenanceIssueStatus.open,
      reportedAt: DateTime.now(),
    );
    maintenanceIssues.add(issue);
    return issue;
  }

  @override
  Future<void> resolveMaintenanceIssue(String householdId, String issueId, {String? notes}) async {
    _maybeThrow();
    final index = maintenanceIssues.indexWhere((i) => i.id == issueId);
    if (index == -1) throw StateError('maintenance issue not found');
    final current = maintenanceIssues[index];
    maintenanceIssues[index] = MaintenanceIssue(
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

class FakeFermentationGateway implements FermentationGateway {
  final List<FermentationProject> projects = [];
  final List<FermentationLog> logs = [];
  int projectCounter = 0;
  int logCounter = 0;
  Object? failNextCall;

  void _maybeThrow() {
    final error = failNextCall;
    if (error != null) {
      failNextCall = null;
      throw error;
    }
  }

  @override
  Future<List<FermentationProject>> fetchProjects(String householdId, {FermentationStatus? status}) async {
    _maybeThrow();
    final filterStatus = status ?? FermentationStatus.active;
    return projects.where((p) => p.status == filterStatus).toList();
  }

  @override
  Future<FermentationProjectDetail> fetchProject(String householdId, String projectId) async {
    _maybeThrow();
    final project = projects.where((p) => p.id == projectId);
    if (project.isEmpty) throw StateError('fermentation project not found');
    final projectLogs = logs.where((l) => l.projectId == projectId).toList()
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    return FermentationProjectDetail(project: project.first, logs: projectLogs);
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
    _maybeThrow();
    final project = FermentationProject(
      id: 'ferm-${++projectCounter}',
      projectType: projectType,
      name: name,
      status: FermentationStatus.active,
      startedAt: DateTime.now(),
      targetParams: targetParams ?? const {},
      nextCheckAt: nextCheckAt,
      notes: notes,
    );
    projects.add(project);
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
    _maybeThrow();
    if (!projects.any((p) => p.id == projectId)) {
      throw StateError('fermentation project not found');
    }
    final log = FermentationLog(
      id: 'ferm-log-${++logCounter}',
      projectId: projectId,
      loggedAt: DateTime.now(),
      logType: logType,
      payload: payload ?? const {},
      notes: notes,
      author: 'foodie',
    );
    logs.add(log);
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
    _maybeThrow();
    if (!projects.any((p) => p.id == projectId)) {
      throw StateError('fermentation project not found');
    }
    final log = FermentationLog(
      id: 'ferm-log-${++logCounter}',
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
      author: 'foodie',
    );
    logs.add(log);
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
    _maybeThrow();
    final index = projects.indexWhere((p) => p.id == projectId);
    if (index == -1) throw StateError('fermentation project not found');
    final current = projects[index];
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
    projects[index] = updated;
    if (currentStage != null || status != null) {
      logs.add(FermentationLog(
        id: 'ferm-log-${++logCounter}',
        projectId: projectId,
        loggedAt: DateTime.now(),
        logType: FermentationLogType.stageChange,
        payload: {'toStage': updated.currentStage, 'toStatus': updated.status.toWire()},
        notes: notes,
        author: 'foodie',
      ));
    }
    return updated;
  }
}

class FakeGroceryGateway implements GroceryGateway {
  String listId = 'list-1';
  String listName = 'Groceries';
  final List<GroceryItem> items = [];
  int idCounter = 0;
  Object? failNextCall;

  void _maybeThrow() {
    final error = failNextCall;
    if (error != null) {
      failNextCall = null;
      throw error;
    }
  }

  @override
  Future<GroceryListSnapshot> fetchGroceryList(String householdId) async {
    _maybeThrow();
    if (items.isEmpty && listId.isEmpty) return GroceryListSnapshot.empty;
    return GroceryListSnapshot(listId: listId, listName: listName, items: List.of(items));
  }

  @override
  Future<GroceryItem> addItem(
    String householdId, {
    required String name,
    double? quantity,
    String? unit,
    String? notes,
  }) async {
    _maybeThrow();
    final item = GroceryItem(
      id: 'grocery-${++idCounter}',
      name: name,
      quantity: quantity,
      unit: unit,
      notes: notes,
    );
    items.add(item);
    return item;
  }
}
