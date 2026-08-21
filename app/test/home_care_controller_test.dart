import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiehome/domain/home_care.dart';
import 'package:foodiehome/domain/recurrence.dart';
import 'package:foodiehome/features/auth/session.dart';
import 'package:foodiehome/features/home_care/home_care_controller.dart';

import 'fakes.dart';

void main() {
  late FakeAuthGateway auth;
  late FakeHouseholdGateway households;
  late FakeHomeCareGateway homeCare;
  late ProviderContainer container;

  setUp(() async {
    auth = FakeAuthGateway()..accounts['a@b.c'] = 'pw';
    households = FakeHouseholdGateway();
    homeCare = FakeHomeCareGateway();
    container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(auth),
      householdGatewayProvider.overrideWithValue(households),
      homeCareGatewayProvider.overrideWithValue(homeCare),
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
    final tasks = await container.read(cleaningControllerProvider.future);
    expect(tasks, isEmpty);
  });

  test('completeTask refreshes state with a new lastCompletedOn', () async {
    homeCare.cleaningTasks.add(const CleaningTask(
      id: 'task-1',
      name: 'Clean bathroom',
      area: 'Bathroom',
      recurrence: RecurrenceSummary(
        intervalUnit: RecurrenceIntervalUnit.week,
        intervalCount: 1,
        weekday: 0,
      ),
    ));
    await container.read(cleaningControllerProvider.future);

    await container.read(cleaningControllerProvider.notifier).completeTask('task-1');

    final tasks = await container.read(cleaningControllerProvider.future);
    expect(tasks.single.lastCompletedOn, isNotNull);
  });

  test('skipTask does not change lastCompletedOn', () async {
    homeCare.cleaningTasks.add(const CleaningTask(id: 'task-1', name: 'Vacuum'));
    await container.read(cleaningControllerProvider.future);

    await container.read(cleaningControllerProvider.notifier).skipTask('task-1');

    final tasks = await container.read(cleaningControllerProvider.future);
    expect(tasks.single.lastCompletedOn, isNull);
  });

  test('logReplacement decrements spares and sets lastReplacedOn', () async {
    homeCare.trackedComponents.add(const TrackedComponent(
      id: 'comp-1',
      systemName: 'Kitchen fridge',
      componentName: 'Water filter',
      kind: 'filter',
      replaceIntervalDays: 90,
      sparesCount: 1,
    ));
    await container.read(trackedComponentsControllerProvider.future);

    await container.read(trackedComponentsControllerProvider.notifier).logReplacement('comp-1');

    final components = await container.read(trackedComponentsControllerProvider.future);
    expect(components.single.sparesCount, 0);
    expect(components.single.lastReplacedOn, isNotNull);
  });

  test('reportIssue then resolveIssue moves it to resolved', () async {
    await container.read(maintenanceIssuesControllerProvider.future);
    await container
        .read(maintenanceIssuesControllerProvider.notifier)
        .reportIssue(title: 'Leaky faucet', area: 'Kitchen');

    var issues = await container.read(maintenanceIssuesControllerProvider.future);
    expect(issues.single.status, MaintenanceIssueStatus.open);

    await container
        .read(maintenanceIssuesControllerProvider.notifier)
        .resolveIssue(issues.single.id, notes: 'plumber fixed it');

    issues = await container.read(maintenanceIssuesControllerProvider.future);
    expect(issues.single.status, MaintenanceIssueStatus.resolved);
    expect(issues.single.notes, 'plumber fixed it');
  });

  test('gateway failure surfaces as an error, not a silent no-op', () async {
    homeCare.cleaningTasks.add(const CleaningTask(id: 'task-1', name: 'Vacuum'));
    await container.read(cleaningControllerProvider.future);
    homeCare.failNextCall = StateError('boom');
    await expectLater(
      container.read(cleaningControllerProvider.notifier).completeTask('task-1'),
      throwsStateError,
    );
  });

  test('RecurrenceSummary.label renders human-readable cadence', () {
    expect(
      const RecurrenceSummary(intervalUnit: RecurrenceIntervalUnit.week, intervalCount: 1, weekday: 0)
          .label,
      'every week (Sunday)',
    );
    expect(
      const RecurrenceSummary(intervalUnit: RecurrenceIntervalUnit.month, intervalCount: 3).label,
      'every 3 months',
    );
  });
}
