/// Domain models for household inventory. Plain immutable Dart, independent
/// of the Supabase row shape (mapping happens in the data layer) — mirrors
/// the pattern established for Household in domain/household.dart.
library;

/// Mirrors the `foodie.supply_level` enum: an approximate stock level, used
/// when a precise quantity isn't practical to track.
enum SupplyLevel { full, good, low, almostEmpty, out }

extension SupplyLevelWire on SupplyLevel {
  static SupplyLevel? fromWire(String? value) => switch (value) {
        'full' => SupplyLevel.full,
        'good' => SupplyLevel.good,
        'low' => SupplyLevel.low,
        'almost_empty' => SupplyLevel.almostEmpty,
        'out' => SupplyLevel.out,
        _ => null,
      };

  String toWire() => switch (this) {
        SupplyLevel.full => 'full',
        SupplyLevel.good => 'good',
        SupplyLevel.low => 'low',
        SupplyLevel.almostEmpty => 'almost_empty',
        SupplyLevel.out => 'out',
      };

  String get label => switch (this) {
        SupplyLevel.full => 'Full',
        SupplyLevel.good => 'Good',
        SupplyLevel.low => 'Low',
        SupplyLevel.almostEmpty => 'Almost empty',
        SupplyLevel.out => 'Out',
      };
}

class InventoryLocation {
  const InventoryLocation({
    required this.id,
    required this.name,
    required this.kind,
  });

  final String id;
  final String name;
  final String kind;

  @override
  bool operator ==(Object other) =>
      other is InventoryLocation &&
      other.id == id &&
      other.name == name &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(id, name, kind);
}

/// An item of stock on hand. Either [quantity]/[unit] or [level] describes
/// how much there is — both are optional, matching the schema's design that
/// "we have some rice" is valid household data even without a precise count.
class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    this.locationName,
    this.quantity,
    this.unit,
    this.level,
    this.expiresOn,
    this.openedOn,
    this.notes,
  });

  final String id;
  final String name;
  final String? locationName;
  final double? quantity;
  final String? unit;
  final SupplyLevel? level;
  final DateTime? expiresOn;
  final DateTime? openedOn;
  final String? notes;

  /// True when [expiresOn] is today or in the past.
  bool isExpired({DateTime? asOf}) {
    if (expiresOn == null) return false;
    final today = _dateOnly(asOf ?? DateTime.now());
    return !expiresOn!.isAfter(today) || expiresOn!.isAtSameMomentAs(today);
  }

  /// True when [expiresOn] falls within the next [withinDays] days
  /// (inclusive), but hasn't already expired.
  bool isExpiringSoon({int withinDays = 3, DateTime? asOf}) {
    if (expiresOn == null || isExpired(asOf: asOf)) return false;
    final today = _dateOnly(asOf ?? DateTime.now());
    final horizon = today.add(Duration(days: withinDays));
    return !expiresOn!.isAfter(horizon);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  InventoryItem copyWith({
    double? quantity,
    bool clearQuantity = false,
    String? unit,
    bool clearUnit = false,
    SupplyLevel? level,
    bool clearLevel = false,
    DateTime? expiresOn,
    bool clearExpiresOn = false,
    DateTime? openedOn,
    bool clearOpenedOn = false,
    String? notes,
    bool clearNotes = false,
  }) =>
      InventoryItem(
        id: id,
        name: name,
        locationName: locationName,
        quantity: clearQuantity ? null : (quantity ?? this.quantity),
        unit: clearUnit ? null : (unit ?? this.unit),
        level: clearLevel ? null : (level ?? this.level),
        expiresOn: clearExpiresOn ? null : (expiresOn ?? this.expiresOn),
        openedOn: clearOpenedOn ? null : (openedOn ?? this.openedOn),
        notes: clearNotes ? null : (notes ?? this.notes),
      );

  @override
  bool operator ==(Object other) =>
      other is InventoryItem &&
      other.id == id &&
      other.name == name &&
      other.locationName == locationName &&
      other.quantity == quantity &&
      other.unit == unit &&
      other.level == level &&
      other.expiresOn == expiresOn &&
      other.openedOn == openedOn &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        locationName,
        quantity,
        unit,
        level,
        expiresOn,
        openedOn,
        notes,
      );
}

/// Everything the Inventory screen needs for one household, fetched
/// together — mirrors the Edge Function's InventoryView shape.
class InventorySnapshot {
  const InventorySnapshot({required this.locations, required this.items});

  final List<InventoryLocation> locations;
  final List<InventoryItem> items;

  static const empty = InventorySnapshot(locations: [], items: []);
}

