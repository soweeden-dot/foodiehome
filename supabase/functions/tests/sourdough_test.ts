import { assert, assertEquals } from "./asserts.ts";
import {
  computeFeedRatio,
  computeHydrationPercent,
  computeNextFeedDue,
  isFeedOverdue,
} from "../_shared/sourdough.ts";

Deno.test("computeHydrationPercent: equal-weight feed is 100% hydration", () => {
  assertEquals(computeHydrationPercent({ starterG: 10, flourG: 50, waterG: 50 }), 100);
});

Deno.test("computeHydrationPercent: rounds to one decimal place", () => {
  assertEquals(computeHydrationPercent({ starterG: 10, flourG: 30, waterG: 20 }), 66.7);
});

Deno.test("computeFeedRatio: normalizes flour/water to the starter amount", () => {
  assertEquals(computeFeedRatio({ starterG: 10, flourG: 50, waterG: 50 }), "1 : 5 : 5");
  assertEquals(computeFeedRatio({ starterG: 20, flourG: 100, waterG: 80 }), "1 : 5 : 4");
});

Deno.test("computeNextFeedDue: adds the interval to the last feeding time", () => {
  const lastFed = new Date("2026-08-10T09:00:00Z");
  const due = computeNextFeedDue(lastFed, 24);
  assert(due !== null);
  assertEquals(due!.toISOString(), "2026-08-11T09:00:00.000Z");
});

Deno.test("computeNextFeedDue: null when never fed", () => {
  assertEquals(computeNextFeedDue(null, 24), null);
});

Deno.test("computeNextFeedDue: refrigerated cadence is a week out", () => {
  const lastFed = new Date("2026-08-01T00:00:00Z");
  const due = computeNextFeedDue(lastFed, 168);
  assert(due !== null);
  assertEquals(due!.toISOString(), "2026-08-08T00:00:00.000Z");
});

Deno.test("isFeedOverdue: true once now passes the due time", () => {
  const due = new Date("2026-08-10T09:00:00Z");
  assert(isFeedOverdue(due, new Date("2026-08-10T10:00:00Z")));
  assert(!isFeedOverdue(due, new Date("2026-08-10T08:00:00Z")));
});

Deno.test("isFeedOverdue: never overdue when there's no due date", () => {
  assert(!isFeedOverdue(null, new Date()));
});
