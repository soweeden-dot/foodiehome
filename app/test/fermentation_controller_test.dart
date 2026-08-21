import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiehome/domain/fermentation.dart';
import 'package:foodiehome/features/auth/session.dart';
import 'package:foodiehome/features/fermentation/fermentation_controller.dart';

import 'fakes.dart';

void main() {
  late FakeAuthGateway auth;
  late FakeHouseholdGateway households;
  late FakeFermentationGateway fermentation;
  late ProviderContainer container;

  setUp(() async {
    auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    households = FakeHouseholdGateway();
    fermentation = FakeFermentationGateway();
    container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(auth),
      householdGatewayProvider.overrideWithValue(households),
      fermentationGatewayProvider.overrideWithValue(fermentation),
    ]);
    container.listen(sessionProvider, (_, _) {});
    final actions = container.read(sessionActionsProvider);
    await actions.signIn(email: 'a@b.c', password: 'pw');
    await actions.createHousehold('Home');
    await container.pump();
    await container.pump();
    await container.read(sessionProvider.future);
  });

  tearDown(() => container.dispose());

  test('starts empty, no household-scoped call until session is Ready', () async {
    final projects = await container.read(fermentationControllerProvider.future);
    expect(projects, isEmpty);
  });

  test('createProject adds an active project and refreshes the list', () async {
    await container.read(fermentationControllerProvider.future);
    await container.read(fermentationControllerProvider.notifier).createProject(
          projectType: 'sourdough_starter',
          name: 'Rustic Rye',
          targetParams: const {'state': 'active', 'feed_interval_hours': 24},
        );

    final projects = await container.read(fermentationControllerProvider.future);
    expect(projects, hasLength(1));
    expect(projects.single.name, 'Rustic Rye');
    expect(projects.single.isSourdough, isTrue);
  });

  test('logSourdoughFeeding stores raw measurements and appears in project detail', () async {
    final project = await fermentation.createProject(
      'hh-1',
      projectType: 'sourdough_starter',
      name: 'Rustic Rye',
      targetParams: const {'state': 'active', 'feed_interval_hours': 24},
    );
    await container.read(fermentationProjectControllerProvider(project.id).future);

    await container
        .read(fermentationProjectControllerProvider(project.id).notifier)
        .logSourdoughFeeding(starterG: 10, flourG: 50, waterG: 50, flourType: 'rye');

    final detail = await container.read(fermentationProjectControllerProvider(project.id).future);
    expect(detail.logs, hasLength(1));
    expect(detail.logs.single.logType, FermentationLogType.feeding);
    expect(detail.lastFeeding?.starterG, 10);
    expect(detail.lastFeeding?.flourG, 50);
    expect(detail.lastFeeding?.waterG, 50);
  });

  test('logEvent appends a generic event', () async {
    final project = await fermentation.createProject('hh-1', projectType: 'cacao', name: 'Batch 1');
    await container.read(fermentationProjectControllerProvider(project.id).future);

    await container.read(fermentationProjectControllerProvider(project.id).notifier).logEvent(
          logType: FermentationLogType.turning,
          payload: const {'turn_number': 1},
          notes: 'stirred well',
        );

    final detail = await container.read(fermentationProjectControllerProvider(project.id).future);
    expect(detail.logs, hasLength(1));
    expect(detail.logs.single.logType, FermentationLogType.turning);
    expect(detail.logs.single.notes, 'stirred well');
  });

  test('updateStage changes stage/status and records a stage_change log', () async {
    final project = await fermentation.createProject('hh-1', projectType: 'cacao', name: 'Batch 1');
    await container.read(fermentationProjectControllerProvider(project.id).future);

    await container.read(fermentationProjectControllerProvider(project.id).notifier).updateStage(
          currentStage: 'drying',
          status: FermentationStatus.active,
        );

    final detail = await container.read(fermentationProjectControllerProvider(project.id).future);
    expect(detail.project.currentStage, 'drying');
    expect(detail.logs.where((l) => l.logType == FermentationLogType.stageChange), hasLength(1));
  });

  test('updateStage to completed sets endedAt and archives out of the active list', () async {
    final project = await fermentation.createProject('hh-1', projectType: 'cacao', name: 'Batch 1');
    await container.read(fermentationControllerProvider.future);
    await container.read(fermentationProjectControllerProvider(project.id).future);

    await container
        .read(fermentationProjectControllerProvider(project.id).notifier)
        .updateStage(status: FermentationStatus.completed);

    final detail = await container.read(fermentationProjectControllerProvider(project.id).future);
    expect(detail.project.status, FermentationStatus.completed);
    expect(detail.project.endedAt, isNotNull);

    final activeProjects = await container.read(fermentationControllerProvider.future);
    expect(activeProjects, isEmpty); // no longer active
  });

  test('gateway failure surfaces as an error, not a silent no-op', () async {
    await container.read(fermentationControllerProvider.future);
    fermentation.failNextCall = StateError('boom');
    await expectLater(
      container.read(fermentationControllerProvider.notifier).createProject(
            projectType: 'cacao',
            name: 'Batch 1',
          ),
      throwsStateError,
    );
    final projects = await container.read(fermentationControllerProvider.future);
    expect(projects, isEmpty);
  });
}
