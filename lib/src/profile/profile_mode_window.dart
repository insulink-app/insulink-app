import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The optional time limit on a settings mode — how long the user picked, and
/// the wall-clock moment that run ends at.
///
/// Shared by silent mode and the battery saver: both are modes you switch on for
/// a while and want back off by themselves. The end is a TIMESTAMP, not a
/// countdown, so a limit survives the app being closed; the window is kept
/// alongside it because the timestamp alone can't say which duration was picked
/// once time has passed (and so that re-arming the same duration is one tap).
class ProfileModeWindow {
  const ProfileModeWindow(this.windowMin, this.until);

  /// No limit: the mode runs until it is switched off.
  const ProfileModeWindow.none() : windowMin = permanent, until = permanent;

  /// Window/end value meaning "no limit". Also the fallback for anything
  /// unparseable, so a mode can never expire by accident.
  static const permanent = 0;

  /// The limited windows the settings UI offers, in minutes.
  static const options = [120, 480];

  /// The picked duration in minutes, or [permanent].
  final int windowMin;

  /// Epoch ms the run ends at, or [permanent].
  final int until;

  bool get lapsed =>
      until != permanent && DateTime.now().millisecondsSinceEpoch >= until;

  /// How much of the run is left; null when unlimited or already lapsed.
  Duration? get remaining {
    if (until == permanent || lapsed) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      until,
    ).difference(DateTime.now());
  }

  /// The same window, running from now — so switching a mode on always gives the
  /// full duration rather than whatever was left of an older run.
  ProfileModeWindow started() => withWindow(windowMin);

  /// A different duration, running from now.
  ProfileModeWindow withWindow(int minutes) {
    if (minutes == permanent) {
      return const ProfileModeWindow(permanent, permanent);
    }
    return ProfileModeWindow(
      minutes,
      DateTime.now().add(Duration(minutes: minutes)).millisecondsSinceEpoch,
    );
  }

  /// The same window, not running — what a mode being switched off stores.
  ProfileModeWindow get stopped => ProfileModeWindow(windowMin, permanent);

  /// Fires when this run lapses, or null when there is nothing to wait for.
  ///
  /// Only the UI isolate needs this, and only so an indicator disappears on
  /// time: [lapsed] already tells every reader the truth without a timer having
  /// fired, which is what makes a limit work across an app restart.
  Timer? expiryTimer(void Function() onLapse) {
    final left = remaining;
    if (left == null) {
      return null;
    }
    return Timer(left, onLapse);
  }

  @override
  bool operator ==(Object other) =>
      other is ProfileModeWindow &&
      other.windowMin == windowMin &&
      other.until == until;

  @override
  int get hashCode => Object.hash(windowMin, until);
}

/// Reads and writes a [ProfileModeWindow] under one setting's own two keys.
///
/// The keys are the same ones [ProfileSettings.collect] puts in the account blob,
/// so a limit follows the user to another device.
class ProfileModeWindowStore {
  const ProfileModeWindowStore(this.windowKey, this.untilKey);

  static const _storage = FlutterSecureStorage();

  final String windowKey;
  final String untilKey;

  Future<ProfileModeWindow> load() async {
    return ProfileModeWindow(await _read(windowKey), await _read(untilKey));
  }

  Future<void> save(ProfileModeWindow window) async {
    await _storage.write(key: windowKey, value: '${window.windowMin}');
    await _storage.write(key: untilKey, value: '${window.until}');
  }

  Future<int> _read(String key) async {
    return int.tryParse(await _storage.read(key: key) ?? '') ??
        ProfileModeWindow.permanent;
  }
}
