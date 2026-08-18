import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Everything about a paired pod that has to outlive the process.
///
/// Losing any of it means losing the pod: the long-term key cannot be
/// renegotiated without re-activating (which the pod only allows once), and both
/// sequence numbers are counters the pod itself tracks and refuses to repeat. So
/// a write here happens BEFORE the value is used on the wire, never after — a
/// counter that was used but not stored is the one failure mode this store
/// exists to prevent.
///
/// Backed by [FlutterSecureStorage] like [CgmStore], with the same synchronous
/// in-memory cache so the read path never awaits, and the same [reload]
/// requirement across isolates.
class PodStore {
  PodStore(this._storage, this._cache);

  static Future<PodStore> open() async {
    const storage = FlutterSecureStorage();
    final cache = await storage.readAll();
    return PodStore(storage, cache);
  }

  static const _kUniqueId = 'pod.unique_id';
  static const _kLongTermKey = 'pod.ltk';
  static const _kEapSequence = 'pod.eap_sequence';
  static const _kCommandSequence = 'pod.command_sequence';
  static const _kLotNumber = 'pod.lot';
  static const _kPodSequence = 'pod.pod_sequence';
  static const _kActivatedAt = 'pod.activated_at';
  static const _kBleAddress = 'pod.ble_address';
  static const _kActivationStep = 'pod.activation_step';
  static const _kExpiryHours = 'pod.expiry_hours';
  static const _kBackendPumpId = 'pod.backend_pump_id';
  static const _kBackendData = 'pod.backend_synced_data';

  final FlutterSecureStorage _storage;
  final Map<String, String> _cache;

  Future<void> reload() async {
    final all = await _storage.readAll();
    _cache
      ..clear()
      ..addAll(all);
  }

  Future<void> _set(String key, String value) async {
    if (_cache[key] == value) {
      return;
    }
    await _storage.write(key: key, value: value);
    _cache[key] = value;
  }

  Future<void> _remove(String key) async {
    await _storage.delete(key: key);
    _cache.remove(key);
  }

  /// Whether a pod is currently paired to this app.
  bool get hasPod => uniqueId != null && longTermKey != null;

  int? get uniqueId => int.tryParse(_cache[_kUniqueId] ?? '');

  Uint8List? get longTermKey {
    final encoded = _cache[_kLongTermKey];
    if (encoded == null) {
      return null;
    }
    return Uint8List.fromList(base64Decode(encoded));
  }

  int? get lotNumber => int.tryParse(_cache[_kLotNumber] ?? '');

  int? get podSequenceNumber => int.tryParse(_cache[_kPodSequence] ?? '');

