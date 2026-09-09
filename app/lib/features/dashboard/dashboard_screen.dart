// The Home Dashboard / Kitchen Command Center. Three layouts (kitchen /
// tablet / phone) share the same DashboardSnapshot and the same section
// widgets below — only density and emphasis change, per resolveShellLayout
// (see core/shell_layout.dart), exactly like AppShell's chrome selection.
//
// Kitchen and Personal-iPad (tablet) visuals follow the warm/ivory palette
// approved via the visual mockup review (docs/DECISIONS.md references that
// round) — see _Palette below. Phone keeps the app's default Material theme;
// it wasn't part of that review.
//
// Every card here reads from a REAL domain controller via
// dashboardControllerProvider (supabase_db-backed, RLS-scoped). There are
// no fabricated placeholder cards: a domain with no data renders a clean
// empty state, never invented content. Cook/Recipes routes to the existing
// reserved '/recipes' placeholder destination rather than fabricating
// recipe content — that domain doesn't exist yet.
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
              ShellLayout.tablet => _TabletDashboard(householdName: householdName, snapshot: snapshot),
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
// Shared warm palette for Kitchen and Personal-iPad (tablet) layouts —
// mirrors the approved visual mockup 1:1 (ivory/cream ground, muted sage
// accent, restrained terracotta warning, soft borders/shadows). Deliberately
// a single light palette, not a dark-mode variant: a kitchen-counter display
// should look the same warm way every time, matching the mockup's own
// single-theme commitment.
// ---------------------------------------------------------------------------
class _Palette {
  const _Palette._();

  static const bg = Color(0xFFFAF3E6);
  static const surface = Color(0xFFFFFDF8);
  static const surfaceBeige = Color(0xFFF2E8D8);
  static const line = Color(0x173A2E22);
  static const ink = Color(0xFF362A1F);
  static const muted = Color(0xFF8A795F);
  static const faint = Color(0xFFB6A688);
  static const accent = Color(0xFF6F8F63);
  static const accentStrong = Color(0xFF56704A);
  static const accentInk = Color(0xFFFBFAF3);
  static const accentTint = Color(0xFFE9EFE2);
  static const warn = Color(0xFFB98A4E);
  static const warnTint = Color(0xFFF3E7CF);
  static const terracotta = Color(0xFFBD6B4C);
  static const terracottaTint = Color(0xFFF4E1D4);

  static const shadow = [
    BoxShadow(color: Color(0x14362A1F), blurRadius: 18, offset: Offset(0, 6)),
  ];
  static const shadowSm = [
    BoxShadow(color: Color(0x0D362A1F), blurRadius: 8, offset: Offset(0, 2)),
  ];
}

String _greetingFor(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December',
];

