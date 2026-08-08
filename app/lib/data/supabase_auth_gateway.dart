import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gateway.dart';

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._client);

  final SupabaseClient _client;

  @override
  Stream<String?> authUserIdChanges() async* {
    yield currentUserId;
    yield* _client.auth.onAuthStateChange
        .map((event) => event.session?.user.id);
  }

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email.trim(), password: password);
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        // Picked up by the handle_new_auth_user trigger for the profile row.
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
      },
    );
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
