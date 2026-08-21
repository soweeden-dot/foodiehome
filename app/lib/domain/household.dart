/// Domain model for a household. Plain immutable Dart, independent of the
/// Supabase row shape (mapping happens in the data layer).
class Household {
  const Household({
    required this.id,
    required this.name,
    required this.createdBy,
    this.inviteCode,
    this.timezone = 'UTC',
  });

  final String id;
  final String name;
  final String createdBy;

  /// Only visible to members (RLS); null when not loaded.
  final String? inviteCode;
  final String timezone;

  @override
  bool operator ==(Object other) =>
      other is Household &&
      other.id == id &&
      other.name == name &&
      other.createdBy == createdBy &&
      other.inviteCode == inviteCode &&
      other.timezone == timezone;

  @override
  int get hashCode => Object.hash(id, name, createdBy, inviteCode, timezone);
}

/// Invite codes are stored lowercase server-side; normalize what users type
/// (whitespace, case) before sending. Server-side redemption normalizes too —
/// this is UX, not enforcement.
String normalizeInviteCode(String raw) => raw.trim().toLowerCase();

/// One row of the household roster — display name + role. Membership UX
/// only; management (invite/remove) stays out of scope for now.
class HouseholdMember {
  const HouseholdMember({required this.displayName, required this.isAdmin});

  final String displayName;
  final bool isAdmin;

  @override
  bool operator ==(Object other) =>
      other is HouseholdMember &&
      other.displayName == displayName &&
      other.isAdmin == isAdmin;

  @override
  int get hashCode => Object.hash(displayName, isAdmin);
}
