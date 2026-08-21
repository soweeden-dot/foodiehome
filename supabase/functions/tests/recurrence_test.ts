import { assert, assertEquals } from "./asserts.ts";
import {
  computeCleaningDueDate,
  computeComponentDueDate,
  isOverdue,
} from "../_shared/recurrence.ts";

function d(iso: string): Date {
  const [y, m, day] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, day));
}
function iso(date: Date): string {
  return date.toISOString().slice(0, 10);
}

Deno.test("weekly Sunday task with a recent completion returns next Sunday, no snap needed", () => {
  // 2026-08-09 is a Sunday; today is that same week, well before the next one.
  const due = computeCleaningDueDate({
    rule: { intervalUnit: "week", intervalCount: 1, weekday: 0, anchorDate: null },
    lastCompletedOn: "2026-08-09",
    today: d("2026-08-10"),
  });
  assertEquals(iso(due), "2026-08-16");
});

Deno.test("monthly task where calendar-month arithmetic lands mid-week snaps to next Sunday", () => {
  // Last completed 2026-06-07 (a Sunday). +1 month = 2026-07-07, a Tuesday.
  // Rule wants Sunday, so it should snap forward to 2026-07-12.
  const due = computeCleaningDueDate({
    rule: { intervalUnit: "month", intervalCount: 1, weekday: 0, anchorDate: null },
    lastCompletedOn: "2026-06-07",
    today: d("2026-06-10"),
  });
  assertEquals(iso(due), "2026-07-12");
});

Deno.test("overdue Wednesday-only task rolls over to the nearest of {Wed, Sun} from today, not the next Wednesday", () => {
  // Weekly Wednesday task, last completed 2026-07-29 (Wed). Theoretical next
  // due = 2026-08-05 (Wed). Today is 2026-08-09 (Sunday) — already past due
  // and still incomplete, so it should roll to today (a Sunday), not wait
  // until the following Wednesday (2026-08-12).
  const due = computeCleaningDueDate({
    rule: { intervalUnit: "week", intervalCount: 1, weekday: 3, anchorDate: null },
    lastCompletedOn: "2026-07-29",
    today: d("2026-08-09"),
  });
  assertEquals(iso(due), "2026-08-09");
});

Deno.test("never-completed task uses anchorDate as the base", () => {
  const due = computeCleaningDueDate({
    rule: { intervalUnit: "week", intervalCount: 2, weekday: 0, anchorDate: "2026-08-02" },
    lastCompletedOn: null,
    today: d("2026-08-03"),
  });
  // base = anchor 2026-08-02 (Sunday) + 2 weeks = 2026-08-16 (already a Sunday, no snap needed).
  assertEquals(iso(due), "2026-08-16");
});

Deno.test("task with neither completion nor anchor falls back to today as the base", () => {
  const due = computeCleaningDueDate({
    rule: { intervalUnit: "week", intervalCount: 1, weekday: 0, anchorDate: null },
    lastCompletedOn: null,
    today: d("2026-08-10"), // a Monday
  });
  // base = today 2026-08-10 + 1 week = 2026-08-17 (Monday), snapped to next Sunday = 2026-08-23.
  assertEquals(iso(due), "2026-08-23");
});

Deno.test("component due date is a simple interval from last replacement", () => {
  const due = computeComponentDueDate({
    replaceIntervalDays: 90,
    lastReplacedOn: "2026-05-01",
    installedOn: "2026-01-01",
  });
  assert(due !== null);
  assertEquals(iso(due!), "2026-07-30");
});

Deno.test("component due date falls back to installedOn when never replaced", () => {
  const due = computeComponentDueDate({
    replaceIntervalDays: 30,
    lastReplacedOn: null,
    installedOn: "2026-08-01",
  });
  assert(due !== null);
  assertEquals(iso(due!), "2026-08-31");
});

Deno.test("component due date is null when there's no interval or no base date", () => {
  assertEquals(
    computeComponentDueDate({ replaceIntervalDays: null, lastReplacedOn: "2026-08-01", installedOn: null }),
    null,
  );
  assertEquals(
    computeComponentDueDate({ replaceIntervalDays: 30, lastReplacedOn: null, installedOn: null }),
    null,
  );
});

Deno.test("isOverdue compares date-only, ignoring time-of-day", () => {
  assert(isOverdue(d("2026-08-01"), d("2026-08-02")));
  assert(!isOverdue(d("2026-08-02"), d("2026-08-02")));
  assert(!isOverdue(d("2026-08-03"), d("2026-08-02")));
});
