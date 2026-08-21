// The Home Dashboard / Kitchen Command Center. Three layouts (kitchen /
// tablet / phone) share the same DashboardSnapshot and the same section
// widgets below — only density and emphasis change, per resolveShellLayout
// (see core/shell_layout.dart), exactly like AppShell's chrome selection.
//
// Every card here reads from a REAL domain controller via
// dashboardControllerProvider (supabase_db-backed, RLS-scoped). There are
// no fabricated placeholder cards: a domain with no data renders a clean
// empty state, never invented content.
//
// Zero AI/model calls happen anywhere in this file or its controller — see
// domain/dashboard.dart's header and docs/DECISIONS.md's AI/cost
// architecture entry.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/kitchen_mode.dart';
import '../../core/shell_layout.dart';
import '../../domain/dashboard.dart';
import '../../domain/fermentation.dart';
import '../auth/session.dart';
import '../fermentation/fermentation_screen.dart';
import '../grocery/grocery_screen.dart';
import '../home_care/home_care_screen.dart';
import '../inventory/inventory_item_form_screen.dart';
import 'dashboard_controller.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kitchenMode = ref.watch(kitchenModeProvider).value ?? false;
    final width = MediaQuery.sizeOf(context).width;
    final layout = resolveShellLayout(width: width, kitchenMode: kitchenMode);
    final session = ref.watch(sessionProvider).value;
    final householdName = session is Ready ? session.household.name : 'Household';
    final dashboard = ref.watch(dashboardControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: switch (dashboard) {
          AsyncData(value: final snapshot) => switch (layout) {
              ShellLayout.kitchen => _KitchenDashboard(householdName: householdName, snapshot: snapshot),
              ShellLayout.tablet => _CompactDashboard(
                  householdName: householdName,
                  snapshot: snapshot,
                  columns: 2,
                ),
              ShellLayout.phone => _CompactDashboard(
                  householdName: householdName,
                  snapshot: snapshot,
                  columns: 1,
                ),
            },
          AsyncError(error: final error) =>
            Center(child: Text('Could not load the dashboard: $error')),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kitchen Device Mode: large touch targets, large readable cards, minimal
// typing, obvious Foodie/grocery/inventory access, attention items front
// and center. No voice, no Cooking Mode — explicitly deferred.
// ---------------------------------------------------------------------------
class _KitchenDashboard extends StatelessWidget {
  const _KitchenDashboard({required this.householdName, required this.snapshot});

  final String householdName;
  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(householdName, style: theme.textTheme.displaySmall),
        const SizedBox(height: 4),
        Text(
          snapshot.isAllClear
              ? 'All caught up.'
              : '${snapshot.attentionCount} thing${snapshot.attentionCount == 1 ? '' : 's'} need attention',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: snapshot.isAllClear ? theme.colorScheme.primary : theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _KitchenBigButton(
                icon: Icons.chat_bubble_outline,
                label: 'Ask Foodie',
                onTap: () => context.go('/foodie'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _KitchenBigButton(
                icon: Icons.shopping_cart_outlined,
                label: 'Groceries',
                badge: snapshot.groceryUncheckedCount,
                onTap: () => context.go('/grocery'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _KitchenBigButton(
                icon: Icons.kitchen_outlined,
                label: 'Inventory',
                onTap: () => context.go('/inventory'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (snapshot.isAllClear)
          const _EmptyStateCard(
            icon: Icons.check_circle_outline,
            title: 'Nothing needs attention',
            message: 'Cleaning, filters, maintenance, and starters are all caught up.',
            large: true,
          )
        else ...[
          for (final task in snapshot.cleaningDueOrOverdue)
            _KitchenAttentionTile(
              icon: Icons.cleaning_services_outlined,
              title: task.name,
              subtitle: task.area == null ? 'Due today' : '${task.area} · Due today',
              onTap: () => context.go('/home-care'),
            ),
          for (final component in snapshot.filtersDueOrOverdue)
            _KitchenAttentionTile(
              icon: Icons.filter_alt_outlined,
              title: '${component.systemName} — ${component.componentName}',
              subtitle: 'Filter due',
              onTap: () => context.go('/supplies'),
            ),
          for (final issue in snapshot.openMaintenanceIssues)
            _KitchenAttentionTile(
              icon: Icons.build_outlined,
              title: issue.title,
              subtitle: issue.area ?? 'Maintenance',
              onTap: () => context.go('/home-care'),
            ),
          for (final status in snapshot.sourdoughFeedStatuses.where((s) => s.overdue))
            _KitchenAttentionTile(
              icon: Icons.bakery_dining_outlined,
              title: status.project.name,
              subtitle: 'Feeding overdue',
              onTap: () => context.go('/fermentation'),
            ),
          for (final item in snapshot.expiredItems)
            _KitchenAttentionTile(
              icon: Icons.error_outline,
              title: item.name,
              subtitle: 'Expired',
              onTap: () => context.go('/inventory'),
            ),
        ],
        const SizedBox(height: 24),
        Text('Fermentation', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        if (snapshot.activeFermentationProjects.isEmpty)
          const _EmptyStateCard(
            icon: Icons.science_outlined,
            title: 'No active fermentation projects',
            message: 'Start a sourdough starter or a cacao batch from the Fermentation tab.',
            large: true,
          )
        else
          for (final project in snapshot.activeFermentationProjects)
            _KitchenAttentionTile(
              icon: project.isSourdough ? Icons.bakery_dining_outlined : Icons.science_outlined,
              title: project.name,
              subtitle: project.currentStage ?? project.status.label,
              onTap: () => context.go('/fermentation'),
            ),
      ],
    );
  }
}

class _KitchenBigButton extends StatelessWidget {
  const _KitchenBigButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 48, color: theme.colorScheme.onPrimaryContainer),
                  if (badge != null && badge! > 0)
                    Positioned(
                      right: -8,
                      top: -8,
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: theme.colorScheme.error,
                        child: Text(
                          '$badge',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onError),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KitchenAttentionTile extends StatelessWidget {
  const _KitchenAttentionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 36, color: theme.colorScheme.error),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleLarge),
                    Text(subtitle, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phone / tablet: compact sections + quick actions. [columns] gives tablet
// a bit more breathing room without changing content.
// ---------------------------------------------------------------------------
class _CompactDashboard extends StatelessWidget {
  const _CompactDashboard({
    required this.householdName,
    required this.snapshot,
    required this.columns,
  });

  final String householdName;
  final DashboardSnapshot snapshot;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = [
      _TodaySection(snapshot: snapshot),
      _FoodSection(snapshot: snapshot),
      _HomeSection(snapshot: snapshot),
      _FermentationSection(snapshot: snapshot),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(householdName, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 4),
        FilledButton.icon(
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Ask Foodie'),
          onPressed: () => context.go('/foodie'),
        ),
        const SizedBox(height: 16),
        const _QuickActions(),
        const SizedBox(height: 16),
        if (columns == 1)
          Column(children: sections)
        else
          GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.4,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: sections,
          ),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionChip(
          avatar: const Icon(Icons.add_shopping_cart_outlined, size: 18),
          label: const Text('Add grocery item'),
          onPressed: () => showAddGroceryItemDialog(context),
        ),
        ActionChip(
          avatar: const Icon(Icons.add_box_outlined, size: 18),
          label: const Text('Add inventory item'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const InventoryItemFormScreen(),
          )),
        ),
        ActionChip(
          avatar: const Icon(Icons.bakery_dining_outlined, size: 18),
          label: const Text('Start fermentation'),
          onPressed: () => showNewFermentationProjectDialog(context),
        ),
        ActionChip(
          avatar: const Icon(Icons.report_problem_outlined, size: 18),
          label: const Text('Report maintenance issue'),
          onPressed: () => showReportMaintenanceIssueDialog(context),
        ),
      ],
    );
  }
}

class _TodaySection extends StatelessWidget {
  const _TodaySection({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <String>[
      if (snapshot.cleaningDueOrOverdue.isNotEmpty)
        '${snapshot.cleaningDueOrOverdue.length} cleaning task${snapshot.cleaningDueOrOverdue.length == 1 ? '' : 's'} due',
      if (snapshot.filtersDueOrOverdue.isNotEmpty)
        '${snapshot.filtersDueOrOverdue.length} filter${snapshot.filtersDueOrOverdue.length == 1 ? '' : 's'} due soon',
      if (snapshot.openMaintenanceIssues.isNotEmpty)
        '${snapshot.openMaintenanceIssues.length} open maintenance issue${snapshot.openMaintenanceIssues.length == 1 ? '' : 's'}',
      if (snapshot.expiredItems.isNotEmpty)
        '${snapshot.expiredItems.length} expired item${snapshot.expiredItems.length == 1 ? '' : 's'}',
      for (final status in snapshot.sourdoughFeedStatuses.where((s) => s.overdue))
        '${status.project.name} needs feeding',
    ];

    return _SectionCard(
      title: 'Today',
      icon: Icons.today_outlined,
      child: items.isEmpty
          ? Row(
              children: [
                Icon(Icons.check_circle_outline, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text('All caught up'),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: items.map((text) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $text'),
                  )).toList(),
            ),
    );
  }
}

class _FoodSection extends StatelessWidget {
  const _FoodSection({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Food',
      icon: Icons.kitchen_outlined,
      onTap: () => context.go('/inventory'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            snapshot.groceryUncheckedCount == 0
                ? 'Grocery list is clear'
                : '${snapshot.groceryUncheckedCount} item${snapshot.groceryUncheckedCount == 1 ? '' : 's'} on the grocery list',
          ),
          const SizedBox(height: 4),
          if (snapshot.expiredItems.isEmpty && snapshot.expiringSoonItems.isEmpty)
            const Text('Nothing expiring soon')
          else ...[
            for (final item in snapshot.expiredItems.take(3))
              Text('${item.name} — expired', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            for (final item in snapshot.expiringSoonItems.take(3)) Text('${item.name} — expiring soon'),
          ],
        ],
      ),
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final hasContent = snapshot.cleaningDueOrOverdue.isNotEmpty ||
        snapshot.filtersDueOrOverdue.isNotEmpty ||
        snapshot.openMaintenanceIssues.isNotEmpty;

    return _SectionCard(
      title: 'Home',
      icon: Icons.home_outlined,
      onTap: () => context.go('/home-care'),
      child: !hasContent
          ? const Text('Nothing due — cleaning, filters, and maintenance are all caught up')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final task in snapshot.cleaningDueOrOverdue.take(3)) Text('${task.name} — due'),
                for (final component in snapshot.filtersDueOrOverdue.take(3))
                  Text('${component.componentName} — due'),
                for (final issue in snapshot.openMaintenanceIssues.take(3)) Text('${issue.title} — open'),
              ],
            ),
    );
  }
}

class _FermentationSection extends StatelessWidget {
  const _FermentationSection({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Fermentation',
      icon: Icons.science_outlined,
      onTap: () => context.go('/fermentation'),
      child: snapshot.activeFermentationProjects.isEmpty
          ? const Text('No active fermentation projects')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final project in snapshot.activeFermentationProjects.take(4))
                  Text('${project.name} — ${project.currentStage ?? project.status.label}'),
                for (final status in snapshot.sourdoughFeedStatuses.where((s) => s.overdue))
                  Text(
                    '${status.project.name} — feeding overdue',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
              ],
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(title, style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.large = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: EdgeInsets.all(large ? 32 : 16),
        child: Column(
          children: [
            Icon(icon, size: large ? 48 : 32, color: theme.colorScheme.outline),
            const SizedBox(height: 8),
            Text(title, style: large ? theme.textTheme.titleLarge : theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
