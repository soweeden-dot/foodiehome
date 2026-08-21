import '../domain/inventory.dart';

/// Data access for household inventory. Backed by Supabase (RLS scopes every
/// query to the caller's household; mutations go through the foodie_*
/// SQL functions from migration 14 — same trust model as HouseholdGateway).
///
/// [updateItem]'s optional parameters follow the same "omitted = leave
/// unchanged" rule as the underlying foodie_update_inventory_item RPC: this
/// call cannot explicitly clear a previously-set field back to empty in this
/// phase (see docs/FOODIE.md). The edit screen's optional fields are
/// captioned accordingly rather than offering a "clear" control that
/// wouldn't actually work.
abstract interface class InventoryGateway {
  Future<InventorySnapshot> fetchInventory(String householdId);

  /// [locationName] is created automatically if it doesn't already exist —
  /// households aren't required to pre-provision Pantry/Fridge/Freezer.
  Future<InventoryItem> addItem(
    String householdId, {
    required String name,
    String? locationName,
    double? quantity,
    String? unit,
    SupplyLevel? level,
    DateTime? expiresOn,
    String? notes,
  });

  Future<InventoryItem> updateItem(
    String householdId,
    String itemId, {
    double? quantity,
    String? unit,
    SupplyLevel? level,
    DateTime? expiresOn,
    DateTime? openedOn,
    String? notes,
  });

  /// Soft-deletes the item (existing schema convention — deleted_at, not a
  /// hard delete).
  Future<void> removeItem(String householdId, String itemId);
}
