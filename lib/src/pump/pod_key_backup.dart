import 'package:flutter/foundation.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/pump_sync.dart';

/// TEMPORARY — writes the paired pod's reconnect record to the log at startup,
/// so it can be copied somewhere safe by hand.
///
/// A pod answers only the controller that activated it, and that binding cannot
/// be redone. Normally the account holds a copy, which is what makes an app reset
/// survivable. While that copy is failing, this record exists on exactly one
/// phone, and a factory reset would leave a pod delivering insulin with nothing
/// able to stop it.
///
/// **This prints a cryptographic key to the device log.** That is a deliberate
/// trade for a specific situation, not a good default: logs get collected,
/// shared and kept. Remove this the moment the account copy works again, and do
/// not hand a logcat containing it to anyone.
///
/// **To remove:** delete this file and its one call in `main.dart`.
class PodKeyBackup {
  const PodKeyBackup(this.store);

  final PodStore store;

  /// Prints the record, or says plainly that there is none.
  void printToLog() {
    final record = PumpSync().backupRecord(store);
    if (record == null) {
      debugPrint('pod backup: no pod paired, nothing to save');
      return;
    }
    debugPrint('pod backup: ==== COPY THE LINE BELOW AND KEEP IT SAFE ====');
    debugPrint('pod backup: $record');
    debugPrint('pod backup: ==== end of pod reconnect record ====');
  }
}