String _dateLabel(DateTime now) =>
    '${_weekdayNames[now.weekday - 1]}, ${_monthNames[now.month - 1]} ${now.day}';

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: _Palette.accent, borderRadius: BorderRadius.circular(9)),
          child: const Icon(Icons.eco_outlined, size: 16, color: _Palette.accentInk),
        ),
        const SizedBox(width: 9),
        const Text('Foodie', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _Palette.ink)),
        const SizedBox(width: 6),
        Text(
          'HOUSEHOLD & KITCHEN',
          style: TextStyle(fontSize: 9, letterSpacing: 1.0, fontWeight: FontWeight.w700, color: _Palette.faint),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final clear = snapshot.isAllClear;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _Palette.line),
        boxShadow: _Palette.shadowSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: clear ? _Palette.accent : _Palette.warn,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            clear
                ? 'All caught up.'
                : '${snapshot.attentionCount} thing${snapshot.attentionCount == 1 ? '' : 's'} need attention',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _Palette.muted),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.value, required this.label, this.warn = false, this.onTap});

  final IconData icon;
  final int value;
  final String label;
  final bool warn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: warn ? _Palette.terracottaTint : _Palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: warn ? null : Border.all(color: _Palette.line),
            boxShadow: _Palette.shadowSm,
          ),
          child: Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: warn ? Colors.white.withValues(alpha: 0.6) : _Palette.accentTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: warn ? _Palette.terracotta : _Palette.accentStrong),
              ),
              const SizedBox(height: 6),
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: warn ? _Palette.terracotta : _Palette.ink,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: warn ? _Palette.terracotta : _Palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.kitchen_outlined,
            value: snapshot.fridgeCount,
            label: 'Fridge',
            onTap: () => context.go('/inventory'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.ac_unit_outlined,
            value: snapshot.freezerCount,
            label: 'Freezer',
            onTap: () => context.go('/inventory'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.inventory_2_outlined,
            value: snapshot.pantryCount,
            label: 'Pantry',
            onTap: () => context.go('/inventory'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.error_outline,
            value: snapshot.expiringSoonItems.length + snapshot.expiredItems.length,
            label: 'Expiring soon',
            warn: true,
            onTap: () => context.go('/inventory'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.shopping_cart_outlined,
            value: snapshot.groceryUncheckedCount,
            label: 'Grocery list',
            onTap: () => context.go('/grocery'),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _Palette.ink),
      );
}

// A single "needs attention" item, category-agnostic — used by both the
// compact chip grid (Kitchen) and the list-style panel (tablet).
class _AttentionEntry {
  const _AttentionEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.tint,
    required this.tintOn,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color tint;
  final Color tintOn;
}

List<_AttentionEntry> _attentionEntries(BuildContext context, DashboardSnapshot snapshot) {
  const dust = (Color(0xFFEAE3D8), Color(0xFF7C6A52));
  const gold = (Color(0xFFF3E7CF), Color(0xFF9A7A3D));
  const terracotta = (_Palette.terracottaTint, _Palette.terracotta);
  const peach = (Color(0xFFF6E2D6), Color(0xFFB1704A));

  return [
    for (final task in snapshot.cleaningDueOrOverdue)
      _AttentionEntry(
        icon: Icons.cleaning_services_outlined,
        title: task.name,
        subtitle: task.area == null ? 'Due today' : '${task.area} · Due today',
        onTap: () => context.go('/home-care'),
        tint: dust.$1,
        tintOn: dust.$2,
      ),
    for (final component in snapshot.filtersDueOrOverdue)
      _AttentionEntry(
        icon: Icons.filter_alt_outlined,
        title: '${component.systemName} — ${component.componentName}',
        subtitle: 'Filter due',
        onTap: () => context.go('/supplies'),
        tint: gold.$1,
        tintOn: gold.$2,
      ),
    for (final issue in snapshot.openMaintenanceIssues)
      _AttentionEntry(
        icon: Icons.build_outlined,
        title: issue.title,
        subtitle: issue.area ?? 'Maintenance',
        onTap: () => context.go('/home-care'),
        tint: terracotta.$1,
        tintOn: terracotta.$2,
      ),
    for (final status in snapshot.sourdoughFeedStatuses.where((s) => s.overdue))
      _AttentionEntry(
        icon: Icons.bakery_dining_outlined,
        title: status.project.name,
        subtitle: 'Feeding overdue',
        onTap: () => context.go('/fermentation'),
        tint: peach.$1,
        tintOn: peach.$2,
      ),
    for (final item in snapshot.expiredItems)
      _AttentionEntry(
        icon: Icons.error_outline,
        title: item.name,
        subtitle: 'Expired',
        onTap: () => context.go('/inventory'),
        tint: peach.$1,
        tintOn: peach.$2,
      ),
  ];
}

class _AttentionChip extends StatelessWidget {
  const _AttentionChip({required this.entry});

  final _AttentionEntry entry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _Palette.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: entry.onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _Palette.line),
            boxShadow: _Palette.shadowSm,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: entry.tint, borderRadius: BorderRadius.circular(11)),
                child: Icon(entry.icon, size: 18, color: entry.tintOn),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: _Palette.ink),
                    ),
                    Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _Palette.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttentionGrid extends StatelessWidget {
  const _AttentionGrid({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final entries = _attentionEntries(context, snapshot);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final tileWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final entry in entries)
              SizedBox(width: tileWidth, child: _AttentionChip(entry: entry)),
          ],
        );
      },
    );
  }
}

