// PROVISIONAL UI — functional inventory list; visual polish and Dashboard
// integration are later phases.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/inventory.dart';
import 'inventory_controller.dart';
import 'inventory_item_form_screen.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventory = ref.watch(inventoryControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add item',
        onPressed: () {
          final locations = inventory.value?.locations ?? const [];
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => InventoryItemFormScreen(knownLocations: locations),
          ));
        },
        child: const Icon(Icons.add),
      ),
      body: switch (inventory) {
        AsyncData(value: final snapshot) => _InventoryBody(snapshot: snapshot),
        AsyncError(error: final error) => Center(child: Text('Could not load inventory: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _InventoryBody extends ConsumerWidget {
  const _InventoryBody({required this.snapshot});

  final InventorySnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(inventoryFilterProvider);
    final filterController = ref.read(inventoryFilterProvider.notifier);
    final filtered = applyInventoryFilter(snapshot.items, filter);

    if (snapshot.items.isEmpty) {
      return const _EmptyState(
        icon: Icons.kitchen_outlined,
        title: 'No inventory yet',
        message: 'Tap + to add what\'s in your pantry, fridge, or freezer.',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search inventory…',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: filterController.setQuery,
          ),
        ),
        if (snapshot.locations.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: filter.locationName == null,
                    onSelected: (_) => filterController.setLocation(null),
                  ),
                ),
                for (final location in snapshot.locations)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(location.name),
                      selected: filter.locationName == location.name,
                      onSelected: (_) => filterController.setLocation(location.name),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: filtered.isEmpty
              ? const _EmptyState(
                  icon: Icons.search_off,
                  title: 'No matches',
                  message: 'Nothing in inventory matches this search/filter.',
                )
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => _InventoryTile(
                    item: filtered[index],
                    knownLocations: snapshot.locations,
                  ),
                ),
        ),
      ],
    );
  }
}

class _InventoryTile extends StatelessWidget {
  const _InventoryTile({required this.item, required this.knownLocations});

  final InventoryItem item;
  final List<InventoryLocation> knownLocations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expired = item.isExpired();
    final expiringSoon = item.isExpiringSoon();

    final subtitleParts = <String>[
      if (item.locationName != null) item.locationName!,
      if (item.quantity != null) '${item.quantity}${item.unit != null ? ' ${item.unit}' : ''}',
      if (item.quantity == null && item.level != null) item.level!.label,
    ];

    return ListTile(
      title: Text(item.name),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
      trailing: expired
          ? Icon(Icons.error_outline, color: theme.colorScheme.error)
          : expiringSoon
              ? Icon(Icons.schedule, color: theme.colorScheme.tertiary)
              : null,
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            InventoryItemFormScreen(item: item, knownLocations: knownLocations),
      )),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
