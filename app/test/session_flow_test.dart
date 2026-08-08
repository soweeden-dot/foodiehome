import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodiehome/domain/household.dart';
import 'package:foodiehome/features/auth/session.dart';

import 'fakes.dart';

void main() {
  late FakeAuthGateway auth;
  late FakeHouseholdGateway households;
  late ProviderContainer container;

  setUp(() {
    auth = FakeAuthGateway();
    households = FakeHouseholdGateway();
    container = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(auth),
      householdGatewayProvider.overrideWithValue(households),
    ]);
    // Keep the stream-backed providers alive for the duration of each test.
    container.listen(sessionProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  Future<SessionState> session() async {
    // Let the auth stream emission cross the async-generator boundary and the
    // resulting provider rebuilds settle before resolving the session.
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    return container.read(sessionProvider.future);
  }

  test('starts signed out', () async {
    expect(await session(), isA<SignedOut>());
  });

  test('sign-in with no household lands on NeedsHousehold', () async {
    auth.accounts['a@b.c'] = 'pw';
    await container.read(sessionActionsProvider).signIn(
        email: 'a@b.c', password: 'pw');
    expect(await session(), isA<NeedsHousehold>());
  });

  test('bad credentials surface and leave the user signed out', () async {
    await expectLater(
      container
          .read(sessionActionsProvider)
          .signIn(email: 'a@b.c', password: 'wrong'),
      throwsStateError,
    );
    expect(await session(), isA<SignedOut>());
  });

  test('creating a household reaches Ready', () async {
    auth.accounts['a@b.c'] = 'pw';
    final actions = container.read(sessionActionsProvider);
    await actions.signIn(email: 'a@b.c', password: 'pw');
    await actions.createHousehold('  Home  ');

    final state = await session();
    expect(state, isA<Ready>());
    expect((state as Ready).household.name, 'Home'); // trimmed
  });

  test('joining via invite code reaches Ready', () async {
    auth.accounts['a@b.c'] = 'pw';
    final actions = container.read(sessionActionsProvider);
    await actions.signIn(email: 'a@b.c', password: 'pw');
    await actions.joinHousehold('  ABC123  '); // normalized to abc123

    final state = await session();
    expect(state, isA<Ready>());
    expect((state as Ready).household.id, 'hh-joined');
  });

  test('empty household name is rejected before hitting the gateway',
      () async {
    final actions = container.read(sessionActionsProvider);
    await expectLater(actions.createHousehold('   '), throwsArgumentError);
    expect(households.createCalls, 0);
  });

  test('empty invite code is rejected before hitting the gateway', () async {
    final actions = container.read(sessionActionsProvider);
    await expectLater(actions.joinHousehold('   '), throwsArgumentError);
  });

  test('sign-out returns to SignedOut', () async {
    auth.accounts['a@b.c'] = 'pw';
    final actions = container.read(sessionActionsProvider);
    await actions.signIn(email: 'a@b.c', password: 'pw');
    await actions.createHousehold('Home');
    await actions.signOut();
    expect(await session(), isA<SignedOut>());
  });

  test('existing signed-in session with household resolves straight to Ready',
      () async {
    auth.accounts['a@b.c'] = 'pw';
    await container
        .read(sessionActionsProvider)
        .signIn(email: 'a@b.c', password: 'pw');
    await container.read(sessionActionsProvider).createHousehold('Home');

    // A fresh container simulates app relaunch with a persisted session.
    final relaunch = ProviderContainer(overrides: [
      authGatewayProvider.overrideWithValue(auth),
      householdGatewayProvider.overrideWithValue(households),
    ]);
    addTearDown(relaunch.dispose);
    relaunch.listen(sessionProvider, (_, _) {});
    await relaunch.pump();
    expect(await relaunch.read(sessionProvider.future), isA<Ready>());
  });

  test('invite code normalization', () {
    expect(normalizeInviteCode('  AbC123  '), 'abc123');
    expect(normalizeInviteCode('abc123'), 'abc123');
    expect(normalizeInviteCode('   '), '');
  });
}