// A sourdough-feeding-or-most-urgent project rendered as a large gradient
// spotlight card, with any remaining active projects shown as smaller
// companion cards beside/below it.
class _FermentationSpotlightRow extends StatelessWidget {
  const _FermentationSpotlightRow({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final projects = snapshot.activeFermentationProjects;
    if (projects.isEmpty) return const SizedBox.shrink();

    final overdue = snapshot.sourdoughFeedStatuses.where((s) => s.overdue).toList();
    final spotlightProject = overdue.isNotEmpty ? overdue.first.project : projects.first;
    final spotlightOverdue = overdue.any((s) => s.project.id == spotlightProject.id);
    final companions = projects.where((p) => p.id != spotlightProject.id).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 16,
          child: _FermentationSpotlight(project: spotlightProject, overdue: spotlightOverdue),
        ),
        if (companions.isNotEmpty) ...[
          const SizedBox(width: 14),
          Expanded(
            flex: 10,
            child: _FermentationCompanion(project: companions.first),
          ),
        ],
      ],
    );
  }
}

class _FermentationSpotlight extends StatelessWidget {
  const _FermentationSpotlight({required this.project, required this.overdue});

  final FermentationProject project;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final due = overdue
        ? 'Feeding overdue'
        : (project.currentStage ?? project.status.label);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.go('/fermentation'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: _Palette.shadowSm,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_Palette.accentTint, _Palette.surface],
              stops: [0, 0.68],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(color: _Palette.surface, shape: BoxShape.circle),
                child: Icon(
                  project.isSourdough ? Icons.bakery_dining_outlined : Icons.science_outlined,
                  size: 26,
                  color: _Palette.accentStrong,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.isSourdough ? 'SOURDOUGH STARTER' : project.projectType.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: _Palette.accentStrong,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: _Palette.ink),
                    ),
                    Text(
                      due,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: overdue ? _Palette.warn : _Palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _Palette.accent,
                  foregroundColor: _Palette.accentInk,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                ),
                onPressed: () => context.go('/fermentation'),
                child: Text(overdue ? 'Log Feeding' : 'View'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FermentationCompanion extends StatelessWidget {
  const _FermentationCompanion({required this.project});

  final FermentationProject project;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _Palette.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.go('/fermentation'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _Palette.line),
            boxShadow: _Palette.shadowSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                project.isSourdough ? Icons.bakery_dining_outlined : Icons.science_outlined,
                size: 22,
                color: _Palette.accentStrong,
              ),
              const SizedBox(height: 8),
              Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _Palette.ink),
              ),
              Text(
                project.currentStage ?? project.status.label,
                style: const TextStyle(fontSize: 12, color: _Palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarmEmptyCard extends StatelessWidget {
  const _WarmEmptyCard({required this.icon, required this.title, required this.message, this.large = false});

  final IconData icon;
  final String title;
  final String message;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(large ? 30 : 16),
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Palette.line),
      ),
      child: Column(
        children: [
          Icon(icon, size: large ? 40 : 28, color: _Palette.faint),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: large ? 17 : 14,
              fontWeight: FontWeight.w700,
              color: _Palette.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: _Palette.muted),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kitchen Device Mode: large touch targets, glanceable stat tiles, compact
// attention/fermentation cards, minimal typing. No voice, no Cooking Mode —
// explicitly deferred; "Cook" opens the reserved Recipes destination.
// ---------------------------------------------------------------------------
class _KitchenDashboard extends StatelessWidget {
  const _KitchenDashboard({required this.householdName, required this.snapshot});

  final String householdName;
  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return ColoredBox(
      color: _Palette.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
        children: [
          const _Brand(),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_greetingFor(now)}, $householdName',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: _Palette.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(_dateLabel(now), style: const TextStyle(fontSize: 14, color: _Palette.muted)),
                  ],
                ),
              ),
              _StatusPill(snapshot: snapshot),
            ],
          ),
          const SizedBox(height: 22),
          _StatsRow(snapshot: snapshot),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              children: [
                Expanded(
                  child: _KitchenBigButton(
                    icon: Icons.chat_bubble_outline,
                    label: 'Ask Foodie',
                    hero: true,
                    onTap: () => context.go('/foodie'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _KitchenBigButton(
                    icon: Icons.auto_stories_outlined,
                    label: 'Cook',
                    tag: 'Soon',
                    onTap: () => context.go('/recipes'),
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
          ),
          const _SectionLabel('Needs attention'),
          const SizedBox(height: 10),
          if (snapshot.isAllClear)
            const _WarmEmptyCard(
              icon: Icons.check_circle_outline,
              title: 'Nothing needs attention',
              message: 'Cleaning, filters, maintenance, and starters are all caught up.',
              large: true,
            )
          else
            _AttentionGrid(snapshot: snapshot),
          const SizedBox(height: 24),
          const _SectionLabel('Fermentation'),
          const SizedBox(height: 10),
          if (snapshot.activeFermentationProjects.isEmpty)
            const _WarmEmptyCard(
              icon: Icons.science_outlined,
              title: 'No active fermentation projects',
              message: 'Start a sourdough starter or a cacao batch from the Fermentation tab.',
              large: true,
            )
          else
            _FermentationSpotlightRow(snapshot: snapshot),
        ],
      ),
    );
  }
}

