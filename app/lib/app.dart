import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/household_gate_screen.dart';
import 'features/auth/session.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/home/home_placeholder_screen.dart';

class FoodieHomeApp extends ConsumerWidget {
  const FoodieHomeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return MaterialApp(
      title: 'FoodieHome',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: switch (session) {
        AsyncData(value: final state) => switch (state) {
            SignedOut() => const SignInScreen(),
            NeedsHousehold() => const HouseholdGateScreen(),
            Ready(household: final household) =>
              HomePlaceholderScreen(household: household),
          },
        AsyncError(error: final error) => _StartupErrorScreen('$error'),
        _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
      },
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Something went wrong:\n$message',
              textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
