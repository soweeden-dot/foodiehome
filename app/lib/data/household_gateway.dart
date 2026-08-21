import '../domain/household.dart';

/// Data access for households and membership. Backed by Supabase (RLS scopes
/// every query; the RPCs are SECURITY DEFINER functions from migration 12).
abstract interface class HouseholdGateway {
  /// Households the current user belongs to (normally 0 or 1).
  Future<List<Household>> fetchMyHouseholds();

  Future<Household> createHousehold(String name);

  /// Redeems an invite code; returns the joined household's id.
  Future<String> redeemInvite(String code);

  Future<void> leaveHousehold(String householdId);

  /// Admins only (enforced server-side). Returns the new code.
  Future<String> regenerateInviteCode(String householdId);

  /// The household roster — display name + role for every member.
  Future<List<HouseholdMember>> fetchMembers(String householdId);
}
