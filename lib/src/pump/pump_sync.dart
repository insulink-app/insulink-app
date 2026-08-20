import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' show Response;
import 'package:insulink/src/pump/pod_store.dart';
import 'package:insulink/src/pump/protocol/pod_responses.dart';
import 'package:insulink/src/request/request.dart';
import 'package:insulink/src/request/response_json.dart';

/// Mirrors the paired pod to the user's backend account, so a reinstall or a
/// factory reset does not strand a pod that is still on the body.
///
/// This matters more here than it does for a sensor. A pod answers only to the
/// controller that activated it, and that binding cannot be redone — so losing
/// the long-term key locally means losing the ability to stop a pod that is
/// still delivering insulin. The key is therefore pushed the moment pairing
/// completes, not lazily.
///
/// Mirrors [SensorSync] deliberately: same register/update split, same opaque
/// blob the server never interprets, same best-effort behaviour (a failed sync
/// is retried on the next call and never blocks pump operation).
class PumpSync {
  /// The pump type key the backend's `PumpType` enum expects.
  static const String _backendType = 'OMNIPOD_DASH';

  /// Registers the pod the first time and refreshes the blob when it changes.
  ///
  /// Cheap and idempotent: the blob is compared against what the backend last
  /// accepted, so an unchanged pod costs nothing.
  ///
  /// Returns whether the account now holds the current blob. Callers that mirror
  /// the KEY have to look at that: this is the only copy of a credential that
  /// cannot be renegotiated, and a silent failure here is the difference between
  /// a recoverable app reset and a pod nobody can ever stop.
  Future<bool> sync(PodStore store, {PodStatusResponse? status}) async {
    final data = _data(store, status);
    if (data == null) {
      debugPrint('pump sync: nothing to mirror, no pod fully paired');
      return false;
    }
    final pumpId = store.backendPumpId;
    if (pumpId == null) {
      return _register(store, data);
    }
    if (store.backendSyncedData == data) {
      return true;
    }
    return _update(store, pumpId, data);
  }

  /// The reconnect identity, or null while no pod is fully paired.
  ///
  /// When a fresh [PodStatusResponse] is at hand it also carries the last thing
  /// the pod said about itself, so the panel can show a pod's reservoir and state
  /// as of the last contact. Those fields are a snapshot, never a live reading —
  /// they are only as fresh as the last time the app spoke to the pod.
  ///
  /// All three counters are included so a restored app resumes near where it left
  /// off. They are only as fresh as the last sync — see [PodStore.adoptFromBackend]
  /// for why being behind is recoverable and being keyless is not.
  String? _data(PodStore store, PodStatusResponse? status) {
    final uniqueId = store.uniqueId;
    final longTermKey = store.longTermKey;
    final activatedAt = store.activatedAt;
    if (uniqueId == null || longTermKey == null || activatedAt == null) {
      return null;
    }
    return jsonEncode({
      'pump_type': _backendType,
      'unique_id': uniqueId,
      'long_term_key': base64Encode(longTermKey),
      'lot_number': store.lotNumber,
      'pod_sequence_number': store.podSequenceNumber,
      'activated_at': activatedAt.millisecondsSinceEpoch,
      'expiry_hours': store.expiryHours,
      'eap_sequence': store.nextEapSequence,
      'command_sequence': store.commandSequence,
      'message_sequence': store.messageSequence,
      if (store.bleAddress != null) 'ble_address': store.bleAddress,
      if (status != null) ...{
        'last_seen_at': DateTime.now().millisecondsSinceEpoch,
        'last_lifecycle': status.lifecycle.name,
        if (status.reservoirUnits != null)
          'reservoir_units': status.reservoirUnits,
        'total_delivered_units': status.totalUnitsDelivered,
      },
    });
  }

  /// Epoch-ms the pod expires, so the stored record ages out with the pod it
  /// describes instead of lingering as a usable key forever.
  int _expiresAt(PodStore store) {
    final expires = store.expiresAt;
    if (expires != null) {
      return expires.millisecondsSinceEpoch;
    }
    return DateTime.now()
        .add(Duration(hours: store.expiryHours))
        .millisecondsSinceEpoch;
  }

  Future<bool> _register(PodStore store, String data) async {
    final response = await Request.post(
      url: '/pump/register/',
      body: {
        'type': _backendType,
        'data': data,
        'expires_at': _expiresAt(store),
      },
    ).send(null);
    if (!_isSuccess(response)) {
      debugPrint('pump sync: register REJECTED, ${_describe(response)}');
      return false;
    }
    final id = response.jsonObject?['pump_id'];
    if (id == null) {
      debugPrint('pump sync: register returned no pump_id');
      return false;
    }
    await store.saveBackendPumpId('$id');
    await store.saveBackendSyncedData(data);
    debugPrint('pump sync: registered as pump $id');
    return true;
  }

