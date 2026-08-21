import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../data/fermentation_gateway.dart';
import '../../data/supabase_fermentation_gateway.dart';
import '../../domain/fermentation.dart';
import '../auth/session.dart';

final fermentationGatewayProvider = Provider<FermentationGateway>(
  (ref) => SupabaseFermentationGateway(Supabase.instance.client),
);

/// Current household's active fermentation projects. Refetches whenever the
/// session changes, and after every mutation — same pattern as
/// InventoryController/CleaningController.
class FermentationController extends AsyncNotifier<List<FermentationProject>> {
  @override
  Future<List<FermentationProject>> build() async {
    final session = await ref.watch(sessionProvider.future);
    if (session is! Ready) return const [];
    return ref.watch(fermentationGatewayProvider).fetchProjects(session.household.id);
  }

  Future<String> _householdId() async {
    final session = await ref.read(sessionProvider.future);
    if (session is! Ready) {
      throw StateError('cannot manage fermentation projects without an active household');
    }
    return session.household.id;
  }

  Future<FermentationProject> createProject({
    required String projectType,
    required String name,
    Map<String, dynamic>? targetParams,
    DateTime? nextCheckAt,
    String? notes,
  }) async {
    final householdId = await _householdId();
    final project = await ref.read(fermentationGatewayProvider).createProject(
          householdId,
          projectType: projectType,
          name: name,
          targetParams: targetParams,
          nextCheckAt: nextCheckAt,
          notes: notes,
        );
    ref.invalidateSelf();
    await future;
    return project;
  }
}

final fermentationControllerProvider =
    AsyncNotifierProvider<FermentationController, List<FermentationProject>>(
        FermentationController.new);

/// One project's full detail (with log history) — a family so each open
/// project screen tracks its own id.
class FermentationProjectController extends AsyncNotifier<FermentationProjectDetail> {
  FermentationProjectController(this.projectId);

  final String projectId;

  @override
  Future<FermentationProjectDetail> build() async {
    final session = await ref.watch(sessionProvider.future);
    if (session is! Ready) {
      throw StateError('cannot load a fermentation project without an active household');
    }
    return ref.watch(fermentationGatewayProvider).fetchProject(session.household.id, projectId);
  }

  Future<String> _householdId() async {
    final session = await ref.read(sessionProvider.future);
    if (session is! Ready) {
      throw StateError('cannot manage this fermentation project without an active household');
    }
    return session.household.id;
  }

  Future<void> logEvent({
    required FermentationLogType logType,
    Map<String, dynamic>? payload,
    String? notes,
  }) async {
    final householdId = await _householdId();
    await ref.read(fermentationGatewayProvider).logEvent(
          householdId,
          projectId,
          logType: logType,
          payload: payload,
          notes: notes,
        );
    ref.invalidateSelf();
    await future;
  }

  Future<void> logSourdoughFeeding({
    required double starterG,
    required double flourG,
    required double waterG,
    String? flourType,
    double? discardG,
    String? notes,
  }) async {
    final householdId = await _householdId();
    await ref.read(fermentationGatewayProvider).logSourdoughFeeding(
          householdId,
          projectId,
          starterG: starterG,
          flourG: flourG,
          waterG: waterG,
          flourType: flourType,
          discardG: discardG,
          notes: notes,
        );
    ref.invalidateSelf();
    await future;
  }

  Future<void> updateStage({
    String? currentStage,
    FermentationStatus? status,
    DateTime? nextCheckAt,
    String? notes,
  }) async {
    final householdId = await _householdId();
    await ref.read(fermentationGatewayProvider).updateStage(
          householdId,
          projectId,
          currentStage: currentStage,
          status: status,
          nextCheckAt: nextCheckAt,
          notes: notes,
        );
    ref.invalidateSelf();
    await future;
    // The project list's cached status may now be stale (e.g. archived).
    ref.invalidate(fermentationControllerProvider);
  }
}

final fermentationProjectControllerProvider = AsyncNotifierProvider.family<
    FermentationProjectController, FermentationProjectDetail, String>(
  FermentationProjectController.new,
);
