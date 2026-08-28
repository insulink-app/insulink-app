import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/profile/basal/basal_profile.dart';

/// The user's basal-rate profiles for the Omnipod. Holds several named
/// [BasalProfile]s and which one is [active]; the active profile's hourly rates
/// are what the pod would deliver. Persisted as a single JSON blob and synced
/// with the account settings.
///
/// Provided above the page tree (see `main.dart`) so the profile page observes
/// it.
class ProfileBasalState extends ChangeNotifier {
  static const _key = 'basal_profiles';
  static const _legacyKey = 'basal_profile';

  final List<BasalProfile> _profiles;
  int _activeIndex;

  ProfileBasalState(this._profiles, this._activeIndex);

  List<BasalProfile> get profiles => List<BasalProfile>.unmodifiable(_profiles);
  int get activeIndex => _activeIndex;
  BasalProfile get active => _profiles[_activeIndex];

  static const _storage = FlutterSecureStorage();

  void selectActive(int index) {
    if (index < 0 || index >= _profiles.length || index == _activeIndex) {
      return;
    }
    _activeIndex = index;
    _commit();
  }

  /// Adds a fresh default profile and makes it active; returns its index.
  int addProfile(String name) {
    _profiles.add(BasalProfile.initial(name));
    _activeIndex = _profiles.length - 1;
    _commit();
    return _activeIndex;
  }

  /// Adds a ready-made profile and leaves the active one alone.
  ///
  /// For the weekly suggestion, which must never switch anyone's basal by
  /// appearing. It lands beside the others as something to look at, and becomes
  /// real only when a person picks it.
  int addInactiveProfile(BasalProfile profile) {
    _profiles.add(profile);
    _commit();
    return _profiles.length - 1;
  }

  void deleteProfile(int index) {
    if (_profiles.length <= 1) {
      return;
    }
    _profiles.removeAt(index);
    if (_activeIndex >= _profiles.length) {
      _activeIndex = _profiles.length - 1;
    }
    _commit();
  }

  /// Replaces a profile with an edited copy (from the editor).
  void updateProfile(int index, BasalProfile profile) {
    _profiles[index] = profile;
    _commit();
  }

  void _commit() {
    notifyListeners();
    _storage.write(key: _key, value: _encode());
  }

  String _encode() => jsonEncode({
    'active': _activeIndex,
    'profiles': _profiles.map((profile) => profile.toJson()).toList(),
  });

  // ---- Persistence ----

  static Future<ProfileBasalState> load() async {
    final all = await _storage.readAll();
    final raw = all[_key];
    if (raw != null && raw.isNotEmpty) {
      return _decode(raw);
    }
    return _migrate(all[_legacyKey]);
  }

  static ProfileBasalState _decode(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final profiles = (map['profiles'] as List)
        .map((p) => BasalProfile.fromJson(p as Map<String, dynamic>))
        .toList();
    if (profiles.isEmpty) {
      return _fresh();
    }
    final active = (map['active'] as num?)?.toInt() ?? 0;
    return ProfileBasalState(profiles, active.clamp(0, profiles.length - 1));
  }

  /// One-time upgrade from the old single comma-joined-rates key.
  static ProfileBasalState _migrate(String? legacy) {
    if (legacy == null || legacy.isEmpty) {
      return _fresh();
    }
    final rates = legacy
        .split(',')
        .map((s) => double.tryParse(s) ?? 0.0)
        .toList();
    if (rates.length != 24) {
      return _fresh();
    }
    final profile = BasalProfile.initial('Standard')..rates.setAll(0, rates);
    return ProfileBasalState([profile], 0);
  }

  static ProfileBasalState _fresh() =>
      ProfileBasalState([BasalProfile.initial('Standard')], 0);

  /// The persisted JSON blob (for backend settings sync).
  static Future<String> loadRaw() async {
    final raw = await _storage.read(key: _key);
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }
    return (await load())._encode();
  }
}
