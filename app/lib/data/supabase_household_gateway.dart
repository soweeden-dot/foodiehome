import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/household.dart';
import 'household_gateway.dart';

class SupabaseHouseholdGateway implements HouseholdGateway {
  SupabaseHouseholdGateway(this._client);

  final SupabaseClient _client;

  static Household _fromRow(Map<String, dynamic> row) => Household(
        id: row['id'] as String,
        name: row['name'] as String,
        createdBy: row['created_by'] as String,
        inviteCode: row['invite_code'] as String?,
        timezone: (row['timezone'] as String?) ?? 'UTC',
      );

  @override
  Future<List<Household>> fetchMyHouseholds() async {
    final rows = await _client.from('households').select();
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Household> createHousehold(String name) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('cannot create a household while signed out');
    }
    final row = await _client
        .from('households')
        .insert({'name': name.trim(), 'created_by': userId})
        .select()
        .single();
    return _fromRow(row);
  }

  @override
  Future<String> redeemInvite(String code) async {
    final result = await _client.rpc<dynamic>(
      'redeem_household_invite',
      params: {'code': normalizeInviteCode(code)},
    );
    return result as String;
  }

  @override
  Future<void> leaveHousehold(String householdId) async {
    await _client.rpc<dynamic>(
      'leave_household',
      params: {'hh': householdId},
    );
  }

  @override
  Future<String> regenerateInviteCode(String householdId) async {
    final result = await _client.rpc<dynamic>(
      'regenerate_invite_code',
      params: {'hh': householdId},
    );
    return result as String;
  }
}
