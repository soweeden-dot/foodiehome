// PROVISIONAL UI — minimal, functional grocery list: view + add only.
// Checking/unchecking an item has no write path yet (no RPC exists for it
// this phase — see GroceryGateway's header note); items already checked
// (e.g. by Foodie or a future write path) still display as such.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/grocery.dart';
import 'grocery_controller.dart';

class GroceryScreen extends ConsumerWidget {
  const GroceryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(groceryControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Groceries')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add item',
        onPressed: () => showAddGroceryItemDialog(context),
        child: const Icon(Icons.add),
      ),
      body: switch (list) {
        AsyncData(value: final snapshot) => snapshot.items.isEmpty
            ? const _EmptyState()
            : ListView.builder(
                itemCount: snapshot.items.length,
                itemBuilder: (context, index) => _ItemTile(item: snapshot.items[index]),
              ),
        AsyncError(error: final error) => Center(child: Text('Could not load groceries: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final GroceryItem item;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (item.quantity != null) '${item.quantity}${item.unit != null ? ' ${item.unit}' : ''}',
      if (item.notes != null) item.notes!,
    ];
    return ListTile(
      leading: Icon(item.checked ? Icons.check_circle : Icons.circle_outlined),
      title: Text(
        item.name,
        style: item.checked ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
      ),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('No grocery items yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Tap + to add something the household needs.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable "add grocery item" dialog — the grocery screen's FAB and the
/// dashboard's "Add grocery item" quick action both open this.
Future<void> showAddGroceryItemDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _AddGroceryItemDialog());
}

class _AddGroceryItemDialog extends ConsumerStatefulWidget {
  const _AddGroceryItemDialog();

  @override
  ConsumerState<_AddGroceryItemDialog> createState() => _AddGroceryItemDialogState();
}

class _AddGroceryItemDialogState extends ConsumerState<_AddGroceryItemDialog> {
  final _name = TextEditingController();
  final _quantity = TextEditingController();
  final _unit = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _unit.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    double? quantity;
    if (_quantity.text.trim().isNotEmpty) {
      quantity = double.tryParse(_quantity.text.trim());
      if (quantity == null) {
        setState(() => _error = 'Quantity must be a number.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(groceryControllerProvider.notifier).addItem(
            name: _name.text.trim(),
            quantity: quantity,
            unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add grocery item'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantity,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Quantity (optional)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _unit,
                  decoration: const InputDecoration(labelText: 'Unit (optional)'),
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
