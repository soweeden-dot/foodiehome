/// Due-date computation for cleaning tasks and tracked components (filters).
/// Deliberately pure: dates in, a date out — no I/O.
///
/// ARCHITECTURE NOTE: next-due is COMPUTED, never stored. This is the Dart
/// half of that computation, used by the Flutter UI; the TypeScript half
/// (used by Foodie's Edge Function tools) is
/// supabase/functions/_shared/recurrence.ts. Same algorithm, reimplemented
/// per-runtime rather than shared, since the two clients don't share one.
///
/// [cleaningDays] below encodes this household's fixed cleaning cadence
/// (Wednesday + Sunday) directly, per the explicit spec: "twice weekly:
/// Wednesday + Sunday", every other cadence anchored on Sunday. Not
/// configurable this phase.
library;

enum RecurrenceIntervalUnit { day, week, month, year }

class RecurrenceRuleInput {
  const RecurrenceRuleInput({
    required this.intervalUnit,
    required this.intervalCount,
    this.weekday,
    this.anchorDate,
  });

  final RecurrenceIntervalUnit intervalUnit;
  final int intervalCount;

  /// 0 = Sunday .. 6 = Saturday. The rule's preferred/anchor weekday.
  final int? weekday;

  /// Used when there's no completion yet.
  final DateTime? anchorDate;
}

const _sunday = 0;
const _wednesday = 3;

/// The household's two designated cleaning days. Rollover always searches
/// this set, regardless of a given task's own anchor weekday — an overdue
/// Wednesday-only task can roll to the coming Sunday rather than waiting a
/// full week. See docs/DECISIONS.md for the reasoning.
const cleaningDays = {_wednesday, _sunday};

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Dart's DateTime.weekday is 1 (Monday) .. 7 (Sunday); the rest of this
/// module (and the wire format) uses 0 (Sunday) .. 6 (Saturday), matching
/// the TypeScript half and the SQL `weekday` column.
int _sundayZeroWeekday(DateTime d) => d.weekday % 7;

/// The nearest date >= [from] whose weekday is in [days] ([from] included).
DateTime _nextMatchingWeekday(DateTime from, Set<int> days) {
  for (var offset = 0; offset < 7; offset++) {
    final candidate = from.add(Duration(days: offset));
    if (days.contains(_sundayZeroWeekday(candidate))) return candidate;
  }
  // Unreachable: cleaningDays/a single weekday set always matches within 7 days.
  return from;
}

/// Computes the next due date for a cleaning task.
///
/// 1. Advance from the last completion (or the rule's anchor, or today) by
///    one interval.
/// 2. If the rule has a target weekday, snap forward to the next occurrence
///    of it.
/// 3. Rollover: if that date has already passed and the task is still
///    incomplete, the due date becomes the nearest upcoming household
///    cleaning day (today included) instead of a stale date in the past.
DateTime computeCleaningDueDate({
  required RecurrenceRuleInput rule,
  required DateTime? lastCompletedOn,
  required DateTime today,
}) {
  final todayOnly = _dateOnly(today);
  final base = lastCompletedOn != null
      ? _dateOnly(lastCompletedOn)
      : rule.anchorDate != null
          ? _dateOnly(rule.anchorDate!)
          : todayOnly;

  final DateTime theoretical;
  switch (rule.intervalUnit) {
    case RecurrenceIntervalUnit.day:
      theoretical = base.add(Duration(days: rule.intervalCount));
    case RecurrenceIntervalUnit.week:
      theoretical = base.add(Duration(days: rule.intervalCount * 7));
    case RecurrenceIntervalUnit.month:
      theoretical = DateTime(base.year, base.month + rule.intervalCount, base.day);
    case RecurrenceIntervalUnit.year:
      theoretical = DateTime(base.year, base.month + rule.intervalCount * 12, base.day);
  }

  final snapped = rule.weekday != null
      ? _nextMatchingWeekday(theoretical, {rule.weekday!})
      : theoretical;

  if (snapped.isBefore(todayOnly)) {
    return _nextMatchingWeekday(todayOnly, cleaningDays);
  }
  return snapped;
}

/// Filters/components: a simple interval in days from the last replacement
/// (or install date) — no weekday anchoring, unlike cleaning.
DateTime? computeComponentDueDate({
  required int? replaceIntervalDays,
  required DateTime? lastReplacedOn,
  required DateTime? installedOn,
}) {
  if (replaceIntervalDays == null) return null;
  final base = lastReplacedOn ?? installedOn;
  if (base == null) return null;
  return _dateOnly(base).add(Duration(days: replaceIntervalDays));
}

bool isOverdue(DateTime dueDate, DateTime today) =>
    _dateOnly(dueDate).isBefore(_dateOnly(today));
