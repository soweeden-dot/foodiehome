import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/inventory.dart';
import 'inventory_gateway.dart';

class SupabaseInventoryGateway implements InventoryGateway {
  SupabaseInventoryGateway(this._client);

  final SupabaseClient _client;

  static DateTime? _parseDate(dynamic value) =>
      value == null ? null : DateTime.parse(value as String);

  static String? _formatDate(DateTime? date) =>
      date?.toIso8601String().split('T').first;

  static InventoryLocation _locationFromRow(Map<String, dynamic> row) =>
      InventoryLocation(
        id: row['id'] as String,
        name: row['name'] as String,
        kind: row['kind'] as String,
      );

  static InventoryItem _itemFromRow(Map<String, dynamic> row) {
    final location = row['inventory_locations'] as Map<String, dynamic>?;
    return InventoryItem(
      id: row['id'] as String,
      name: (row['name'] as String?) ?? '(unnamed)',
      locationName: location?['name'] as String?,
      quantity: (row['quantity'] as num?)?.toDouble(),
      unit: row['unit'] as String?,
      level: SupplyLevelWire.fromWire(row['level'] as String?),
      expiresOn: _parseDate(row['expires_on']),
      openedOn: _parseDate(row['opened_on']),
      notes: row['notes'] as String?,
    );
  }

  /// The mutating RPCs return the raw row (a location id, not a joined
  /// name); a second small lookup resolves it for display, mirroring the
  /// Edge Function's SupabaseFoodieDb.
  Future<InventoryItem> _itemFromRpcResult(Map<String, dynamic> row) async {
    final locationId = row['location_id'] as String?;
    String? locationName;
    if (locationId != null) {
      final location = await _client
          .from('inventory_locations')
          .select('name')
          .eq('id', locationId)
          .maybeSingle();
      locationName = location?['name'] as String?;
    }
    return InventoryItem(
      id: row['id'] as String,
      name: (row['name'] as String?) ?? '(unnamed)',
      locationName: locationName,
      quantity: (row['quantity'] as num?)?.toDouble(),
      unit: row['unit'] as String?,
      level: SupplyLevelWire.fromWire(row['level'] as String?),
      expiresOn: _parseDate(row['expires_on']),
      openedOn: _parseDate(row['opened_on']),
      notes: row['notes'] as String?,
    );
  }

  @override
  Future<InventorySnapshot> fetchInventory(String householdId) async {
    final locationsFuture = _client
        .from('inventory_locations')
        .select('id, name, kind')
        .eq('household_id', householdId)
        .isFilter('deleted_at', null)
        .order('position');
    final itemsFuture = _client
        .from('inventory_items')
        .select(
            'id, name, quantity, unit, level, expires_on, opened_on, notes, inventory_locations(name)')
        .eq('household_id', householdId)
        .isFilter('deleted_at', null)
        .order('created_at');

    final results = await Future.wait([locationsFuture, itemsFuture]);
    final locationRows = results[0];
    final itemRows = results[1];

    return InventorySnapshot(
      locations: locationRows.map(_locationFromRow).toList(),
      items: itemRows.map(_itemFromRow).toList(),
    );
  }

  @override
  Future<InventoryItem> addItem(
    String householdId, {
    required String name,
    String? locationName,
    double? quantity,
    String? unit,
    SupplyLevel? level,
    DateTime? expiresOn,
    String? notes,
  }) async {
    final result = await _client.rpc<dynamic>(
      'foodie_add_inventory_item',
      params: {
        'p_household': householdId,
        'p_name': name.trim(),
        'p_location_name': locationName,
        'p_quantity': quantity,
        'p_unit': unit,
        'p_level': level?.toWire(),
        'p_expires_on': _formatDate(expiresOn),
        'p_notes': notes,
      },
    );
    return _itemFromRpcResult(result as Map<String, dynamic>);
  }

  @override
  Future<InventoryItem> updateItem(
    String householdId,
    String itemId, {
    double? quantity,
    String? unit,
    SupplyLevel? level,
    DateTime? expiresOn,
    DateTime? openedOn,
    String? notes,
  }) async {
    final result = await _client.rpc<dynamic>(
      'foodie_update_inventory_item',
      params: {
        'p_household': householdId,
        'p_item_id': itemId,
        'p_quantity': quantity,
        'p_unit': unit,
        'p_level': level?.toWire(),
        'p_expires_on': _formatDate(expiresOn),
        'p_opened_on': _formatDate(openedOn),
        'p_notes': notes,
      },
    );
    return _itemFromRpcResult(result as Map<String, dynamic>);
  }

  @override
  Future<void> removeItem(String householdId, String itemId) async {
    await _client.rpc<dynamic>(
      'foodie_remove_inventory_item',
      params: {'p_household': householdId, 'p_item_id': itemId},
    );
  }
}
