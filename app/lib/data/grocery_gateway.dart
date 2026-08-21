import '../domain/grocery.dart';

/// Data access for the household grocery list. Backed by Supabase (RLS
/// scopes every query to the caller's household). Read is a direct RLS
/// select (mirrors the Edge Function's SupabaseFoodieDb.getGroceryList);
/// [addItem] goes through the existing `foodie_add_grocery_item` RPC
/// (migration 13 — no new migration needed for the Dashboard phase).
///
/// Deliberately narrow: checking/unchecking an item has no write path yet
/// (no RPC exists for it) — this phase only needs read + add for the
/// dashboard's "Food" section and "Add grocery item" quick action.
abstract interface class GroceryGateway {
  Future<GroceryListSnapshot> fetchGroceryList(String householdId);

  Future<GroceryItem> addItem(
    String householdId, {
    required String name,
    double? quantity,
    String? unit,
    String? notes,
  });
}
