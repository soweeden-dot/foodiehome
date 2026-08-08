// PROVISIONAL UI — create a household or join one with an invite code.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session.dart';

class HouseholdGateScreen extends ConsumerStatefulWidget {
  const HouseholdGateScreen({super.key});

  @override
  ConsumerState<HouseholdGateScreen> createState() =>
      _HouseholdGateScreenState();
}

class _HouseholdGateScreenState extends ConsumerState<HouseholdGateScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = ref.read(sessionActionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your household'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _busy ? null : () => _run(actions.signOut),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text('Create a household',
                  style: Theme.of(context).textTheme.titleMedium),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Household name'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed:
                    _busy ? null : () => _run(() => actions.createHousehold(_name.text)),
                child: const Text('Create'),
              ),
              const SizedBox(height: 32),
              Text('Or join with an invite code',
                  style: Theme.of(context).textTheme.titleMedium),
              TextField(
                controller: _code,
                decoration: const InputDecoration(labelText: 'Invite code'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed:
                    _busy ? null : () => _run(() => actions.joinHousehold(_code.text)),
                child: const Text('Join'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
