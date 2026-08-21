/// Sourdough-specific computations. Deliberately pure — mirrors
/// recurrence.dart's split between raw stored data and values computed at
/// read time. The TypeScript half (used by Foodie's agent tools) is
/// supabase/functions/_shared/sourdough.ts, same formulas.
///
/// A feeding log stores only the raw measurements (starter/flour/water
/// grams, flour type, discard); hydration %, the feed ratio, and next-feed
/// due are all COMPUTED from those raw numbers here, never stored.
library;

class FeedingMeasurements {
  const FeedingMeasurements({
    required this.starterG,
    required this.flourG,
    required this.waterG,
  });

  final double starterG;
  final double flourG;
  final double waterG;
}

/// Baker's-percentage hydration: water as a percentage of flour weight.
double computeHydrationPercent(FeedingMeasurements m) =>
    (m.waterG / m.flourG * 1000).round() / 10;

/// Starter:flour:water ratio, normalized to the starter amount (e.g. "1 : 5 : 5").
String computeFeedRatio(FeedingMeasurements m) {
  final flourRatio = (m.flourG / m.starterG * 100).round() / 100;
  final waterRatio = (m.waterG / m.starterG * 100).round() / 100;
  return '1 : ${_trimZeros(flourRatio)} : ${_trimZeros(waterRatio)}';
}

String _trimZeros(double v) {
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

/// A sourdough starter's cadence isn't a calendar recurrence rule like
/// cleaning — it's "feed every N hours from the last feeding," where N
/// depends on state (active on the counter vs. refrigerated).
DateTime? computeNextFeedDue({
  required DateTime? lastFedAt,
  required int feedIntervalHours,
}) {
  if (lastFedAt == null) return null;
  return lastFedAt.add(Duration(hours: feedIntervalHours));
}

bool isFeedOverdue(DateTime? nextFeedDue, DateTime now) {
  if (nextFeedDue == null) return false;
  return nextFeedDue.isBefore(now);
}

const defaultActiveFeedIntervalHours = 24;
const defaultRefrigeratedFeedIntervalHours = 168; // weekly
