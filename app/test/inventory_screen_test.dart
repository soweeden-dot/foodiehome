import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiehome/domain/inventory.dart';
import 'package:foodiehome/features/auth/session.dart';
import 'package:foodiehome/features/inventory/inventory_controller.dart';
import 'package:foodiehome/features/inventory/inventory_screen.dart';

import 'fakes.dart';

/// Pumps the widget tree, then drives sign-in + household creation through
/// the real action provider (so session invalidation fires correctly), then
/// settles.
Future<void> _signInReady(WidgetTester tester, ProviderContainer container) async {
  final actions = container.read(sessionActionsProvider);
  await actions.signIn(email: 'a@b.c', password: 'pw');
  await actions.createHousehold('Home');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty inventory shows the empty state, not a blank screen',
      (tester) async {
    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final households = FakeHouseholdGateway();
    final inventory = FakeInventoryGateway();

    final container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(auth),
      householdGatewayProvider.overrideWithValue(households),
      inventoryGatewayProvider.overrideWithValue(inventory),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InventoryScreen()),
      ),
    );
    await _signInReady(tester, container);

    expect(find.text('No inventory yet'), findsOneWidget);
  });

  testWidgets('items render and search filters them', (tester) async {
    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final households = FakeHouseholdGateway();
    final inventory = FakeInventoryGateway()
      ..locations.add(const InventoryLocation(id: 'loc-1', name: 'Fridge', kind: 'other'))
      ..items.addAll(const [
        InventoryItem(id: 'inv-1', name: 'Milk', locationName: 'Fridge', quantity: 1, unit: 'l'),
        InventoryItem(id: 'inv-2', name: 'Rice', quantity: 2, unit: 'kg'),
      ]);

    final container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(auth),
      householdGatewayProvider.overrideWithValue(households),
      inventoryGatewayProvider.overrideWithValue(inventory),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InventoryScreen()),
      ),
    );
    await _signInReady(tester, container);

    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('Rice'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'milk');
    await tester.pumpAndSettle();

    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('Rice'), findsNothing);
  });

  testWidgets('add item flow calls the gateway and closes the form',
      (tester) async {
    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final households = FakeHouseholdGateway();
    final inventory = FakeInventoryGateway();

    final container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(auth),
      householdGatewayProvider.overrideWithValue(households),
      inventoryGatewayProvider.overrideWithValue(inventory),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InventoryScreen()),
      ),
    );
    await _signInReady(tester, container);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Add item'), findsWidgets); // AppBar title + button

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Butter');
    final submitButton = find.widgetWithText(FilledButton, 'Add item');
    await tester.scrollUntilVisible(submitButton, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(submitButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(inventory.items.map((i) => i.name), contains('Butter'));
    // Form popped back to the list, which now shows the new item.
    expect(find.text('Butter'), findsOneWidget);
  });
}
