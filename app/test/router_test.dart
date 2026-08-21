// Stream 4 — navigation shell tests: auth/session routing, household-gated
// routes, responsive layout selection, Kitchen Device Mode behavior (and its
// device-locality), and that Kitchen Mode changes chrome only, never access.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiehome/app.dart';
import 'package:foodiehome/core/kitchen_mode.dart';
import 'package:foodiehome/core/router.dart';
import 'package:foodiehome/core/shell_layout.dart';
import 'package:foodiehome/data/foodie_gateway.dart';
import 'package:foodiehome/features/auth/household_gate_screen.dart';
import 'package:foodiehome/features/auth/session.dart';
import 'package:foodiehome/features/auth/sign_in_screen.dart';
import 'package:foodiehome/features/dashboard/dashboard_screen.dart';
import 'package:foodiehome/features/fermentation/fermentation_controller.dart';
import 'package:foodiehome/features/foodie/chat_controller.dart';
import 'package:foodiehome/features/foodie/chat_screen.dart';
import 'package:foodiehome/features/grocery/grocery_controller.dart';
import 'package:foodiehome/features/home_care/home_care_controller.dart';
import 'package:foodiehome/features/inventory/inventory_controller.dart';

import 'fakes.dart';

const _phoneSize = Size(390, 844); // iPhone-class width, well under 840
const _tabletSize = Size(1024, 768); // iPad-class width, well over 840

