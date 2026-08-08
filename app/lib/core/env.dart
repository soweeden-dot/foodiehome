/// Build-time configuration, injected with --dart-define:
///
///   flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///               --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
///
/// The publishable key is designed to be public (RLS is the security
/// boundary); it still stays out of source control as a matter of hygiene.
/// SUPABASE_ANON_KEY is accepted as a fallback for legacy-format projects.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const _publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const supabaseKey =
      _publishableKey != '' ? _publishableKey : _anonKey;

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
