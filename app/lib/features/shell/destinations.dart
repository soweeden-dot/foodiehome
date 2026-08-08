import 'package:flutter/material.dart';

/// The app's section map — one entry per future feature area. Routes exist
/// today; most bodies are placeholders until their stream lands. Navigation
/// chrome filters this list per layout, so adding a section later is one
/// entry here plus a branch in the router.
class AppDestination {
  const AppDestination({
    required this.route,
    required this.label,
    required this.icon,
    this.primaryOnPhone = false,
    this.showInKitchen = false,
  });

  final String route;
  final String label;
  final IconData icon;

  /// Shown directly in the phone bottom bar (everything else is under More).
  final bool primaryOnPhone;

  /// Shown in the simplified Kitchen Mode shell.
  final bool showInKitchen;
}

const appDestinations = <AppDestination>[
  AppDestination(
    route: '/home',
    label: 'Home',
    icon: Icons.home_outlined,
    primaryOnPhone: true,
    showInKitchen: true,
  ),
  AppDestination(
    route: '/grocery',
    label: 'Grocery',
    icon: Icons.shopping_cart_outlined,
    primaryOnPhone: true,
    showInKitchen: true,
  ),
  AppDestination(
    route: '/foodie',
    label: 'Foodie',
    icon: Icons.chat_bubble_outline,
    primaryOnPhone: true,
    showInKitchen: true,
  ),
  AppDestination(route: '/inventory', label: 'Inventory', icon: Icons.kitchen_outlined),
  AppDestination(route: '/recipes', label: 'Recipes', icon: Icons.menu_book_outlined),
  AppDestination(route: '/meal-plan', label: 'Meal Plan', icon: Icons.calendar_month_outlined),
  AppDestination(route: '/fermentation', label: 'Fermentation', icon: Icons.science_outlined),
  AppDestination(route: '/home-care', label: 'Home Care', icon: Icons.cleaning_services_outlined),
  AppDestination(route: '/supplies', label: 'Filters & Supplies', icon: Icons.filter_alt_outlined),
  AppDestination(route: '/settings', label: 'Settings', icon: Icons.settings_outlined),
];

List<AppDestination> phonePrimaryDestinations() =>
    appDestinations.where((d) => d.primaryOnPhone).toList();

List<AppDestination> phoneOverflowDestinations() =>
    appDestinations.where((d) => !d.primaryOnPhone).toList();

/// Kitchen Mode intentionally omits Settings and management sections
/// ("reduced access to account/admin surfaces"); a small gear affordance in
/// the kitchen shell still reaches Settings so the mode can be turned off.
List<AppDestination> kitchenDestinations() =>
    appDestinations.where((d) => d.showInKitchen).toList();
