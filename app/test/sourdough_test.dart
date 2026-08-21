import 'package:flutter_test/flutter_test.dart';
import 'package:foodiehome/domain/sourdough.dart';

void main() {
  test('computeHydrationPercent: equal-weight feed is 100% hydration', () {
    expect(
      computeHydrationPercent(const FeedingMeasurements(starterG: 10, flourG: 50, waterG: 50)),
      100,
    );
  });

  test('computeHydrationPercent: rounds to one decimal place', () {
    expect(
      computeHydrationPercent(const FeedingMeasurements(starterG: 10, flourG: 30, waterG: 20)),
      66.7,
    );
  });

  test('computeFeedRatio: normalizes flour/water to the starter amount', () {
    expect(
      computeFeedRatio(const FeedingMeasurements(starterG: 10, flourG: 50, waterG: 50)),
      '1 : 5 : 5',
    );
    expect(
      computeFeedRatio(const FeedingMeasurements(starterG: 20, flourG: 100, waterG: 80)),
      '1 : 5 : 4',
    );
  });

  test('computeNextFeedDue: adds the interval to the last feeding time', () {
    final due = computeNextFeedDue(
      lastFedAt: DateTime.utc(2026, 8, 10, 9),
      feedIntervalHours: 24,
    );
    expect(due, DateTime.utc(2026, 8, 11, 9));
  });

  test('computeNextFeedDue: null when never fed', () {
    expect(computeNextFeedDue(lastFedAt: null, feedIntervalHours: 24), isNull);
  });

  test('computeNextFeedDue: refrigerated cadence is a week out', () {
    final due = computeNextFeedDue(
      lastFedAt: DateTime.utc(2026, 8, 1),
      feedIntervalHours: defaultRefrigeratedFeedIntervalHours,
    );
    expect(due, DateTime.utc(2026, 8, 8));
  });

  test('isFeedOverdue: true once now passes the due time', () {
    final due = DateTime.utc(2026, 8, 10, 9);
    expect(isFeedOverdue(due, DateTime.utc(2026, 8, 10, 10)), isTrue);
    expect(isFeedOverdue(due, DateTime.utc(2026, 8, 10, 8)), isFalse);
  });

  test("isFeedOverdue: never overdue when there's no due date", () {
    expect(isFeedOverdue(null, DateTime.now()), isFalse);
  });
}
