import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiehome/app.dart';
import 'package:foodiehome/features/auth/household_gate_screen.dart';
import 'package:foodiehome/features/auth/session.dart';
import 'package:foodiehome/features/auth/sign_in_screen.dart';
import 'package:foodiehome/features/dashboard/dashboard_screen.dart';

import 'fakes.dart';

void main() {
  testWidgets('signed out → sign in → create household → dashboard',
      (tester) async {
    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final households = FakeHouseholdGateway();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authGatewayProvider.overrideWithValue(auth),
          householdGatewayProvider.overrideWithValue(households),
        ],
        child: const FoodieHomeApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Signed out: the sign-in screen is shown.
    expect(find.byType(SignInScreen), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Email'), 'a@b.c');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    // Signed in without a household: the gate screen is shown.
    expect(find.byType(HouseholdGateScreen), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Household name'), 'Sunnybrook');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    // Household exists: the dashboard boundary shows the household name.
    // (Named distinctly from the "Home" nav destination to avoid a text
    // collision in the phone shell's bottom bar.)
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('Sunnybrook'), findsOneWidget);
  });

  testWidgets('wrong invite code shows an error and stays on the gate',
      (tester) async {
    final auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    final households = FakeHouseholdGateway();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authGatewayProvider.overrideWithValue(auth),
          householdGatewayProvider.overrideWithValue(households),
        ],
        child: const FoodieHomeApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.c');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Invite code'), 'wrong-code');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Join'));
    await tester.pumpAndSettle();

    expect(find.byType(HouseholdGateScreen), findsOneWidget);
    expect(find.textContaining('invalid invite code'), findsOneWidget);
  });
}
