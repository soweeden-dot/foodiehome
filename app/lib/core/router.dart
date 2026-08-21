// Production navigation. Route boundaries exist for every future feature
// area; bodies are placeholders until their stream lands.
//
// Auth protection: a single redirect keyed off the Stream 2 session state.
// Every shell route requires Ready (signed in + household). Kitchen Device
// Mode has no influence here — it selects chrome, never access.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/household_gate_screen.dart';
import '../features/auth/session.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/fermentation/fermentation_screen.dart';
import '../features/foodie/chat_screen.dart';
import '../features/grocery/grocery_screen.dart';
import '../features/home_care/filters_screen.dart';
import '../features/home_care/home_care_screen.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/destinations.dart';
import '../features/shell/placeholder_screen.dart';

const _authRoutes = {'/splash', '/signin', '/setup'};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final path = state.uri.path;
      final onAuthRoute = _authRoutes.contains(path);

      if (session.isLoading) return onAuthRoute ? null : '/splash';
      return switch (session.value) {
        SignedOut() || null => path == '/signin' ? null : '/signin',
        NeedsHousehold() => path == '/setup' ? null : '/setup',
        Ready() => onAuthRoute ? '/home' : null,
      };
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      GoRoute(path: '/signin', builder: (context, state) => const SignInScreen()),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const HouseholdGateScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        // One branch per AppDestination, in list order — the shell relies on
        // branch index == appDestinations index.
        branches: [
          for (final destination in appDestinations)
            StatefulShellBranch(routes: [
              GoRoute(
                path: destination.route,
                builder: (context, state) => _destinationBody(destination),
              ),
            ]),
        ],
      ),
    ],
  );
});

Widget _destinationBody(AppDestination destination) => switch (destination.route) {
      '/home' => const DashboardScreen(),
      '/foodie' => const FoodieChatScreen(),
      '/grocery' => const GroceryScreen(),
      '/inventory' => const InventoryScreen(),
      '/home-care' => const HomeCareScreen(),
      '/supplies' => const FiltersScreen(),
      '/fermentation' => const FermentationScreen(),
      '/settings' => const SettingsScreen(),
      _ => PlaceholderScreen(title: destination.label, icon: destination.icon),
    };