class _KitchenBigButton extends StatelessWidget {
  const _KitchenBigButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    this.tag,
    this.hero = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? badge;
  final String? tag;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
          decoration: BoxDecoration(
            color: hero ? _Palette.accent : _Palette.surfaceBeige,
            borderRadius: BorderRadius.circular(20),
            boxShadow: _Palette.shadowSm,
          ),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 40, color: hero ? _Palette.accentInk : _Palette.ink),
                  if (badge != null && badge! > 0)
                    Positioned(
                      right: -8,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _Palette.terracotta,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$badge',
                          style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: hero ? _Palette.accentInk : _Palette.ink,
                ),
              ),
              if (tag != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: hero ? Colors.white.withValues(alpha: 0.25) : _Palette.accentTint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    tag!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: hero ? _Palette.accentInk : _Palette.accentStrong,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Personal iPad (tablet): same warm visual language as Kitchen Mode, denser
// glanceable panels for someone actively planning/managing rather than
// glancing from across the room. The section-destination sidebar itself is
// AppShell's existing navigation rail — not duplicated here.
// ---------------------------------------------------------------------------
class _TabletDashboard extends StatelessWidget {
  const _TabletDashboard({required this.householdName, required this.snapshot});

  final String householdName;
  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return ColoredBox(
      color: _Palette.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_greetingFor(now)}, $householdName',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: _Palette.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(_dateLabel(now), style: const TextStyle(fontSize: 13, color: _Palette.muted)),
                  ],
                ),
              ),
              _StatusPill(snapshot: snapshot),
            ],
          ),
          const SizedBox(height: 20),
          _StatsRow(snapshot: snapshot),
          const SizedBox(height: 20),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _UseSoonPanel(snapshot: snapshot)),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: snapshot.activeFermentationProjects.isEmpty
                      ? const _PanelCard(
                          title: 'Fermentation',
                          icon: Icons.science_outlined,
                          child: _WarmEmptyCard(
                            icon: Icons.science_outlined,
                            title: 'No active projects',
                            message: 'Start a sourdough starter or a cacao batch.',
                          ),
                        )
                      : _PanelCard(
                          title: 'Fermentation Spotlight',
                          icon: Icons.science_outlined,
                          child: _FermentationSpotlightRow(snapshot: snapshot),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(child: _TodaysTasksPanel(snapshot: snapshot)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _Palette.accent,
                  foregroundColor: _Palette.accentInk,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Ask Foodie'),
                onPressed: () => context.go('/foodie'),
              ),
              const SizedBox(width: 12),
              const Expanded(child: _QuickActions()),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _FoodPanel(snapshot: snapshot)),
              const SizedBox(width: 14),
              Expanded(child: _HomePanel(snapshot: snapshot)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
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
    return Material(
      color: _Palette.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _Palette.line),
            boxShadow: _Palette.shadowSm,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: _Palette.accentStrong),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: _Palette.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniRow extends StatelessWidget {
  const _MiniRow({required this.text, this.emphasis = false});

  final String text;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: emphasis ? _Palette.warn : _Palette.ink,
          fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

class _UseSoonPanel extends StatelessWidget {
  const _UseSoonPanel({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final expired = snapshot.expiredItems;
    final expiring = snapshot.expiringSoonItems;
    return _PanelCard(
      title: 'Use Soon',
      icon: Icons.access_time,
      onTap: () => context.go('/inventory'),
      child: expired.isEmpty && expiring.isEmpty
          ? const Text('Nothing expiring soon', style: TextStyle(fontSize: 13, color: _Palette.muted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in expired.take(3)) _MiniRow(text: '${item.name} — expired', emphasis: true),
                for (final item in expiring.take(3)) _MiniRow(text: '${item.name} — expiring soon'),
              ],
            ),
    );
  }
}

class _TodaysTasksPanel extends StatelessWidget {
  const _TodaysTasksPanel({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final entries = _attentionEntries(context, snapshot);
    return _PanelCard(
      title: "Today's Tasks",
      icon: Icons.today_outlined,
      child: entries.isEmpty
          ? const Text('All caught up', style: TextStyle(fontSize: 13, color: _Palette.muted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final e in entries.take(4)) _MiniRow(text: e.title)],
            ),
    );
  }
}

class _FoodPanel extends StatelessWidget {
  const _FoodPanel({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: 'Grocery List',
      icon: Icons.shopping_cart_outlined,
      onTap: () => context.go('/grocery'),
      child: Text(
        snapshot.groceryUncheckedCount == 0
            ? 'Grocery list is clear'
            : '${snapshot.groceryUncheckedCount} item${snapshot.groceryUncheckedCount == 1 ? '' : 's'} on the list',
        style: const TextStyle(fontSize: 13, color: _Palette.muted),
      ),
    );
  }
}

class _HomePanel extends StatelessWidget {
  const _HomePanel({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final hasContent = snapshot.cleaningDueOrOverdue.isNotEmpty ||
        snapshot.filtersDueOrOverdue.isNotEmpty ||
        snapshot.openMaintenanceIssues.isNotEmpty;
    return _PanelCard(
      title: 'Home Care',
      icon: Icons.home_outlined,
      onTap: () => context.go('/home-care'),
      child: !hasContent
          ? const Text(
              'Nothing due — cleaning, filters, and maintenance are all caught up',
              style: TextStyle(fontSize: 13, color: _Palette.muted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final task in snapshot.cleaningDueOrOverdue.take(3)) _MiniRow(text: '${task.name} — due'),
                for (final component in snapshot.filtersDueOrOverdue.take(3))
                  _MiniRow(text: '${component.componentName} — due'),
                for (final issue in snapshot.openMaintenanceIssues.take(3)) _MiniRow(text: '${issue.title} — open'),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phone: compact sections + quick actions, on the app's default theme. Not
// part of the warm-palette visual review — kept structurally unchanged.
// [columns] gives a slightly wider layout a bit more breathing room without
// changing content.
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
