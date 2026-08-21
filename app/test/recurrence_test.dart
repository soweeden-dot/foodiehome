import 'package:flutter_test/flutter_test.dart';
import 'package:foodiehome/domain/recurrence.dart';

DateTime _d(String iso) => DateTime.parse(iso);
String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

void main() {
  test('weekly Sunday task with a recent completion returns next Sunday, no snap needed', () {
    final due = computeCleaningDueDate(
      rule: const RecurrenceRuleInput(
        intervalUnit: RecurrenceIntervalUnit.week,
        intervalCount: 1,
        weekday: 0,
      ),
      lastCompletedOn: _d('2026-08-09'),
      today: _d('2026-08-10'),
    );
    expect(_iso(due), '2026-08-16');
  });

  test('monthly task where calendar-month arithmetic lands mid-week snaps to next Sunday', () {
    final due = computeCleaningDueDate(
      rule: const RecurrenceRuleInput(
        intervalUnit: RecurrenceIntervalUnit.month,
        intervalCount: 1,
        weekday: 0,
      ),
      lastCompletedOn: _d('2026-06-07'),
      today: _d('2026-06-10'),
    );
    expect(_iso(due), '2026-07-12');
  });

  test(
    'overdue Wednesday-only task rolls over to the nearest of {Wed, Sun} from today, not the next Wednesday',
    () {
      final due = computeCleaningDueDate(
        rule: const RecurrenceRuleInput(
          intervalUnit: RecurrenceIntervalUnit.week,
          intervalCount: 1,
          weekday: 3,
        ),
        lastCompletedOn: _d('2026-07-29'),
        today: _d('2026-08-09'),
      );
      expect(_iso(due), '2026-08-09');
    },
  );

  test('never-completed task uses anchorDate as the base', () {
    final due = computeCleaningDueDate(
      rule: RecurrenceRuleInput(
        intervalUnit: RecurrenceIntervalUnit.week,
        intervalCount: 2,
        weekday: 0,
        anchorDate: _d('2026-08-02'),
      ),
      lastCompletedOn: null,
      today: _d('2026-08-03'),
    );
    expect(_iso(due), '2026-08-16');
  });

  test('task with neither completion nor anchor falls back to today as the base', () {
    final due = computeCleaningDueDate(
      rule: const RecurrenceRuleInput(
        intervalUnit: RecurrenceIntervalUnit.week,
        intervalCount: 1,
        weekday: 0,
      ),
      lastCompletedOn: null,
      today: _d('2026-08-10'),
    );
    expect(_iso(due), '2026-08-23');
  });

  test('component due date is a simple interval from last replacement', () {
    final due = computeComponentDueDate(
      replaceIntervalDays: 90,
      lastReplacedOn: _d('2026-05-01'),
      installedOn: _d('2026-01-01'),
    );
    expect(due, isNotNull);
    expect(_iso(due!), '2026-07-30');
  });

  test('component due date falls back to installedOn when never replaced', () {
    final due = computeComponentDueDate(
      replaceIntervalDays: 30,
      lastReplacedOn: null,
      installedOn: _d('2026-08-01'),
    );
    expect(due, isNotNull);
    expect(_iso(due!), '2026-08-31');
  });

  test("component due date is null when there's no interval or no base date", () {
    expect(
      computeComponentDueDate(
        replaceIntervalDays: null,
        lastReplacedOn: _d('2026-08-01'),
        installedOn: null,
      ),
      isNull,
    );
    expect(
      computeComponentDueDate(
        replaceIntervalDays: 30,
        lastReplacedOn: null,
        installedOn: null,
      ),
      isNull,
    );
  });

  test('isOverdue compares date-only, ignoring time-of-day', () {
    expect(isOverdue(_d('2026-08-01'), _d('2026-08-02')), isTrue);
    expect(isOverdue(_d('2026-08-02'), _d('2026-08-02')), isFalse);
    expect(isOverdue(_d('2026-08-03'), _d('2026-08-02')), isFalse);
  });
}
