import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/grocery.dart';
import 'grocery_gateway.dart';

class SupabaseGroceryGateway implements GroceryGateway {
  SupabaseGroceryGateway(this._client);

  final SupabaseClient _client;

  static GroceryItem _itemFromRow(Map<String, dynamic> row) => GroceryItem(
        id: row['id'] as String,
        name: (row['name'] as String?) ?? '(unnamed)',
        quantity: (row['quantity'] as num?)?.toDouble(),
        unit: row['unit'] as String?,
        checked: row['checked_at'] != null,
        notes: row['notes'] as String?,
      );

  @override
  Future<GroceryListSnapshot> fetchGroceryList(String householdId) async {
    final lists = await _client
        .from('grocery_lists')
        .select('id, name')
        .eq('household_id', householdId)
        .isFilter('archived_at', null)
        .isFilter('deleted_at', null)
        .order('created_at')
        .limit(1);
    if (lists.isEmpty) return GroceryListSnapshot.empty;

    final listId = lists.first['id'] as String;
    final listName = lists.first['name'] as String;
    final items = await _client
        .from('grocery_items')
        .select('id, name, quantity, unit, checked_at, notes')
        .eq('grocery_list_id', listId)
        .isFilter('deleted_at', null)
        .order('created_at');

    return GroceryListSnapshot(
      listId: listId,
      listName: listName,
      items: items.map(_itemFromRow).toList(),
    );
  }

  @override
  Future<GroceryItem> addItem(
    String householdId, {
    required String name,
    double? quantity,
    String? unit,
    String? notes,
  }) async {
    final result = await _client.rpc<dynamic>(
      'foodie_add_grocery_item',
      params: {
        'p_household': householdId,
        'p_name': name.trim(),
        'p_quantity': quantity,
        'p_unit': unit,
        'p_notes': notes,
      },
    );
    return _itemFromRow(result as Map<String, dynamic>);
  }
}
