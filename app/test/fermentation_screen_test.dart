import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiehome/features/auth/session.dart';
import 'package:foodiehome/features/fermentation/fermentation_controller.dart';
import 'package:foodiehome/features/fermentation/fermentation_screen.dart';

import 'fakes.dart';

Future<void> _signInReady(WidgetTester tester, ProviderContainer container) async {
  final actions = container.read(sessionActionsProvider);
  await actions.signIn(email: 'a@b.c', password: 'pw');
  await actions.createHousehold('Home');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty fermentation list shows the empty state', (tester) async {
    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final households = FakeHouseholdGateway();
    final fermentation = FakeFermentationGateway();

    final container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(auth),
      householdGatewayProvider.overrideWithValue(households),
      fermentationGatewayProvider.overrideWithValue(fermentation),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FermentationScreen()),
      ),
    );
    await _signInReady(tester, container);

    expect(find.text('No active fermentation projects'), findsOneWidget);
  });

  testWidgets('starting a sourdough project calls the gateway and shows it in the list',
      (tester) async {
    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final households = FakeHouseholdGateway();
    final fermentation = FakeFermentationGateway();

    final container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(auth),
      householdGatewayProvider.overrideWithValue(households),
      fermentationGatewayProvider.overrideWithValue(fermentation),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FermentationScreen()),
      ),
    );
    await _signInReady(tester, container);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Rustic Rye');
    await tester.tap(find.widgetWithText(FilledButton, 'Start'));
    await tester.pumpAndSettle();

    expect(fermentation.projects.map((p) => p.name), contains('Rustic Rye'));
    expect(find.text('Rustic Rye'), findsOneWidget);
  });

  testWidgets('tapping a project opens detail and logging a feeding calls the gateway',
      (tester) async {
    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final households = FakeHouseholdGateway();
    final fermentation = FakeFermentationGateway();
    await fermentation.createProject(
      'hh-1',
      projectType: 'sourdough_starter',
      name: 'Rustic Rye',
      targetParams: const {'state': 'active', 'feed_interval_hours': 24},
    );

    final container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(auth),
      householdGatewayProvider.overrideWithValue(households),
      fermentationGatewayProvider.overrideWithValue(fermentation),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FermentationScreen()),
      ),
    );
    await _signInReady(tester, container);

    await tester.tap(find.text('Rustic Rye'));
    await tester.pumpAndSettle();

    expect(find.text('No feedings logged yet.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Log feeding'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Starter (g)'), '10');
    await tester.enterText(find.widgetWithText(TextField, 'Flour (g)'), '50');
    await tester.enterText(find.widgetWithText(TextField, 'Water (g)'), '50');
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Log feeding'),
    ));
    await tester.pumpAndSettle();

    expect(fermentation.logs, hasLength(1));
    expect(find.textContaining('Hydration 100.0%'), findsOneWidget);
  });
}
