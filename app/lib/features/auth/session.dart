import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../data/auth_gateway.dart';
import '../../data/household_gateway.dart';
import '../../data/supabase_auth_gateway.dart';
import '../../data/supabase_household_gateway.dart';
import '../../domain/household.dart';

/// Gateway providers — the composition root. Tests override these with fakes;
/// production resolves them against the initialized Supabase client.
final authGatewayProvider = Provider<AuthGateway>(
  (ref) => SupabaseAuthGateway(Supabase.instance.client),
);

final householdGatewayProvider = Provider<HouseholdGateway>(
  (ref) => SupabaseHouseholdGateway(Supabase.instance.client),
);

/// Where the user is in the auth/household flow. The root widget switches on
/// this — it is the single source of truth for "which screen".
sealed class SessionState {
  const SessionState();
}

class SignedOut extends SessionState {
  const SignedOut();
}

/// Signed in, but not a member of any household yet: show create/join.
class NeedsHousehold extends SessionState {
  const NeedsHousehold(this.userId);
  final String userId;
}

class Ready extends SessionState {
  const Ready(this.userId, this.household);
  final String userId;
  final Household household;
}

final authUserIdProvider = StreamProvider<String?>(
  (ref) => ref.watch(authGatewayProvider).authUserIdChanges(),
);

final sessionProvider = FutureProvider<SessionState>((ref) async {
  // Await the first auth emission — reading valueOrNull while the stream is
  // still loading would misreport a persisted session as signed out.
  final userId = await ref.watch(authUserIdProvider.future);
  if (userId == null) return const SignedOut();

  final households =
      await ref.watch(householdGatewayProvider).fetchMyHouseholds();
  if (households.isEmpty) return NeedsHousehold(userId);
  // Multiple memberships are possible in the model but not in this
  // household's reality; the first is fine until a picker is ever needed.
  return Ready(userId, households.first);
});

/// Imperative auth/household actions used by the provisional screens.
/// Mutations invalidate [sessionProvider] so the flow re-resolves.
final sessionActionsProvider = Provider<SessionActions>(SessionActions.new);

class SessionActions {
  SessionActions(this._ref);

  final Ref _ref;

  AuthGateway get _auth => _ref.read(authGatewayProvider);
  HouseholdGateway get _households => _ref.read(householdGatewayProvider);

  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithPassword(email: email, password: password);
    _ref.invalidate(sessionProvider);
  }

  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    await _auth.signUp(
        email: email, password: password, displayName: displayName);
    _ref.invalidate(sessionProvider);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _ref.invalidate(sessionProvider);
  }

  Future<void> createHousehold(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('household name cannot be empty');
    }
    await _households.createHousehold(trimmed);
    _ref.invalidate(sessionProvider);
  }

  Future<void> joinHousehold(String inviteCode) async {
    final code = normalizeInviteCode(inviteCode);
    if (code.isEmpty) {
      throw ArgumentError('invite code cannot be empty');
    }
    await _households.redeemInvite(code);
    _ref.invalidate(sessionProvider);
  }
}
