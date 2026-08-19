import 'package:flutter/widgets.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/pump_sync.dart';

/// Adopts a pod the user's account was holding after the app lost its own copy.
///
/// Kept apart from [PodController] because it is the one pump operation that does
/// not talk to a pod at all — it moves credentials from the account into local
/// storage, and only then is there a pod to command.
class PodBackupRestore {
  const PodBackupRestore(this.store);

  final PodStore store;

  /// The pod the account is holding for us, or null if there is none, one is
  /// already paired locally, or it has expired.
  ///
  /// Never offered while a pod is paired locally: adopting a second identity
  /// would silently replace the key to a pod that may still be delivering.
  Future<PodRestore?> availableBackendPod(BuildContext context) async {
    if (store.hasPod) {
      return null;
    }
    final restore = await PumpSync().fetchCurrent(context);
    if (restore == null || restore.isExpired) {
      return null;
    }
    return restore;
  }

  /// Adopts a pod from the account and reads its status to confirm it answers.
  ///
  /// If the pod does not answer, the credentials are KEPT rather than rolled
  /// back: the pod may simply be out of range, and discarding the only key to a
  /// pod that is still on the body is the one outcome worth avoiding.
  Future<void> restoreFromBackend(PodRestore restore) async {
    await store.adoptFromBackend(
      pumpId: restore.pumpId,
      uniqueId: restore.uniqueId,
      longTermKey: restore.longTermKey,
      lotNumber: restore.lotNumber,
      podSequenceNumber: restore.podSequenceNumber,
      activatedAt: restore.activatedAt,
      expiryHours: restore.expiryHours,
      eapSequence: restore.eapSequence,
      commandSequence: restore.commandSequence,
      messageSequence: restore.messageSequence,
      bleAddress: restore.bleAddress,
    );
  }
}
