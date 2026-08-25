part of 'pod_store.dart';

/// The last status the pod gave anyone, and when.
///
/// Two jobs, and both matter more than they look:
///
///  * **The pump page opens on something.** Without it, every visit began with an
///    empty page and a BLE session, several seconds of a spinner before the page
///    could say whether the pod was even delivering. The cached one is shown at
///    once with its age, and a read only happens when it has actually gone stale.
///  * **The automation can decide while switched off.** Its decision needs the
///    pod's state, and a cycle that only wanted to WRITE DOWN what it would have
///    done should not be opening a radio link every five minutes to do it.
///
/// Written by whichever isolate last read the pod, so the UI benefits from the
/// background poll and the background poll benefits from the UI.
///
/// The raw frame is stored rather than the decoded fields: one decoder, no second
/// one to drift from it.
extension PodStatusCache on PodStore {
  PodStatusResponse? get lastStatus {
    final encoded = _cache[PodStore._kLastStatus];
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      final held = jsonDecode(encoded) as Map<String, dynamic>;
      return PodStatusResponse(base64Decode(held['body'] as String));
    } on FormatException {
      return null;
    } on PodResponseException {
      return null;
    }
  }

  /// When [lastStatus] was read, or null when none has been.
  DateTime? get lastStatusAt {
    final encoded = _cache[PodStore._kLastStatus];
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      final held = jsonDecode(encoded) as Map<String, dynamic>;
      return DateTime.fromMillisecondsSinceEpoch((held['at'] as num).toInt());
    } on FormatException {
      return null;
    }
  }

  /// Stores a status, and takes the pod's own word for whether it is running.
  ///
  /// [PodStore.isActivated] used to rest on a purely local note of how far the
  /// activation wizard got. That note is not part of the pod: a reinstall wipes
  /// it, and [PodStore.adoptFromBackend] restores every credential without it. So
  /// a pod that had been delivering for a day came back as "paired, activation
  /// unfinished" — and everything hangs off that flag, so the pump page offered
  /// to resume the wizard while the status poll, the background watch and the
  /// loop all stood down for a pod that was working perfectly.
  ///
  /// The pod is the authority on this, and every reply it gives passes through
  /// here. A lifecycle it reports as running IS an activation that finished,
  /// whichever install of the app finished it.
  ///
  /// One-directional on purpose: a pod that stops running is not un-activated.
  /// That is a pod change, and it goes through [PodStore.forgetPod].
  Future<void> saveLastStatus(PodStatusResponse status, DateTime at) async {
    if (status.lifecycle.isRunning && !isActivated) {
      await saveActivationStep(PodActivationStep.running.name);
    }
    await _set(
      PodStore._kLastStatus,
      jsonEncode({
        'body': base64Encode(status.body),
        'at': at.millisecondsSinceEpoch,
      }),
    );
  }
}
