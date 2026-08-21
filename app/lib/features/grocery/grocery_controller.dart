import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../data/grocery_gateway.dart';
import '../../data/supabase_grocery_gateway.dart';
import '../../domain/grocery.dart';
import '../auth/session.dart';

final groceryGatewayProvider = Provider<GroceryGateway>(
  (ref) => SupabaseGroceryGateway(Supabase.instance.client),
);

/// Current household's grocery list. Same refetch-on-mutation pattern as
/// every other domain controller in this codebase.
class GroceryController extends AsyncNotifier<GroceryListSnapshot> {
  @override
  Future<GroceryListSnapshot> build() async {
    final session = await ref.watch(sessionProvider.future);
    if (session is! Ready) return GroceryListSnapshot.empty;
    return ref.watch(groceryGatewayProvider).fetchGroceryList(session.household.id);
  }

  Future<void> addItem({
    required String name,
    double? quantity,
    String? unit,
    String? notes,
  }) async {
    final session = await ref.read(sessionProvider.future);
    if (session is! Ready) {
      throw StateError('cannot manage groceries without an active household');
    }
    await ref.read(groceryGatewayProvider).addItem(
          session.household.id,
          name: name,
          quantity: quantity,
          unit: unit,
          notes: notes,
        );
    ref.invalidateSelf();
    await future;
  }
}

final groceryControllerProvider =
    AsyncNotifierProvider<GroceryController, GroceryListSnapshot>(GroceryController.new);
