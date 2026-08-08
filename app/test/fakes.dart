import 'dart:async';

import 'package:foodiehome/data/auth_gateway.dart';
import 'package:foodiehome/data/household_gateway.dart';
import 'package:foodiehome/domain/household.dart';

class FakeAuthGateway implements AuthGateway {
  // Not an async* generator: listeners must be registered synchronously so an
  // emission between "listen" and a generator's yield* can never be dropped.
  final _listeners = <StreamController<String?>>[];
  String? _userId;

  /// Emails registered via [signUp] (or seeded by tests).
  final Map<String, String> accounts = {};

  @override
  String? get currentUserId => _userId;

  @override
  Stream<String?> authUserIdChanges() {
    late final StreamController<String?> controller;
    controller = StreamController<String?>(
      onListen: () {
        controller.add(_userId);
        _listeners.add(controller);
      },
      onCancel: () => _listeners.remove(controller),
    );
    return controller.stream;
  }

  void _set(String? id) {
    _userId = id;
    for (final controller in List.of(_listeners)) {
      controller.add(id);
    }
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (accounts[email.trim()] != password) {
      throw StateError('invalid credentials');
    }
    _set('user-${email.trim()}');
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    accounts[email.trim()] = password;
    _set('user-${email.trim()}');
  }

  @override
  Future<void> signOut() async => _set(null);
}

class FakeHouseholdGateway implements HouseholdGateway {
  FakeHouseholdGateway({this.knownInviteCode = 'abc123'});

  final String knownInviteCode;
  final List<Household> memberships = [];
  int createCalls = 0;

  @override
  Future<List<Household>> fetchMyHouseholds() async => List.of(memberships);

  @override
  Future<Household> createHousehold(String name) async {
    createCalls++;
    final household = Household(
      id: 'hh-${memberships.length + 1}',
      name: name,
      createdBy: 'creator',
      inviteCode: knownInviteCode,
    );
    memberships.add(household);
    return household;
  }

  @override
  Future<String> redeemInvite(String code) async {
    if (code != knownInviteCode) {
      throw StateError('invalid invite code');
    }
    const joined = Household(
      id: 'hh-joined',
      name: 'Joined household',
      createdBy: 'someone-else',
      inviteCode: 'abc123',
    );
    memberships.add(joined);
    return joined.id;
  }

  @override
  Future<void> leaveHousehold(String householdId) async {
    memberships.removeWhere((h) => h.id == householdId);
  }

  @override
  Future<String> regenerateInviteCode(String householdId) async => 'newcode';
}
