// PROVISIONAL UI — functional add/edit form; visual polish is not the goal
// of this phase (see the Household Inventory scope note).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/inventory.dart';
import 'inventory_controller.dart';

/// Add mode when [item] is null; edit mode otherwise. [knownLocations]
/// seeds an autocomplete-style suggestion list — any name still works,
/// since unknown locations are created automatically server-side.
class InventoryItemFormScreen extends ConsumerStatefulWidget {
  const InventoryItemFormScreen({
    super.key,
    this.item,
    this.knownLocations = const [],
  });

  final InventoryItem? item;
  final List<InventoryLocation> knownLocations;

  @override
  ConsumerState<InventoryItemFormScreen> createState() =>
      _InventoryItemFormScreenState();
}

class _InventoryItemFormScreenState
    extends ConsumerState<InventoryItemFormScreen> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _location = TextEditingController(
    text: widget.item?.locationName ?? '',
  );
  late final _quantity = TextEditingController(
    text: widget.item?.quantity?.toString() ?? '',
  );
  late final _unit = TextEditingController(text: widget.item?.unit ?? '');
  late final _notes = TextEditingController(text: widget.item?.notes ?? '');
  SupplyLevel? _level;
  DateTime? _expiresOn;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    _level = widget.item?.level;
    _expiresOn = widget.item?.expiresOn;
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _quantity.dispose();
    _unit.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresOn ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _expiresOn = picked);
  }

  Future<void> _submit() async {
    final controller = ref.read(inventoryControllerProvider.notifier);
    double? quantity;
    if (_quantity.text.trim().isNotEmpty) {
      quantity = double.tryParse(_quantity.text.trim());
      if (quantity == null) {
        setState(() => _error = 'Quantity must be a number.');
        return;
      }
      if (quantity < 0) {
        setState(() => _error = 'Quantity cannot be negative.');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        await controller.updateItem(
          widget.item!.id,
          quantity: quantity,
          unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
          level: _level,
          expiresOn: _expiresOn,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        );
      } else {
        if (_name.text.trim().isEmpty) {
          setState(() {
            _busy = false;
            _error = 'Name is required.';
          });
          return;
        }
        await controller.addItem(
          name: _name.text.trim(),
          locationName: _location.text.trim().isEmpty
              ? null
              : _location.text.trim(),
          quantity: quantity,
          unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
          level: _level,
          expiresOn: _expiresOn,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(inventoryControllerProvider.notifier)
          .removeItem(widget.item!.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not remove: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit item' : 'Add item'),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove',
              onPressed: _busy ? null : _remove,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_isEdit)
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true,
            ),
          if (!_isEdit) const SizedBox(height: 12),
          if (!_isEdit)
            Autocomplete<String>(
              optionsBuilder: (value) => widget.knownLocations
                  .map((l) => l.name)
                  .where(
                    (name) => name.toLowerCase().contains(
                      value.text.trim().toLowerCase(),
                    ),
                  ),
              onSelected: (selection) => _location.text = selection,
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                controller.text = _location.text;
                controller.addListener(() => _location.text = controller.text);
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    hintText: 'e.g. Fridge — created automatically if new',
                  ),
                );
              },
            ),
          if (!_isEdit) const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    helperText: 'Leave blank to keep unchanged',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _unit,
                  decoration: const InputDecoration(labelText: 'Unit'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<SupplyLevel?>(
            isExpanded: true,
            initialValue: _level,
            decoration: const InputDecoration(
              labelText: 'Approximate level',
              helperText: 'Use when an exact quantity isn\'t practical',
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('(not set)')),
              ...SupplyLevel.values.map(
                (l) => DropdownMenuItem(value: l, child: Text(l.label)),
              ),
            ],
            onChanged: (value) => setState(() => _level = value),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Expires on'),
            subtitle: Text(
              _expiresOn == null
                  ? 'Not set'
                  : '${_expiresOn!.year}-${_expiresOn!.month.toString().padLeft(2, '0')}-${_expiresOn!.day.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: _pickExpiry,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(
              labelText: 'Notes',
              helperText: 'Leave blank to keep unchanged',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_isEdit ? 'Save changes' : 'Add item'),
          ),
        ],
      ),
    );
  }
}
