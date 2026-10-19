import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/activity_mode/activity_mode_settings.dart';
import 'package:insulink/src/profile/security/profile_security_state.dart';
import 'package:insulink/src/pump/loop/loop_mode_backup.dart';
import 'package:insulink/src/pump/loop/loop_settings.dart';

/// What a reviewed setting is about, so the confirmation names it in words the
/// user knows instead of storage keys.
enum RemoteSettingsGroup {
  dosing,
  targets,
  automation,
  alarms,
  locks;

  String get labelKey => 'settings_review.group.$name';
}

/// Holds account settings that decide how much insulin is given, or whether an
/// alarm sounds, until the user confirms them on this phone.
///
/// The settings blob can be written by anyone holding the account: the web
/// panel, another phone, or someone who stole a session. Adopting a correction
/// factor, a basal profile or a muted alarm from there unseen would let them
/// change a dose from afar. Everything else is still adopted directly.
class RemoteSettingsReview {
  const RemoteSettingsReview([this._storage = const FlutterSecureStorage()]);

  /// Under no prefix a sign-out keeps, so a held change dies with the session.
  static const String storageKey = 'settings.pending_remote';

  static final Map<String, RemoteSettingsGroup> _groups = {
    for (final key in const [
      'bolus_correction_factor',
      'bolus_carb_factor',
      'bolus_max',
      'bolus_insulin_duration_h',
      'basal_profiles',
    ])
      key: RemoteSettingsGroup.dosing,
    for (final key in const ['glucose_target_low', 'glucose_target_high'])
      key: RemoteSettingsGroup.targets,
    for (final key in [
      ...LoopSettings.all.map((setting) => setting.storageKey),
      ...ActivityModeSettings.all.map((setting) => setting.storageKey),
      ActivityModeSettings.enabled.storageKey,
      LoopModeBackup.key,
    ])
      key: RemoteSettingsGroup.automation,
    for (final key in const [
      'glucose_urgent_low',
      'glucose_low',
      'glucose_high',
      'glucose_urgent_high',
      'notifications',
      'alarm_sound',
      'connection_lost_alert',
      'silent_mode',
      'silent_tones',
      'silent_window_min',
      'silent_until',
      'battery_saver_mode',
      'battery_saver_window_min',
      'battery_saver_until',
    ])
      key: RemoteSettingsGroup.alarms,
    for (final action in GuardedAction.values)
      action.storageKey: RemoteSettingsGroup.locks,
  };

  final FlutterSecureStorage _storage;

  bool isReviewed(String key) => _groups.containsKey(key);

  /// Adds [changes] (storage key to the account's value) to what is held. A
  /// later value for the same key replaces the earlier one.
  Future<void> hold(Map<String, String> changes) async {
    await _write({...await pending(), ...changes});
  }

  Future<Map<String, String>> pending() async {
    final stored = await _storage.read(key: storageKey);
    if (stored == null) {
      return {};
    }
    return (jsonDecode(stored) as Map<String, dynamic>).cast<String, String>();
  }

  /// The groups the held changes touch, in a fixed order.
  Future<List<RemoteSettingsGroup>> groups() async {
    final touched = (await pending()).keys.map((key) => _groups[key]).toSet();
    return RemoteSettingsGroup.values.where(touched.contains).toList();
  }

  /// Writes the held values where the app reads them and forgets them. The
  /// loaders hold every value to its editor's bounds, so even a confirmed
  /// change cannot reach past them.
  Future<void> apply() async {
    for (final entry in (await pending()).entries) {
      await _storage.write(key: entry.key, value: entry.value);
    }
    await discard();
  }

  Future<void> discard() => _storage.delete(key: storageKey);

  Future<void> _write(Map<String, String> held) =>
      _storage.write(key: storageKey, value: jsonEncode(held));
}
