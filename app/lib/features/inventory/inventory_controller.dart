import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../data/inventory_gateway.dart';
import '../../data/supabase_inventory_gateway.dart';
import '../../domain/inventory.dart';
import '../auth/session.dart';

final inventoryGatewayProvider = Provider<InventoryGateway>(
  (ref) => SupabaseInventoryGateway(Supabase.instance.client),
);

/// Current household's inventory. Depends on [sessionProvider] for the
/// household id — refetches whenever the session changes (e.g. household
/// switch), and after every mutation (simple, correct; optimistic updates
/// aren't worth the complexity for a two-person household).
class InventoryController extends AsyncNotifier<InventorySnapshot> {
  @override
  Future<InventorySnapshot> build() async {
    final session = await ref.watch(sessionProvider.future);
    if (session is! Ready) return InventorySnapshot.empty;
    return ref.watch(inventoryGatewayProvider).fetchInventory(session.household.id);
  }

  Future<String> _householdId() async {
    final session = await ref.read(sessionProvider.future);
    if (session is! Ready) {
      throw StateError('cannot manage inventory without an active household');
    }
    return session.household.id;
  }

  Future<void> addItem({
    required String name,
    String? locationName,
    double? quantity,
    String? unit,
    SupplyLevel? level,
    DateTime? expiresOn,
    String? notes,
  }) async {
    final householdId = await _householdId();
    await ref.read(inventoryGatewayProvider).addItem(
          householdId,
          name: name,
          locationName: locationName,
          quantity: quantity,
          unit: unit,
          level: level,
          expiresOn: expiresOn,
          notes: notes,
        );
    ref.invalidateSelf();
    await future;
  }

  Future<void> updateItem(
    String itemId, {
    double? quantity,
    String? unit,
    SupplyLevel? level,
    DateTime? expiresOn,
    DateTime? openedOn,
    String? notes,
  }) async {
    final householdId = await _householdId();
    await ref.read(inventoryGatewayProvider).updateItem(
          householdId,
          itemId,
          quantity: quantity,
          unit: unit,
          level: level,
          expiresOn: expiresOn,
          openedOn: openedOn,
          notes: notes,
        );
    ref.invalidateSelf();
    await future;
  }

  Future<void> removeItem(String itemId) async {
    final householdId = await _householdId();
    await ref.read(inventoryGatewayProvider).removeItem(householdId, itemId);
    ref.invalidateSelf();
    await future;
  }
}

final inventoryControllerProvider =
    AsyncNotifierProvider<InventoryController, InventorySnapshot>(
        InventoryController.new);

/// Client-side search/filter state — no network call, applied to the
/// already-fetched snapshot.
class InventoryFilter {
  const InventoryFilter({this.query = '', this.locationName});

  final String query;

  /// null = all locations.
  final String? locationName;

  InventoryFilter copyWith({String? query, String? locationName, bool clearLocation = false}) =>
      InventoryFilter(
        query: query ?? this.query,
        locationName: clearLocation ? null : (locationName ?? this.locationName),
      );
}

class InventoryFilterController extends Notifier<InventoryFilter> {
  @override
  InventoryFilter build() => const InventoryFilter();

  void setQuery(String query) => state = state.copyWith(query: query);

  void setLocation(String? locationName) => state = locationName == null
      ? state.copyWith(clearLocation: true)
      : state.copyWith(locationName: locationName);
}

final inventoryFilterProvider =
    NotifierProvider<InventoryFilterController, InventoryFilter>(
        InventoryFilterController.new);

List<InventoryItem> applyInventoryFilter(
  List<InventoryItem> items,
  InventoryFilter filter,
) {
  final query = filter.query.trim().toLowerCase();
  return items.where((item) {
    if (filter.locationName != null && item.locationName != filter.locationName) {
      return false;
    }
    if (query.isEmpty) return true;
    return item.name.toLowerCase().contains(query) ||
        (item.notes?.toLowerCase().contains(query) ?? false);
  }).toList();
}
