import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiehome/domain/inventory.dart';
import 'package:foodiehome/features/auth/session.dart';
import 'package:foodiehome/features/inventory/inventory_controller.dart';

import 'fakes.dart';

void main() {
  late FakeAuthGateway auth;
  late FakeHouseholdGateway households;
  late FakeInventoryGateway inventory;
  late ProviderContainer container;

  setUp(() async {
    auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    households = FakeHouseholdGateway();
    inventory = FakeInventoryGateway();
    container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(auth),
      householdGatewayProvider.overrideWithValue(households),
      inventoryGatewayProvider.overrideWithValue(inventory),
    ]);
    container.listen(sessionProvider, (_, _) {});
    final actions = container.read(sessionActionsProvider);
    await actions.signIn(email: 'a@b.c', password: 'pw');
    await actions.createHousehold('Home');
    // Let the session stream settle into Ready before each test.
    await container.pump();
    await container.pump();
    await container.read(sessionProvider.future);
  });

  tearDown(() => container.dispose());

  test('starts empty, no household-scoped call until session is Ready', () async {
    final snapshot = await container.read(inventoryControllerProvider.future);
    expect(snapshot.items, isEmpty);
    expect(snapshot.locations, isEmpty);
  });

  test('addItem persists via the gateway and refreshes state', () async {
    await container.read(inventoryControllerProvider.future); // settle
    await container.read(inventoryControllerProvider.notifier).addItem(
          name: 'Milk',
          locationName: 'Fridge',
          quantity: 1,
          unit: 'l',
        );

    final snapshot = await container.read(inventoryControllerProvider.future);
    expect(snapshot.items, hasLength(1));
    expect(snapshot.items.single.name, 'Milk');
    expect(snapshot.items.single.locationName, 'Fridge');
    expect(snapshot.locations.map((l) => l.name), ['Fridge']);
  });

  test('adding to the same location name twice does not duplicate it', () async {
    await container.read(inventoryControllerProvider.future);
    final actions = container.read(inventoryControllerProvider.notifier);
    await actions.addItem(name: 'Milk', locationName: 'Fridge');
    await actions.addItem(name: 'Eggs', locationName: 'fridge'); // different case

    final snapshot = await container.read(inventoryControllerProvider.future);
    expect(snapshot.locations, hasLength(1));
  });

  test('updateItem changes only the provided fields', () async {
    await container.read(inventoryControllerProvider.future);
    final actions = container.read(inventoryControllerProvider.notifier);
    await actions.addItem(name: 'Milk', unit: 'l', quantity: 1);
    final itemId = inventory.items.single.id;

    await actions.updateItem(itemId, quantity: 0.5);

    final snapshot = await container.read(inventoryControllerProvider.future);
    final updated = snapshot.items.single;
    expect(updated.quantity, 0.5);
    expect(updated.unit, 'l'); // untouched
  });

  test('removeItem removes it from subsequent reads', () async {
    await container.read(inventoryControllerProvider.future);
    final actions = container.read(inventoryControllerProvider.notifier);
    await actions.addItem(name: 'Milk');
    final itemId = inventory.items.single.id;

    await actions.removeItem(itemId);

    final snapshot = await container.read(inventoryControllerProvider.future);
    expect(snapshot.items, isEmpty);
  });

  test('applyInventoryFilter matches by name, notes, and location', () {
    const fridge = InventoryItem(id: '1', name: 'Milk', locationName: 'Fridge');
    const pantry = InventoryItem(
        id: '2', name: 'Rice', locationName: 'Pantry', notes: 'bulk bag');
    final items = [fridge, pantry];

    expect(applyInventoryFilter(items, const InventoryFilter(query: 'milk')),
        [fridge]);
    expect(applyInventoryFilter(items, const InventoryFilter(query: 'bulk')),
        [pantry]);
    expect(
      applyInventoryFilter(
          items, const InventoryFilter(locationName: 'Pantry')),
      [pantry],
    );
    expect(applyInventoryFilter(items, const InventoryFilter()), items);
  });

  test('InventoryItem expiry helpers', () {
    final now = DateTime(2026, 8, 20);
    final expired = InventoryItem(
        id: '1', name: 'Old milk', expiresOn: DateTime(2026, 8, 19));
    final soon = InventoryItem(
        id: '2', name: 'Yogurt', expiresOn: DateTime(2026, 8, 21));
    final fine = InventoryItem(
        id: '3', name: 'Frozen peas', expiresOn: DateTime(2027, 1, 1));

    expect(expired.isExpired(asOf: now), isTrue);
    expect(expired.isExpiringSoon(asOf: now), isFalse); // already expired
    expect(soon.isExpiringSoon(asOf: now), isTrue);
    expect(fine.isExpired(asOf: now), isFalse);
    expect(fine.isExpiringSoon(asOf: now), isFalse);
  });

  test('gateway failure surfaces as an error, not a silent no-op', () async {
    await container.read(inventoryControllerProvider.future);
    inventory.failNextCall = StateError('boom');
    await expectLater(
      container.read(inventoryControllerProvider.notifier).addItem(name: 'Milk'),
      throwsStateError,
    );
    // Nothing was actually added.
    final snapshot = await container.read(inventoryControllerProvider.future);
    expect(snapshot.items, isEmpty);
  });
}
