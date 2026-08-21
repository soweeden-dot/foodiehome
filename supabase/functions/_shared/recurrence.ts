// Due-date computation for cleaning tasks and tracked components (filters).
// Deliberately pure and dependency-free: dates in, a date out — no I/O.
//
// ARCHITECTURE NOTE: next-due is COMPUTED, never stored (see DATABASE.md's
// "Sync-relevant schema features" and the assets/home-care design notes).
// This is the TypeScript half of that computation; app/lib/domain/recurrence.dart
// is the Dart half (used by the Flutter UI). Same algorithm, reimplemented
// per-runtime rather than shared, since Edge Functions (Deno) and Flutter
// (Dart) don't share a runtime — consistent with how this codebase already
// duplicates domain logic across the two clients where needed.
//
// CLEANING_DAYS below encodes this household's fixed cleaning cadence
// (Wednesday + Sunday) directly, per the explicit spec: "twice weekly:
// Wednesday + Sunday", every other cadence anchored on Sunday. Not
// configurable this phase.

export interface RecurrenceRuleInput {
  intervalUnit: "day" | "week" | "month" | "year";
  intervalCount: number;
  /** 0 = Sunday .. 6 = Saturday. The rule's preferred/anchor weekday. */
  weekday: number | null;
  anchorDate: string | null; // ISO date, used when there's no completion yet
}

const SUNDAY = 0;
const WEDNESDAY = 3;
/** The household's two designated cleaning days. Rollover always searches
 * this set, regardless of a given task's own anchor weekday — an overdue
 * Wednesday-only task can roll to the coming Sunday rather than waiting a
 * full week. See docs/DECISIONS.md for the reasoning. */
const CLEANING_DAYS = new Set([WEDNESDAY, SUNDAY]);

function toUtcMidnight(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

function parseDateOnly(iso: string): Date {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

function addDays(d: Date, days: number): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + days));
}

function addMonths(d: Date, months: number): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + months, d.getUTCDate()));
}

/** The nearest date >= [from] whose weekday is in [days] ([from] included). */
function nextMatchingWeekday(from: Date, days: Set<number>): Date {
  for (let offset = 0; offset < 7; offset++) {
    const candidate = addDays(from, offset);
    if (days.has(candidate.getUTCDay())) return candidate;
  }
  // Unreachable: CLEANING_DAYS/a single weekday set always matches within 7 days.
  return from;
}

export interface DueComputationInput {
  rule: RecurrenceRuleInput;
  /** Most recent completion date (outcome-agnostic — see callers), or null. */
  lastCompletedOn: string | null;
  today: Date;
}

/**
 * Computes the next due date for a cleaning task.
 *
 * 1. Advance from the last completion (or the rule's anchor, or today) by
 *    one interval.
 * 2. If the rule has a target weekday, snap forward to the next occurrence
 *    of it (a no-op for week-interval rules whose base already fell on that
 *    weekday; does real work for month/year rules, which rarely land on a
 *    specific weekday by calendar arithmetic alone).
 * 3. Rollover: if that date has already passed and the task is still
 *    incomplete, the due date becomes the nearest upcoming household
 *    cleaning day (today included) instead of a stale date in the past.
 */
export function computeCleaningDueDate(input: DueComputationInput): Date {
  const today = toUtcMidnight(input.today);
  const base = input.lastCompletedOn
    ? toUtcMidnight(parseDateOnly(input.lastCompletedOn))
    : input.rule.anchorDate
    ? toUtcMidnight(parseDateOnly(input.rule.anchorDate))
    : today;

  let theoretical: Date;
  switch (input.rule.intervalUnit) {
    case "day":
      theoretical = addDays(base, input.rule.intervalCount);
      break;
    case "week":
      theoretical = addDays(base, input.rule.intervalCount * 7);
      break;
    case "month":
      theoretical = addMonths(base, input.rule.intervalCount);
      break;
    case "year":
      theoretical = addMonths(base, input.rule.intervalCount * 12);
      break;
  }

  const snapped = input.rule.weekday !== null
    ? nextMatchingWeekday(theoretical, new Set([input.rule.weekday]))
    : theoretical;

  if (snapped.getTime() < today.getTime()) {
    return nextMatchingWeekday(today, CLEANING_DAYS);
  }
  return snapped;
}

/** Filters/components: a simple interval in days from the last replacement
 * (or install date) — no weekday anchoring, unlike cleaning. */
export function computeComponentDueDate(input: {
  replaceIntervalDays: number | null;
  lastReplacedOn: string | null;
  installedOn: string | null;
}): Date | null {
  if (input.replaceIntervalDays === null) return null;
  const base = input.lastReplacedOn ?? input.installedOn;
  if (base === null) return null;
  return addDays(toUtcMidnight(parseDateOnly(base)), input.replaceIntervalDays);
}

export function isOverdue(dueDate: Date, today: Date): boolean {
  return toUtcMidnight(dueDate).getTime() < toUtcMidnight(today).getTime();
}
