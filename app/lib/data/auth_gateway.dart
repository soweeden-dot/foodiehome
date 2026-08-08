/// Thin seam over authentication so application logic and tests never touch
/// the Supabase SDK directly. The only implementation today is
/// [SupabaseAuthGateway]; adding Sign in with Apple later means widening this
/// interface, not rewriting callers.
abstract interface class AuthGateway {
  /// Emits the signed-in user id, or null when signed out. Implementations
  /// emit the current value to new listeners.
  Stream<String?> authUserIdChanges();

  String? get currentUserId;

  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  });

  Future<void> signOut();
}
