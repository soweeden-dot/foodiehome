// LOCAL PREVIEW ENTRYPOINT — not the production app. Boots FoodieHomeApp
// against in-memory sample gateways (lib/dev/demo_gateways.dart) instead of
// Supabase, so the Home Dashboard can be reviewed in a browser without a
// live backend connection.
//
// Why this exists: the live-infrastructure freeze forbids any real Supabase
// interaction this phase, and this sandbox cannot reach the real project
// even if the freeze were lifted (confirmed during Stream 3's smoke-test
// attempt). Real credentials for the shared project also aren't held here.
// Rather than fail to deliver anything reviewable, this preview reuses the
// exact same widget tree as production — only the data source differs.
//
// Run with: flutter run -d web-server --web-port=8080 -t lib/main_demo.dart
// Production always boots through main.dart against the real
// Supabase-backed gateways — this file is never used there.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'dev/demo_gateways.dart';
import 'features/auth/session.dart';
import 'features/fermentation/fermentation_controller.dart';
import 'features/foodie/chat_controller.dart';
import 'features/grocery/grocery_controller.dart';
import 'features/home_care/home_care_controller.dart';
import 'features/inventory/inventory_controller.dart';

void main() {
  runApp(
    ProviderScope(
      overrides: [
        authGatewayProvider.overrideWithValue(DemoAuthGateway()),
        householdGatewayProvider.overrideWithValue(DemoHouseholdGateway()),
        groceryGatewayProvider.overrideWithValue(DemoGroceryGateway()),
        inventoryGatewayProvider.overrideWithValue(DemoInventoryGateway()),
        homeCareGatewayProvider.overrideWithValue(DemoHomeCareGateway()),
        fermentationGatewayProvider.overrideWithValue(DemoFermentationGateway()),
        foodieGatewayProvider.overrideWithValue(DemoFoodieGateway()),
      ],
      child: const FoodieHomeApp(),
    ),
  );
}