  DateTime? get activatedAt {
    final millis = int.tryParse(_cache[_kActivatedAt] ?? '');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// The pod's BLE address, so a reconnect can skip the scan.
  String? get bleAddress => _cache[_kBleAddress];

  /// How far activation got, so an interrupted activation resumes instead of
  /// restarting — restarting would re-send commands the pod already ran.
  String? get activationStep => _cache[_kActivationStep];

  /// The pod's own reported lifetime. Only a fallback default until a pod has
  /// told us its own, which it does when it accepts its id.
  int get expiryHours => int.tryParse(_cache[_kExpiryHours] ?? '') ?? 80;

  /// When the pod runs out, derived from its activation time and its own
  /// reported lifetime.
  DateTime? get expiresAt {
    final started = activatedAt;
    return started?.add(Duration(hours: expiryHours));
  }

  /// The id this pod has in the user's backend account, once it has been
  /// mirrored there. Null means it has not been registered yet.
  String? get backendPumpId => _cache[_kBackendPumpId];

  /// The blob last accepted by the backend, so an unchanged sync is skipped.
  String? get backendSyncedData => _cache[_kBackendData];

  Future<void> saveBackendPumpId(String pumpId) =>
      _set(_kBackendPumpId, pumpId);

  Future<void> saveBackendSyncedData(String data) => _set(_kBackendData, data);

  /// The EAP sequence number the NEXT session must use.
  int get nextEapSequence => int.tryParse(_cache[_kEapSequence] ?? '') ?? 1;

  /// The pod command sequence number to continue from.
  int get commandSequence => int.tryParse(_cache[_kCommandSequence] ?? '') ?? 0;

  /// Records a completed pairing. Written as one step so a pod is never half
  /// remembered — a stored key without an id, or the reverse, is unusable.
  Future<void> savePairing({
    required int uniqueId,
    required Uint8List longTermKey,
    required int lotNumber,
    required int podSequenceNumber,
    required DateTime activatedAt,
    int? expiryHours,
  }) async {
    await _set(_kLongTermKey, base64Encode(longTermKey));
    await _set(_kLotNumber, '$lotNumber');
    await _set(_kPodSequence, '$podSequenceNumber');
    await _set(_kActivatedAt, '${activatedAt.millisecondsSinceEpoch}');
    if (expiryHours != null) {
      await _set(_kExpiryHours, '$expiryHours');
    }
    await _set(_kUniqueId, '$uniqueId');
  }

  /// Adopts a pod the backend was holding for us, after the local copy was lost.
  ///
  /// The counters come back too, and they may be behind what the pod has since
  /// run — the app only mirrors them opportunistically. That is recoverable: a
  /// stale command counter earns one refusal, and a stale session counter earns
  /// one resynchronisation round, both of which the driver already handles. What
  /// is NOT recoverable is a missing key, which is why the key is mirrored the
  /// moment pairing completes rather than lazily.
  Future<void> adoptFromBackend({
    required String pumpId,
    required int uniqueId,
    required Uint8List longTermKey,
    required int lotNumber,
    required int podSequenceNumber,
    required DateTime activatedAt,
    required int expiryHours,
    required int eapSequence,
    required int commandSequence,
    String? bleAddress,
  }) async {
    await savePairing(
      uniqueId: uniqueId,
      longTermKey: longTermKey,
      lotNumber: lotNumber,
      podSequenceNumber: podSequenceNumber,
      activatedAt: activatedAt,
      expiryHours: expiryHours,
    );
    await _set(_kEapSequence, '$eapSequence');
    await saveCommandSequence(commandSequence);
    if (bleAddress != null && bleAddress.isNotEmpty) {
      await saveBleAddress(bleAddress);
    }
    await saveBackendPumpId(pumpId);
  }

  Future<void> saveBleAddress(String address) => _set(_kBleAddress, address);

  Future<void> saveActivationStep(String step) => _set(_kActivationStep, step);

  /// Reserves the EAP sequence number for the session about to be established
  /// and returns it, having already stored the successor.
  ///
  /// Reserving before use is deliberate: if the app dies mid-handshake the
  /// number is treated as spent, which costs one wasted counter value. Storing
  /// it afterwards instead would risk reusing one, which the pod rejects and
  /// which needs a resynchronisation round to recover from.
  Future<int> reserveEapSequence() async {
    final reserved = nextEapSequence;
    await _set(_kEapSequence, '${reserved + 1}');
    return reserved;
  }

  /// Stores the sequence number the pod told us to use after a resynchronisation.
  Future<void> saveSynchronizedEapSequence(int sequence) =>
      _set(_kEapSequence, '$sequence');

  /// Persists where the command counter stands. Called after every command so a
  /// restart does not replay one the pod has already run.
  Future<void> saveCommandSequence(int sequence) =>
      _set(_kCommandSequence, '${sequence & 0x0f}');

  /// Forgets the pod entirely, after it has been deactivated or discarded.
  ///
  /// Only safe once the pod is known to be stopped: dropping the key while a pod
  /// is still delivering leaves insulin running with nothing able to command it.
  Future<void> forgetPod() async {
    for (final key in const [
      _kUniqueId,
      _kLongTermKey,
      _kEapSequence,
      _kCommandSequence,
      _kLotNumber,
      _kPodSequence,
      _kActivatedAt,
      _kBleAddress,
      _kActivationStep,
      _kExpiryHours,
      _kBackendPumpId,
      _kBackendData,
    ]) {
      await _remove(key);
    }
  }
}
