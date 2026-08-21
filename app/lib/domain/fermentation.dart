/// Domain models for Fermentation Tracking. Plain immutable Dart, mirroring
/// domain/inventory.dart's pattern. Sourdough and cacao share this exact
/// shape — `projectType`/`logType` are the only specialization, never new
/// fields. See sourdough.dart for the sourdough-specific derived values
/// (hydration, ratio, next-feed-due), computed on demand, never stored.
library;

enum FermentationStatus { planned, active, paused, completed, discarded }

extension FermentationStatusWire on FermentationStatus {
  static FermentationStatus fromWire(String value) => switch (value) {
        'planned' => FermentationStatus.planned,
        'active' => FermentationStatus.active,
        'paused' => FermentationStatus.paused,
        'completed' => FermentationStatus.completed,
        'discarded' => FermentationStatus.discarded,
        _ => throw ArgumentError('unknown fermentation status: $value'),
      };

  String toWire() => switch (this) {
        FermentationStatus.planned => 'planned',
        FermentationStatus.active => 'active',
        FermentationStatus.paused => 'paused',
        FermentationStatus.completed => 'completed',
        FermentationStatus.discarded => 'discarded',
      };

  String get label => switch (this) {
        FermentationStatus.planned => 'Planned',
        FermentationStatus.active => 'Active',
        FermentationStatus.paused => 'Paused',
        FermentationStatus.completed => 'Completed',
        FermentationStatus.discarded => 'Discarded',
      };
}

enum FermentationLogType { observation, feeding, turning, temperature, stageChange, aiObservation }

extension FermentationLogTypeWire on FermentationLogType {
  static FermentationLogType fromWire(String value) => switch (value) {
        'observation' => FermentationLogType.observation,
        'feeding' => FermentationLogType.feeding,
        'turning' => FermentationLogType.turning,
        'temperature' => FermentationLogType.temperature,
        'stage_change' => FermentationLogType.stageChange,
        'ai_observation' => FermentationLogType.aiObservation,
        _ => throw ArgumentError('unknown fermentation log type: $value'),
      };

  String toWire() => switch (this) {
        FermentationLogType.observation => 'observation',
        FermentationLogType.feeding => 'feeding',
        FermentationLogType.turning => 'turning',
        FermentationLogType.temperature => 'temperature',
        FermentationLogType.stageChange => 'stage_change',
        FermentationLogType.aiObservation => 'ai_observation',
      };

  String get label => switch (this) {
        FermentationLogType.observation => 'Observation',
        FermentationLogType.feeding => 'Feeding',
        FermentationLogType.turning => 'Turn/stir',
        FermentationLogType.temperature => 'Temperature',
        FermentationLogType.stageChange => 'Stage change',
        FermentationLogType.aiObservation => 'Foodie observation',
      };
}

class FermentationProject {
  const FermentationProject({
    required this.id,
    required this.projectType,
    required this.name,
    required this.status,
    required this.startedAt,
    this.endedAt,
    this.currentStage,
    this.targetParams = const {},
    this.nextCheckAt,
    this.notes,
  });

  final String id;
  final String projectType;
  final String name;
  final FermentationStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? currentStage;
  final Map<String, dynamic> targetParams;
  final DateTime? nextCheckAt;
  final String? notes;

  bool get isSourdough => projectType == 'sourdough_starter';

  /// Sourdough convenience: 'active' (counter) or 'refrigerated', from
  /// target_params — not a dedicated column (see migration 16).
  String? get sourdoughState => targetParams['state'] as String?;

  int get feedIntervalHours =>
      (targetParams['feed_interval_hours'] as num?)?.toInt() ?? 24;

  @override
  bool operator ==(Object other) =>
      other is FermentationProject &&
      other.id == id &&
      other.projectType == projectType &&
      other.name == name &&
      other.status == status &&
      other.startedAt == startedAt &&
      other.endedAt == endedAt &&
      other.currentStage == currentStage &&
      other.nextCheckAt == nextCheckAt &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(
        id,
        projectType,
        name,
        status,
        startedAt,
        endedAt,
        currentStage,
        nextCheckAt,
        notes,
      );
}

class FermentationLog {
  const FermentationLog({
    required this.id,
    required this.projectId,
    required this.loggedAt,
    required this.logType,
    this.payload = const {},
    this.notes,
    required this.author,
  });

  final String id;
  final String projectId;
  final DateTime loggedAt;
  final FermentationLogType logType;
  final Map<String, dynamic> payload;
  final String? notes;
  final String author;

  double? _numeric(String key) {
    final v = payload[key];
    return v == null ? null : (v as num).toDouble();
  }

  /// Feeding-log convenience accessors — null for any other log type.
  double? get starterG => logType == FermentationLogType.feeding ? _numeric('starterG') : null;
  double? get flourG => logType == FermentationLogType.feeding ? _numeric('flourG') : null;
  double? get waterG => logType == FermentationLogType.feeding ? _numeric('waterG') : null;
  double? get discardG => logType == FermentationLogType.feeding ? _numeric('discardG') : null;
  String? get flourType => logType == FermentationLogType.feeding ? payload['flourType'] as String? : null;

  @override
  bool operator ==(Object other) =>
      other is FermentationLog &&
      other.id == id &&
      other.projectId == projectId &&
      other.loggedAt == loggedAt &&
      other.logType == logType &&
      other.notes == notes &&
      other.author == author;

  @override
  int get hashCode => Object.hash(id, projectId, loggedAt, logType, notes, author);
}

class FermentationProjectDetail {
  const FermentationProjectDetail({required this.project, required this.logs});

  final FermentationProject project;
  final List<FermentationLog> logs;

  /// Most recent feeding log, if any — the basis for next-feed-due.
  FermentationLog? get lastFeeding {
    for (final log in logs) {
      if (log.logType == FermentationLogType.feeding) return log;
    }
    return null;
  }
}
