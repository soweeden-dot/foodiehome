import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiehome/domain/home_care.dart';
import 'package:foodiehome/domain/recurrence.dart';
import 'package:foodiehome/features/auth/session.dart';
import 'package:foodiehome/features/home_care/filters_screen.dart';
import 'package:foodiehome/features/home_care/home_care_controller.dart';
import 'package:foodiehome/features/home_care/home_care_screen.dart';

import 'fakes.dart';

Future<void> _signInReady(WidgetTester tester, ProviderContainer container) async {
  final actions = container.read(sessionActionsProvider);
  await actions.signIn(email: 'a@b.c', password: 'pw');
  await actions.createHousehold('Home');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty cleaning tab shows the empty state', (tester) async {
    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final households = FakeHouseholdGateway();
    final homeCare = FakeHomeCareGateway();

    final container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(auth),
      householdGatewayProvider.overrideWithValue(households),
      homeCareGatewayProvider.overrideWithValue(homeCare),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeCareScreen()),
      ),
    );
    await _signInReady(tester, container);

    expect(find.text('No cleaning tasks yet'), findsOneWidget);
  });

  testWidgets('tapping done on a cleaning task calls the gateway', (tester) async {
    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final households = FakeHouseholdGateway();
    final homeCare = FakeHomeCareGateway()
      ..cleaningTasks.add(const CleaningTask(
        id: 'task-1',
        name: 'Clean bathroom',
        area: 'Bathroom',
        recurrence: RecurrenceSummary(
          intervalUnit: RecurrenceIntervalUnit.week,
          intervalCount: 1,
          weekday: 0,
        ),
      ));

    final container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(auth),
      householdGatewayProvider.overrideWithValue(households),
      homeCareGatewayProvider.overrideWithValue(homeCare),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeCareScreen()),
      ),
    );
    await _signInReady(tester, container);

    expect(find.text('Clean bathroom'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.done));
    await tester.pumpAndSettle();

    expect(homeCare.cleaningTasks.single.lastCompletedOn, isNotNull);
  });

  testWidgets('report maintenance issue flow calls the gateway and closes the dialog',
      (tester) async {
    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final households = FakeHouseholdGateway();
    final homeCare = FakeHomeCareGateway();

    final container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(auth),
      householdGatewayProvider.overrideWithValue(households),
      homeCareGatewayProvider.overrideWithValue(homeCare),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeCareScreen()),
      ),
    );
    await _signInReady(tester, container);

    await tester.tap(find.text('Maintenance'));
    await tester.pumpAndSettle();
    expect(find.text('No maintenance issues'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Leaky faucet');
    await tester.tap(find.widgetWithText(FilledButton, 'Report'));
    await tester.pumpAndSettle();

    expect(homeCare.maintenanceIssues.map((i) => i.title), contains('Leaky faucet'));
    expect(find.text('Leaky faucet'), findsOneWidget);
  });

  testWidgets('filters screen shows tracked components and logs a replacement',
      (tester) async {
    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final households = FakeHouseholdGateway();
    final homeCare = FakeHomeCareGateway()
      ..trackedComponents.add(const TrackedComponent(
        id: 'comp-1',
        systemName: 'Kitchen fridge',
        componentName: 'Water filter',
        kind: 'filter',
        replaceIntervalDays: 90,
        sparesCount: 1,
      ));

    final container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(auth),
      householdGatewayProvider.overrideWithValue(households),
      homeCareGatewayProvider.overrideWithValue(homeCare),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FiltersScreen()),
      ),
    );
    await _signInReady(tester, container);

    expect(find.textContaining('Water filter'), findsOneWidget);

    await tester.tap(find.text('Log replacement'));
    await tester.pumpAndSettle();

    expect(homeCare.trackedComponents.single.sparesCount, 0);
  });
}