Future<void> _pumpApp(
  WidgetTester tester, {
  required FakeAuthGateway auth,
  required FakeHouseholdGateway households,
  DeviceKeyValueStore? deviceStore,
  FoodieGateway? foodieGateway,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authGatewayProvider.overrideWithValue(auth),
        householdGatewayProvider.overrideWithValue(households),
        if (deviceStore != null) deviceStoreProvider.overrideWithValue(deviceStore),
        if (foodieGateway != null)
          foodieGatewayProvider.overrideWithValue(foodieGateway),
        // The dashboard aggregates every domain controller on landing —
        // give it fakes so it doesn't reach for a real Supabase client.
        groceryGatewayProvider.overrideWithValue(FakeGroceryGateway()),
        inventoryGatewayProvider.overrideWithValue(FakeInventoryGateway()),
        homeCareGatewayProvider.overrideWithValue(FakeHomeCareGateway()),
        fermentationGatewayProvider.overrideWithValue(FakeFermentationGateway()),
      ],
      child: const FoodieHomeApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ---------------------------------------------------------------------
  // Pure layout resolution (unit-level, no widgets).
  // ---------------------------------------------------------------------
  group('resolveShellLayout', () {
    test('phone layout selection: narrow width, kitchen mode off', () {
      expect(resolveShellLayout(width: 390, kitchenMode: false), ShellLayout.phone);
      expect(resolveShellLayout(width: tabletBreakpoint - 1, kitchenMode: false),
          ShellLayout.phone);
    });

    test('tablet layout selection: wide width, kitchen mode off', () {
      expect(resolveShellLayout(width: tabletBreakpoint, kitchenMode: false),
          ShellLayout.tablet);
      expect(resolveShellLayout(width: 1200, kitchenMode: false), ShellLayout.tablet);
    });

    test('Kitchen Device Mode layout wins regardless of width', () {
      expect(resolveShellLayout(width: 390, kitchenMode: true), ShellLayout.kitchen);
      expect(resolveShellLayout(width: 1200, kitchenMode: true), ShellLayout.kitchen);
    });
  });

  // ---------------------------------------------------------------------
  // Auth/session routing.
  // ---------------------------------------------------------------------
  group('auth/session routing', () {
    testWidgets('signed out shows the sign-in screen', (tester) async {
      await _pumpApp(
        tester,
        auth: FakeAuthGateway(),
        households: FakeHouseholdGateway(),
      );
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);
    });

    testWidgets('household-required routing: signed in without a household '
        'is confined to setup, even when a shell route is requested',
        (tester) async {
      final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
      final households = FakeHouseholdGateway();
      await _pumpApp(tester, auth: auth, households: households);

      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.c');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(HouseholdGateScreen), findsOneWidget);

      // Directly requesting a shell route must not escape /setup.
      final element = tester.element(find.byType(FoodieHomeApp));
      final router = ProviderScope.containerOf(element).read(routerProvider);
      router.go('/grocery');
      await tester.pumpAndSettle();
      expect(find.byType(HouseholdGateScreen), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/setup');
    });

    testWidgets('ready lands on the dashboard', (tester) async {
      final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
      final households = FakeHouseholdGateway();
      await _pumpApp(tester, auth: auth, households: households);
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.c');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Household name'), 'Sunnybrook');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardScreen), findsOneWidget);
      // Named distinctly from the "Home" nav destination to avoid a text
      // collision in the phone shell's bottom bar.
      expect(find.text('Sunnybrook'), findsOneWidget);
    });

    testWidgets(
        'Kitchen Device Mode does not bypass auth: signed-out stays on sign-in',
        (tester) async {
      await _pumpApp(
        tester,
        auth: FakeAuthGateway(),
        households: FakeHouseholdGateway(),
        deviceStore: FakeDeviceKeyValueStore(kitchenMode: true),
      );

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.byKey(const Key('kitchenShell')), findsNothing);
      expect(find.byType(DashboardScreen), findsNothing);
    });
  });

  // ---------------------------------------------------------------------
  // Responsive chrome, end to end through the real widget tree.
  // ---------------------------------------------------------------------
  group('shell chrome selection', () {
    Future<ProviderContainer> signInAndCreateHousehold(
      WidgetTester tester, {
      DeviceKeyValueStore? deviceStore,
    }) async {
      final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
      final households = FakeHouseholdGateway();
      await _pumpApp(tester,
          auth: auth, households: households, deviceStore: deviceStore);
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.c');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Household name'), 'Sunnybrook');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(FoodieHomeApp)));
    }

    testWidgets('phone width renders the bottom-navigation shell',
        (tester) async {
      tester.view.physicalSize = _phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await signInAndCreateHousehold(tester);

      expect(find.byKey(const Key('phoneShell')), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byKey(const Key('kitchenShell')), findsNothing);
    });

    testWidgets('tablet width renders the navigation-rail shell',
        (tester) async {
      tester.view.physicalSize = _tabletSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await signInAndCreateHousehold(tester);

      expect(find.byKey(const Key('tabletShell')), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets(
        'Kitchen Device Mode renders the simplified shell even at phone width',
        (tester) async {
      tester.view.physicalSize = _phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await signInAndCreateHousehold(
        tester,
        deviceStore: FakeDeviceKeyValueStore(kitchenMode: true),
      );

      expect(find.byKey(const Key('kitchenShell')), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets(
        'Kitchen Mode remains device-specific: two independent device stores '
        'never see each other\'s setting', (tester) async {
      final deviceA = FakeDeviceKeyValueStore(kitchenMode: true);
      final deviceB = FakeDeviceKeyValueStore(kitchenMode: false);

      final containerA = ProviderContainer(
          overrides: [deviceStoreProvider.overrideWithValue(deviceA)]);
      final containerB = ProviderContainer(
          overrides: [deviceStoreProvider.overrideWithValue(deviceB)]);
      addTearDown(containerA.dispose);
      addTearDown(containerB.dispose);

      final resultA = await containerA.read(kitchenModeProvider.future);
      final resultB = await containerB.read(kitchenModeProvider.future);

      expect(resultA, isTrue);
      expect(resultB, isFalse);

      // Toggling one device's store never touches the other's.
      await containerA.read(kitchenModeProvider.notifier).setEnabled(false);
      expect(await deviceB.getBool('device.kitchen_mode'), isFalse);
      expect(await deviceA.getBool('device.kitchen_mode'), isFalse);
    });
  });

  // ---------------------------------------------------------------------
  // Foodie remains reachable through the new shell.
  // ---------------------------------------------------------------------
  testWidgets('Foodie chat is reachable from the phone shell',
      (tester) async {
    tester.view.physicalSize = _phoneSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final households = FakeHouseholdGateway();
    await _pumpApp(
      tester,
      auth: auth,
      households: households,
      foodieGateway: FakeFoodieGateway(),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.c');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Household name'), 'Sunnybrook');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(NavigationDestination, 'Foodie'));
    await tester.pumpAndSettle();

    expect(find.byType(FoodieChatScreen), findsOneWidget);
  });
}
