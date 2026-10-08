import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/pump/pod_store.dart';

/// The automation mode as the account remembers it, so a pod adopted after a
/// reinstall comes back the way it was left.
///
/// A key of its own, apart from `pod.loop_mode`: [ProfileSettings.pull] writes
/// every key it receives straight into storage, so the live mode under its real
/// key would switch on the automation of whichever phone signs in. This copy is
/// only ever read by [LoopSwitch.resumeAfterRestore], at the moment a pod moves
/// to this phone. Written by [PodLoopJournal.saveLoopMode] through the pod
/// store's own storage.
class LoopModeBackup {
  const LoopModeBackup();

  static const String key = 'loop_mode_backup';
  static const _storage = FlutterSecureStorage();

  Future<String> loadRaw() async =>
      await _storage.read(key: key) ?? PodLoopMode.off.name;

  Future<bool> wasEngaged() async =>
      await loadRaw() == PodLoopMode.engaged.name;
}
