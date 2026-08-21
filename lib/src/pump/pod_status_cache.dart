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

  Future<void> saveLastStatus(PodStatusResponse status, DateTime at) {
    return _set(
      PodStore._kLastStatus,
      jsonEncode({
        'body': base64Encode(status.body),
        'at': at.millisecondsSinceEpoch,
      }),
    );
  }
}
