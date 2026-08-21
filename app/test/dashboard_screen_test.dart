// Home Dashboard / Kitchen Command Center widget tests: phone vs Kitchen
// Mode layout selection, empty states, attention items, and quick actions.
// Pumped through the real app/router (like router_test.dart) so
// context.go(...) navigation inside the dashboard has a GoRouter ancestor.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiehome/app.dart';
import 'package:foodiehome/core/kitchen_mode.dart';
import 'package:foodiehome/domain/home_care.dart';
import 'package:foodiehome/features/auth/session.dart';
import 'package:foodiehome/features/fermentation/fermentation_controller.dart';
import 'package:foodiehome/features/grocery/grocery_controller.dart';
import 'package:foodiehome/features/home_care/home_care_controller.dart';
import 'package:foodiehome/features/inventory/inventory_controller.dart';

import 'fakes.dart';

const _phoneSize = Size(390, 844);

Future<void> _pumpToDashboard(
  WidgetTester tester, {
  required FakeAuthGateway auth,
  required FakeHouseholdGateway households,
  required FakeGroceryGateway grocery,
  required FakeInventoryGateway inventory,
  required FakeHomeCareGateway homeCare,
  required FakeFermentationGateway fermentation,
  DeviceKeyValueStore? deviceStore,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authGatewayProvider.overrideWithValue(auth),
        householdGatewayProvider.overrideWithValue(households),
        groceryGatewayProvider.overrideWithValue(grocery),
        inventoryGatewayProvider.overrideWithValue(inventory),
        homeCareGatewayProvider.overrideWithValue(homeCare),
        fermentationGatewayProvider.overrideWithValue(fermentation),
        if (deviceStore != null) deviceStoreProvider.overrideWithValue(deviceStore),
      ],
      child: const FoodieHomeApp(),
    ),
  );
  await tester.pumpAndSettle();

  await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.c');
  await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Household name'), 'Sunnybrook');
  await tester.tap(find.widgetWithText(FilledButton, 'Create'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone layout: all-clear empty state, no fabricated content', (tester) async {
    tester.view.physicalSize = _phoneSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    await _pumpToDashboard(
      tester,
      auth: auth,
      households: FakeHouseholdGateway(),
      grocery: FakeGroceryGateway(),
      inventory: FakeInventoryGateway(),
      homeCare: FakeHomeCareGateway(),
      fermentation: FakeFermentationGateway(),
      deviceStore: FakeDeviceKeyValueStore(kitchenMode: false),
    );

    expect(find.text('All caught up'), findsOneWidget);
    expect(find.text('Grocery list is clear'), findsOneWidget);
    expect(find.text('No active fermentation projects'), findsOneWidget);
    expect(find.textContaining('all caught up'), findsWidgets); // Home section
  });

  testWidgets('kitchen layout: all-clear shows the big empty-state card and big buttons',
      (tester) async {
    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    await _pumpToDashboard(
      tester,
      auth: auth,
      households: FakeHouseholdGateway(),
      grocery: FakeGroceryGateway(),
      inventory: FakeInventoryGateway(),
      homeCare: FakeHomeCareGateway(),
      fermentation: FakeFermentationGateway(),
      deviceStore: FakeDeviceKeyValueStore(kitchenMode: true),
    );

    expect(find.text('All caught up.'), findsOneWidget);
    expect(find.text('Nothing needs attention'), findsOneWidget);
    expect(find.text('Ask Foodie'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);
  });

  testWidgets('kitchen layout: an overdue filter and an open maintenance issue show as attention tiles',
      (tester) async {
    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final homeCare = FakeHomeCareGateway()
      ..trackedComponents.add(TrackedComponent(
        id: 'comp-1',
        systemName: 'Fridge',
        componentName: 'Water filter',
        kind: 'filter',
        installedOn: DateTime.now().subtract(const Duration(days: 100)),
        replaceIntervalDays: 30, // installed 100 days ago, replace every 30 → overdue
      ))
      ..maintenanceIssues.add(MaintenanceIssue(
        id: 'issue-1',
        title: 'Leaky faucet',
        status: MaintenanceIssueStatus.open,
        reportedAt: DateTime.now(),
      ));

    await _pumpToDashboard(
      tester,
      auth: auth,
      households: FakeHouseholdGateway(),
      grocery: FakeGroceryGateway(),
      inventory: FakeInventoryGateway(),
      homeCare: homeCare,
      fermentation: FakeFermentationGateway(),
      deviceStore: FakeDeviceKeyValueStore(kitchenMode: true),
    );

    expect(find.text('Leaky faucet'), findsOneWidget);
    expect(find.textContaining('thing'), findsOneWidget); // "N things need attention"
  });

  testWidgets('quick action: Add grocery item opens the dialog and calls the gateway',
      (tester) async {
    tester.view.physicalSize = _phoneSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final grocery = FakeGroceryGateway();
    await _pumpToDashboard(
      tester,
      auth: auth,
      households: FakeHouseholdGateway(),
      grocery: grocery,
      inventory: FakeInventoryGateway(),
      homeCare: FakeHomeCareGateway(),
      fermentation: FakeFermentationGateway(),
      deviceStore: FakeDeviceKeyValueStore(kitchenMode: false),
    );

    await tester.tap(find.widgetWithText(ActionChip, 'Add grocery item'));
    await tester.pumpAndSettle();

    expect(find.text('Add grocery item'), findsWidgets); // dialog title + chip

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Butter');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(grocery.items.map((i) => i.name), contains('Butter'));
  });

  testWidgets('quick action: Start fermentation opens the dialog and calls the gateway',
      (tester) async {
    tester.view.physicalSize = _phoneSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final fermentation = FakeFermentationGateway();
    await _pumpToDashboard(
      tester,
      auth: auth,
      households: FakeHouseholdGateway(),
      grocery: FakeGroceryGateway(),
      inventory: FakeInventoryGateway(),
      homeCare: FakeHomeCareGateway(),
      fermentation: fermentation,
      deviceStore: FakeDeviceKeyValueStore(kitchenMode: false),
    );

    await tester.tap(find.widgetWithText(ActionChip, 'Start fermentation'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Rustic Rye');
    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pumpAndSettle();

    expect(fermentation.projects.map((p) => p.name), contains('Rustic Rye'));
  });

  testWidgets('phone layout: an active sourdough project appears in the Fermentation section',
      (tester) async {
    tester.view.physicalSize = _phoneSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final fermentation = FakeFermentationGateway();
    await fermentation.createProject(
      'hh-1',
      projectType: 'sourdough_starter',
      name: 'Rustic Rye',
      targetParams: const {'state': 'active', 'feed_interval_hours': 24},
    );

    await _pumpToDashboard(
      tester,
      auth: auth,
      households: FakeHouseholdGateway(),
      grocery: FakeGroceryGateway(),
      inventory: FakeInventoryGateway(),
      homeCare: FakeHomeCareGateway(),
      fermentation: fermentation,
      deviceStore: FakeDeviceKeyValueStore(kitchenMode: false),
    );

    expect(find.textContaining('Rustic Rye'), findsOneWidget);
  });
}
