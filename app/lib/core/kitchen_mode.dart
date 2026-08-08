/// Kitchen Device Mode — a DEVICE-LOCAL UI preference.
///
/// Storage decision (documented in ARCHITECTURE.md §"Kitchen Device Mode"):
/// the flag lives in this installation's SharedPreferences
/// (NSUserDefaults on iOS), NOT in the household database, and is never
/// synced. Enabling it on the kitchen iPad therefore cannot affect the
/// iPhone or any other device. It is presentation-only: it changes the
/// shell layout, never identity, auth, or data access — RLS and session
/// handling are untouched by it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Seam over device-local storage so tests can fake per-device stores.
abstract interface class DeviceKeyValueStore {
  Future<bool?> getBool(String key);
  Future<void> setBool(String key, bool value);
}

class SharedPreferencesStore implements DeviceKeyValueStore {
  @override
  Future<bool?> getBool(String key) async =>
      (await SharedPreferences.getInstance()).getBool(key);

  @override
  Future<void> setBool(String key, bool value) async =>
      (await SharedPreferences.getInstance()).setBool(key, value);
}

final deviceStoreProvider =
    Provider<DeviceKeyValueStore>((ref) => SharedPreferencesStore());

const _kitchenModeKey = 'device.kitchen_mode';

/// Whether THIS device is in Kitchen Mode. Loads from device storage once;
/// toggles persist immediately.
class KitchenModeController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async =>
      await ref.watch(deviceStoreProvider).getBool(_kitchenModeKey) ?? false;

  Future<void> setEnabled(bool enabled) async {
    state = AsyncData(enabled);
    await ref.read(deviceStoreProvider).setBool(_kitchenModeKey, enabled);
  }
}

final kitchenModeProvider =
    AsyncNotifierProvider<KitchenModeController, bool>(KitchenModeController.new);
