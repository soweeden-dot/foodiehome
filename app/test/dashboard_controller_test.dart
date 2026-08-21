import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiehome/domain/home_care.dart';
import 'package:foodiehome/domain/recurrence.dart';
import 'package:foodiehome/features/auth/session.dart';
import 'package:foodiehome/features/dashboard/dashboard_controller.dart';
import 'package:foodiehome/features/fermentation/fermentation_controller.dart';
import 'package:foodiehome/features/grocery/grocery_controller.dart';
import 'package:foodiehome/features/home_care/home_care_controller.dart';
import 'package:foodiehome/features/inventory/inventory_controller.dart';

import 'fakes.dart';

void main() {
  late FakeAuthGateway auth;
  late FakeHouseholdGateway households;
  late FakeGroceryGateway grocery;
  late FakeInventoryGateway inventory;
  late FakeHomeCareGateway homeCare;
  late FakeFermentationGateway fermentation;
  late ProviderContainer container;

  setUp(() async {
    auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    households = FakeHouseholdGateway();
    grocery = FakeGroceryGateway();
    inventory = FakeInventoryGateway();
    homeCare = FakeHomeCareGateway();
    fermentation = FakeFermentationGateway();
    // Deliberately NOT overriding foodieGatewayProvider (the AI chat
    // gateway) or any Anthropic/model provider — this is the proof the
    // dashboard has zero AI/network dependency: if DashboardController ever
    // touched an AI provider, this container would have nothing to serve
    // it and the test would fail loudly rather than silently succeeding.
    container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(auth),
      householdGatewayProvider.overrideWithValue(households),
      groceryGatewayProvider.overrideWithValue(grocery),
      inventoryGatewayProvider.overrideWithValue(inventory),
      homeCareGatewayProvider.overrideWithValue(homeCare),
      fermentationGatewayProvider.overrideWithValue(fermentation),
    ]);
    container.listen(sessionProvider, (_, _) {});
    final actions = container.read(sessionActionsProvider);
    await actions.signIn(email: 'a@b.c', password: 'pw');
    await actions.createHousehold('Home');
    await container.pump();
    await container.pump();
    await container.read(sessionProvider.future);
  });

  tearDown(() => container.dispose());

  test(
    'renders successfully with zero AI/network dependency: no FoodieGateway override needed',
    () async {
      final snapshot = await container.read(dashboardControllerProvider.future);
      expect(snapshot.isAllClear, isTrue);
    },
  );

  test('aggregates real data from every domain controller', () async {
    homeCare.cleaningTasks.add(CleaningTask(
      id: 'task-1',
      name: 'Vacuum',
      lastCompletedOn: DateTime.now().subtract(const Duration(days: 30)),
      recurrence: const RecurrenceSummary(
        intervalUnit: RecurrenceIntervalUnit.week,
        intervalCount: 1,
        weekday: 0,
      ),
    ));
    homeCare.trackedComponents.add(const TrackedComponent(
      id: 'comp-1',
      systemName: 'Fridge',
      componentName: 'Water filter',
      kind: 'filter',
      replaceIntervalDays: 30,
    ));
    homeCare.maintenanceIssues.add(MaintenanceIssue(
      id: 'issue-1',
      title: 'Leaky faucet',
      status: MaintenanceIssueStatus.open,
      reportedAt: DateTime.now(),
    ));
    await fermentation.createProject(
      'hh-1',
      projectType: 'sourdough_starter',
      name: 'Rustic Rye',
      targetParams: const {'state': 'active', 'feed_interval_hours': 24},
    );
    await grocery.addItem('hh-1', name: 'Milk');

    // Refresh every source controller so the dashboard sees this data.
    container.invalidate(cleaningControllerProvider);
    container.invalidate(trackedComponentsControllerProvider);
    container.invalidate(maintenanceIssuesControllerProvider);
    container.invalidate(fermentationControllerProvider);
    container.invalidate(groceryControllerProvider);
    container.invalidate(dashboardControllerProvider);

    final snapshot = await container.read(dashboardControllerProvider.future);
    expect(snapshot.groceryUncheckedCount, 1);
    expect(snapshot.openMaintenanceIssues, hasLength(1));
    expect(snapshot.activeFermentationProjects, hasLength(1));
    expect(snapshot.isAllClear, isFalse);
  });

  test('dashboard refreshes automatically after a mutation on an underlying controller', () async {
    await container.read(dashboardControllerProvider.future);
    expect((await container.read(dashboardControllerProvider.future)).openMaintenanceIssues, isEmpty);

    await container
        .read(maintenanceIssuesControllerProvider.notifier)
        .reportIssue(title: 'Leaky faucet');

    final snapshot = await container.read(dashboardControllerProvider.future);
    expect(snapshot.openMaintenanceIssues, hasLength(1));
  });
}
