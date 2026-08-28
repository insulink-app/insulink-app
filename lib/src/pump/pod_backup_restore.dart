import 'package:flutter/widgets.dart';
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/pump_sync.dart';

/// Moves a pod between the user's account and local storage: adopting one the
/// account was holding after the app lost its own copy, and letting go of one
/// that is finished.
///
/// Kept apart from [PodController] because these are the pump operations that do
/// not talk to a pod at all.
class PodBackupRestore {
  const PodBackupRestore(this.store, {this.sync = const PumpSync()});

  final PodStore store;

  /// How the account is reached. Injectable so the order these steps run in can
  /// be checked without a server, which is what matters here: the id is read
  /// before it is cleared.
  final PumpSync sync;

  /// The pod the account is holding for us, or null if there is none, one is
  /// already paired locally, or it has expired.
  ///
  /// Never offered while a pod is paired locally: adopting a second identity
  /// would silently replace the key to a pod that may still be delivering.
  Future<PodRestore?> availableBackendPod(BuildContext context) async {
    if (store.hasPod) {
      return null;
    }
    final restore = await sync.fetchCurrent(context);
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

  /// Forgets a pod locally AND tells the account it is gone.
  ///
  /// Both, because the account is what offers a pod back after a reinstall: a
  /// pod dropped only locally goes on being suggested at every launch, with the
  /// user having already dealt with it once. Deactivating one, discarding a
  /// half-finished activation and letting go of an unreachable one all left it
  /// in that state.
  ///
  /// The account is told FIRST, because [PodStore.forgetPod] clears the id it is
  /// told by. Best-effort though: a phone with no signal must still be able to
  /// let go of a pod, so a failed call is logged and the local forget happens
  /// anyway. The offer card's own discard is the way back from that, and it is
  /// why that button exists separately.
  Future<void> letGo() async {
    final pumpId = store.backendPumpId;
    if (pumpId != null) {
      await _tellTheAccount(pumpId);
    }
    await store.forgetPod();
  }

  /// Best-effort, and it swallows even a thrown error.
  ///
  /// The two failures fall in opposite directions and only one of them is
  /// recoverable. A pod forgotten locally while the account still holds it is
  /// offered back by the card, so nothing is lost. A pod the app REFUSES to let
  /// go of because a network call threw is the state the user was stuck in, with
  /// no way out at all.
  Future<void> _tellTheAccount(String pumpId) async {
    try {
      await sync.discard(pumpId, null);
    } catch (error) {
      debugPrint('pump sync: discard THREW, letting go locally anyway: $error');
    }
  }
}
