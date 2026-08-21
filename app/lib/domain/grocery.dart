/// Minimal grocery domain — just enough for the Home Dashboard's "Food"
/// section and its "Add grocery item" quick action. Mirrors the Edge
/// Function's GroceryItemView/GroceryListView shapes (see
/// supabase/functions/_shared/types.ts), with the item id Foodie's chat
/// tools don't need but the UI does (there's no toggle-checked write path
/// yet — see the gateway for why).
library;

class GroceryItem {
  const GroceryItem({
    required this.id,
    required this.name,
    this.quantity,
    this.unit,
    this.checked = false,
    this.notes,
  });

  final String id;
  final String name;
  final double? quantity;
  final String? unit;
  final bool checked;
  final String? notes;

  @override
  bool operator ==(Object other) =>
      other is GroceryItem &&
      other.id == id &&
      other.name == name &&
      other.quantity == quantity &&
      other.unit == unit &&
      other.checked == checked &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(id, name, quantity, unit, checked, notes);
}

class GroceryListSnapshot {
  const GroceryListSnapshot({
    required this.listId,
    required this.listName,
    required this.items,
  });

  final String listId;
  final String listName;
  final List<GroceryItem> items;

  int get uncheckedCount => items.where((i) => !i.checked).length;

  static const empty = GroceryListSnapshot(listId: '', listName: 'Groceries', items: []);
}
