// Sourdough-specific computations. Deliberately pure and dependency-free —
// mirrors recurrence.ts's split between raw stored data and values computed
// at read time.
//
// ARCHITECTURE NOTE: a feeding log stores only the raw measurements
// (starter_g, flour_g, water_g, flour_type, discard_g — see migration 16's
// foodie_log_sourdough_feeding). Hydration %, the starter:flour:water ratio,
// and next-feed-due are all COMPUTED from those raw numbers, never stored —
// avoids a derived value silently drifting from the numbers it was derived
// from. This is the TypeScript half; app/lib/domain/sourdough.dart is the
// Dart half (used by the Flutter UI), same formulas.

export interface FeedingMeasurements {
  starterG: number;
  flourG: number;
  waterG: number;
}

/** Baker's-percentage hydration: water as a percentage of flour weight. */
export function computeHydrationPercent(m: FeedingMeasurements): number {
  return Math.round((m.waterG / m.flourG) * 1000) / 10;
}

/** Starter:flour:water ratio, normalized to the starter amount (e.g. "1 : 5 : 5"). */
export function computeFeedRatio(m: FeedingMeasurements): string {
  const flourRatio = Math.round((m.flourG / m.starterG) * 100) / 100;
  const waterRatio = Math.round((m.waterG / m.starterG) * 100) / 100;
  return `1 : ${flourRatio} : ${waterRatio}`;
}

/**
 * A sourdough starter's cadence isn't a calendar recurrence rule like
 * cleaning — it's "feed every N hours from the last feeding," where N
 * depends on state (active on the counter vs. refrigerated). Next-feed-due
 * is simply the last feeding time plus that interval; there is no weekday
 * anchoring or rollover the way cleaning has.
 */
export function computeNextFeedDue(
  lastFedAt: Date | null,
  feedIntervalHours: number,
): Date | null {
  if (lastFedAt === null) return null;
  return new Date(lastFedAt.getTime() + feedIntervalHours * 60 * 60 * 1000);
}

export function isFeedOverdue(nextFeedDue: Date | null, now: Date): boolean {
  if (nextFeedDue === null) return false;
  return nextFeedDue.getTime() < now.getTime();
}

/** Default feed cadence when a project's target_params doesn't specify one. */
export const DEFAULT_ACTIVE_FEED_INTERVAL_HOURS = 24;
export const DEFAULT_REFRIGERATED_FEED_INTERVAL_HOURS = 168; // weekly