  Future<bool> _update(PodStore store, String pumpId, String data) async {
    final response = await Request.post(
      url: '/pump/update/',
      body: {'pump_id': pumpId, 'data': data},
    ).send(null);
    if (!_isSuccess(response)) {
      debugPrint('pump sync: update REJECTED, ${_describe(response)}');
      return false;
    }
    await store.saveBackendSyncedData(data);
    debugPrint('pump sync: updated pump $pumpId');
    return true;
  }

  /// Makes sure the account holds this pod, catching up if it never did.
  ///
  /// The ordinary mirror only runs off a successful pod operation, so a pod that
  /// is paired but not yet activated is never pushed: the background watch skips
  /// it and the activation has not reached its end. That left the only copy of an
  /// unrecoverable key on one phone.
  ///
  /// Duplicate-safe. A registration whose reply was lost would otherwise be
  /// repeated, so the account is ASKED first: a pod already on file with our id
  /// is adopted by its existing id rather than registered a second time.
  Future<bool> ensureMirrored(PodStore store, {BuildContext? context}) async {
    if (!store.hasPod || store.backendPumpId != null) {
      return store.backendPumpId != null;
    }
    final onFile = await fetchCurrent(context);
    if (onFile != null && onFile.uniqueId == store.uniqueId) {
      debugPrint('pump sync: account already holds this pod, adopting '
          '${onFile.pumpId} instead of registering again');
      await store.saveBackendPumpId(onFile.pumpId);
      return sync(store);
    }
    debugPrint('pump sync: account has no copy of this pod, registering');
    return sync(store);
  }

  /// The account's current pod as a restorable identity, or null if there is
  /// none, it has expired, or the response was malformed. Call from the UI
  /// isolate, where an expired token can still be refreshed.
  Future<PodRestore?> fetchCurrent(BuildContext? context) async {
    final response = await Request.get(url: '/pump/current/').send(context);
    if (!_isSuccess(response)) {
      return null;
    }
    final body = response.jsonObject;
    if (body == null) {
      return null;
    }
    final id = body['id'];
    final data = body['data'];
    if (id == null || data is! String) {
      return null;
    }
    try {
      return PodRestore.fromBlob('$id', jsonDecode(data) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// What came back, for a log line. A silent rejection is the one thing this
  /// path must never produce.
  String _describe(Response? response) {
    if (response == null) {
      return 'no response (offline, or the API is unreachable)';
    }
    final body = response.body;
    final shown = body.length > 200 ? '${body.substring(0, 200)}…' : body;
    return 'status ${response.statusCode}, body: $shown';
  }

  bool _isSuccess(Response? response) => response.isApiSuccess;
}

/// A backend pod decoded into what the local store needs to adopt it.
class PodRestore {
  const PodRestore({
    required this.pumpId,
    required this.uniqueId,
    required this.longTermKey,
    required this.lotNumber,
    required this.podSequenceNumber,
    required this.activatedAt,
    required this.expiryHours,
    required this.eapSequence,
    required this.commandSequence,
    required this.messageSequence,
    this.bleAddress,
  });

  /// Reads a stored blob. Throws if a field the reconnect cannot do without is
  /// missing, so a malformed record is refused rather than adopted half-way.
  factory PodRestore.fromBlob(String pumpId, Map<String, dynamic> blob) {
    return PodRestore(
      pumpId: pumpId,
      uniqueId: (blob['unique_id'] as num).toInt(),
      longTermKey: Uint8List.fromList(
        base64Decode(blob['long_term_key'] as String),
      ),
      lotNumber: (blob['lot_number'] as num?)?.toInt() ?? 0,
      podSequenceNumber: (blob['pod_sequence_number'] as num?)?.toInt() ?? 0,
      activatedAt: DateTime.fromMillisecondsSinceEpoch(
        (blob['activated_at'] as num).toInt(),
      ),
      expiryHours: (blob['expiry_hours'] as num?)?.toInt() ?? 80,
      eapSequence: (blob['eap_sequence'] as num?)?.toInt() ?? 1,
      commandSequence: (blob['command_sequence'] as num?)?.toInt() ?? 0,
      messageSequence: (blob['message_sequence'] as num?)?.toInt() ?? 0,
      bleAddress: blob['ble_address'] as String?,
    );
  }

  final String pumpId;
  final int uniqueId;
  final Uint8List longTermKey;
  final int lotNumber;
  final int podSequenceNumber;
  final DateTime activatedAt;
  final int expiryHours;
  final int eapSequence;
  final int commandSequence;
  final int messageSequence;
  final String? bleAddress;

  DateTime get expiresAt => activatedAt.add(Duration(hours: expiryHours));

  /// Whether the pod this describes has already run past its life, in which case
  /// it cannot be reconnected and should not be offered.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get remaining => expiresAt.difference(DateTime.now());
}
