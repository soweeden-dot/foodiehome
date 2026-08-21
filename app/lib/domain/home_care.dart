/// Domain models for Cleaning + Home Care. Plain immutable Dart, independent
/// of the Supabase row shape — mirrors the pattern established in
/// domain/inventory.dart. Next-due dates are COMPUTED on demand from
/// recurrence.dart, never stored on these models.
library;

import 'recurrence.dart' as rec;
import 'recurrence.dart' show RecurrenceIntervalUnit, RecurrenceRuleInput;

enum CleaningOutcome { completed, skipped }

class RecurrenceSummary {
  const RecurrenceSummary({
    required this.intervalUnit,
    required this.intervalCount,
    this.weekday,
  });

  final RecurrenceIntervalUnit intervalUnit;
  final int intervalCount;

  /// 0 = Sunday .. 6 = Saturday, or null for rules with no weekday anchor.
  final int? weekday;

  static const _weekdayNames = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  /// Human-readable cadence, e.g. "every week (Sunday)", "every 3 months".
  String get label {
    final unitWord = switch (intervalUnit) {
      RecurrenceIntervalUnit.day => 'day',
      RecurrenceIntervalUnit.week => 'week',
      RecurrenceIntervalUnit.month => 'month',
      RecurrenceIntervalUnit.year => 'year',
    };
    final cadence = intervalCount == 1 ? 'every $unitWord' : 'every $intervalCount ${unitWord}s';
    return weekday == null ? cadence : '$cadence (${_weekdayNames[weekday!]})';
  }

  @override
  bool operator ==(Object other) =>
      other is RecurrenceSummary &&
      other.intervalUnit == intervalUnit &&
      other.intervalCount == intervalCount &&
      other.weekday == weekday;

  @override
  int get hashCode => Object.hash(intervalUnit, intervalCount, weekday);
}

class CleaningTask {
  const CleaningTask({
    required this.id,
    required this.name,
    this.area,
    this.recurrence,
    this.assignedUserName,
    this.suppliesNeeded = const [],
    this.lastCompletedOn,
  });

  final String id;
  final String name;
  final String? area;
  final RecurrenceSummary? recurrence;
  final String? assignedUserName;
  final List<String> suppliesNeeded;
  final DateTime? lastCompletedOn;

  /// Computed, never stored — null when the task has no recurrence rule.
  DateTime? nextDueOn({DateTime? asOf}) {
    final rule = recurrence;
    if (rule == null) return null;
    return rec.computeCleaningDueDate(
      rule: RecurrenceRuleInput(
        intervalUnit: rule.intervalUnit,
        intervalCount: rule.intervalCount,
        weekday: rule.weekday,
      ),
      lastCompletedOn: lastCompletedOn,
      today: asOf ?? DateTime.now(),
    );
  }

  bool isOverdue({DateTime? asOf}) {
    final due = nextDueOn(asOf: asOf);
    if (due == null) return false;
    return rec.isOverdue(due, asOf ?? DateTime.now());
  }

  @override
  bool operator ==(Object other) =>
      other is CleaningTask &&
      other.id == id &&
      other.name == name &&
      other.area == area &&
      other.recurrence == recurrence &&
      other.assignedUserName == assignedUserName &&
      other.lastCompletedOn == lastCompletedOn;

  @override
  int get hashCode =>
      Object.hash(id, name, area, recurrence, assignedUserName, lastCompletedOn);
}

class TrackedComponent {
  const TrackedComponent({
    required this.id,
    required this.systemName,
    required this.componentName,
    required this.kind,
    this.installedOn,
    this.replaceIntervalDays,
    this.sparesCount = 0,
    this.lastReplacedOn,
  });

  final String id;
  final String systemName;
  final String componentName;
  final String kind;
  final DateTime? installedOn;
  final int? replaceIntervalDays;
  final int sparesCount;
  final DateTime? lastReplacedOn;

  /// Computed, never stored — null when there's no replace interval set.
  DateTime? nextDueOn({DateTime? asOf}) => rec.computeComponentDueDate(
        replaceIntervalDays: replaceIntervalDays,
        lastReplacedOn: lastReplacedOn,
        installedOn: installedOn,
      );

  bool isOverdue({DateTime? asOf}) {
    final due = nextDueOn(asOf: asOf);
    if (due == null) return false;
    return rec.isOverdue(due, asOf ?? DateTime.now());
  }

  @override
  bool operator ==(Object other) =>
      other is TrackedComponent &&
      other.id == id &&
      other.systemName == systemName &&
      other.componentName == componentName &&
      other.kind == kind &&
      other.installedOn == installedOn &&
      other.replaceIntervalDays == replaceIntervalDays &&
      other.sparesCount == sparesCount &&
      other.lastReplacedOn == lastReplacedOn;

  @override
  int get hashCode => Object.hash(
        id,
        systemName,
        componentName,
        kind,
        installedOn,
        replaceIntervalDays,
        sparesCount,
        lastReplacedOn,
      );
}

enum MaintenanceIssueStatus { open, inProgress, resolved }

extension MaintenanceIssueStatusWire on MaintenanceIssueStatus {
  static MaintenanceIssueStatus fromWire(String value) => switch (value) {
        'open' => MaintenanceIssueStatus.open,
        'in_progress' => MaintenanceIssueStatus.inProgress,
        'resolved' => MaintenanceIssueStatus.resolved,
        _ => throw ArgumentError('unknown maintenance issue status: $value'),
      };

  String toWire() => switch (this) {
        MaintenanceIssueStatus.open => 'open',
        MaintenanceIssueStatus.inProgress => 'in_progress',
        MaintenanceIssueStatus.resolved => 'resolved',
      };

  String get label => switch (this) {
        MaintenanceIssueStatus.open => 'Open',
        MaintenanceIssueStatus.inProgress => 'In progress',
        MaintenanceIssueStatus.resolved => 'Resolved',
      };
}

class MaintenanceIssue {
  const MaintenanceIssue({
    required this.id,
    required this.title,
    this.area,
    this.description,
    required this.status,
    required this.reportedAt,
    this.resolvedAt,
    this.notes,
  });

  final String id;
  final String title;
  final String? area;
  final String? description;
  final MaintenanceIssueStatus status;
  final DateTime reportedAt;
  final DateTime? resolvedAt;
  final String? notes;

  @override
  bool operator ==(Object other) =>
      other is MaintenanceIssue &&
      other.id == id &&
      other.title == title &&
      other.area == area &&
      other.description == description &&
      other.status == status &&
      other.reportedAt == reportedAt &&
      other.resolvedAt == resolvedAt &&
      other.notes == notes;

  @override
  int get hashCode =>
      Object.hash(id, title, area, description, status, reportedAt, resolvedAt, notes);
}
