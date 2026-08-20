import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insulink/src/pump/pod_basal_delivery.dart';
import 'package:insulink/src/pump/pod_running_bolus.dart';

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
part 'pod_basal_ledger.dart';
part 'pod_delivery_log.dart';

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
  static const _kLastSeenAt = 'pod.last_seen_at';
  static const _kSuspendedByUs = 'pod.suspended_by_us';
  static const _kBasalRates = 'pod.basal_rates';
  static const _kBasalDelivered = 'pod.basal_delivered';
  static const _kBasalTotal = 'pod.basal_total';
  static const _kBasalHours = 'pod.basal_hours';
  static const _kBasalCountedTo = 'pod.basal_counted_to';
  static const _kTempBasal = 'pod.temp_basal';
  static const _kActivationFacts = 'pod.activation_facts';
  static const _kMessageSequence = 'pod.message_sequence';
  static const _kDeliveryLog = 'pod.delivery_log';
  static const _kRunningBolus = 'pod.running_bolus';
  static const _kPendingBolus = 'pod.pending_bolus';

  /// Roughly two days of 15-minute samples. Past that the oldest are dropped:
  /// insulin history that old is no longer shaping a forecast, and an unbounded
  /// queue in secure storage is its own problem.
  static const int _maxPendingDeliveries = 200;

  /// Hours of basal history kept. A pod lives 80 hours, so this covers its whole
  /// life with room to spare and still bounds what sits in secure storage.
  static const int _maxBasalHours = 120;

  /// One-shot alarm flags, keyed by the pod they belong to so a new pod warns
  /// again. See [podKey].
  static String _kNotified(String podKey, String alarm) =>
      'pod.notified.$alarm.$podKey';

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

  /// Identifies the pod for per-pod flags.
  ///
  /// The activation time, NOT the unique id: that id is derived from the
  /// controller address and is therefore identical for every pod this app ever
  /// activates, so it cannot tell two apart. Two pods are never activated in the
  /// same millisecond.
  String? get podKey {
    final started = activatedAt;
    return started == null ? null : '${started.millisecondsSinceEpoch}';
  }

  /// Whether a one-shot alarm has already fired for the current pod.
  bool alarmNotified(String alarm) {
    final key = podKey;
    return key != null && _cache[_kNotified(key, alarm)] == 'true';
  }

  Future<void> setAlarmNotified(String alarm) async {
    final key = podKey;
    if (key != null) {
      await _set(_kNotified(key, alarm), 'true');
    }
  }

  /// When the app last got a status out of the pod, or null if never.
  DateTime? get lastSeenAt {
    final millis = int.tryParse(_cache[_kLastSeenAt] ?? '');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> markSeen(DateTime moment) =>
      _set(_kLastSeenAt, '${moment.millisecondsSinceEpoch}');

  /// Whether WE stopped the pod, so a suspended pod is not reported as having
  /// stopped on its own. Set when a suspend is sent, cleared when delivery is
  /// programmed again.
  bool get suspendedByUs => _cache[_kSuspendedByUs] == 'true';

  Future<void> setSuspendedByUs(bool value) =>
      _set(_kSuspendedByUs, '$value');

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
      _kLastSeenAt,
      _kSuspendedByUs,
      _kBasalRates,
      _kBasalDelivered,
      _kBasalTotal,
      _kBasalHours,
      _kBasalCountedTo,
      _kTempBasal,
      _kActivationFacts,
      _kMessageSequence,
      _kDeliveryLog,
      _kRunningBolus,
      _kPendingBolus,
    ]) {
      await _remove(key);
    }
    for (final key in _cache.keys.where((key) => key.startsWith('pod.notified.')).toList()) {
      await _remove(key);
    }
  }

  /// The EAP sequence number the NEXT session must use.
  int get nextEapSequence => int.tryParse(_cache[_kEapSequence] ?? '') ?? 1;

  /// The pod command sequence number to continue from.
  int get commandSequence => int.tryParse(_cache[_kCommandSequence] ?? '') ?? 0;

  /// The message-packet sequence number the next session continues from.
  ///
  /// A different counter from [commandSequence], which numbers COMMANDS inside
  /// four bits. This one numbers the packets that carry them, is a byte wide, and
  /// runs across sessions — the pod keeps counting it whether or not a new session
  /// was established in between.
  int get messageSequence => int.tryParse(_cache[_kMessageSequence] ?? '') ?? 0;

  /// Records a completed pairing. Written as one step so a pod is never half
  /// remembered — a stored key without an id, or the reverse, is unusable.
  ///
  /// [resetSessionCounters] starts a NEWLY paired pod's counters from scratch. A
  /// fresh pod has never seen a session or a command, so carrying a previous pod's
  /// numbers over would have it reject the first handshake and demand a
  /// resynchronisation. Left off when restoring a pod that is already running,
  /// whose counters must be preserved exactly.
  Future<void> savePairing({
    required int uniqueId,
    required Uint8List longTermKey,
    required int lotNumber,
    required int podSequenceNumber,
    required DateTime activatedAt,
    int? expiryHours,
    bool resetSessionCounters = false,
  }) async {
    if (resetSessionCounters) {
      await _set(_kEapSequence, '1');
      await _set(_kCommandSequence, '0');
      await _set(_kMessageSequence, '0');
    }
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
    required int messageSequence,
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
    await saveMessageSequence(messageSequence);
    if (bleAddress != null && bleAddress.isNotEmpty) {
      await saveBleAddress(bleAddress);
    }
    await saveBackendPumpId(pumpId);
  }

  Future<void> saveBleAddress(String address) => _set(_kBleAddress, address);

  Future<void> saveActivationStep(String step) => _set(_kActivationStep, step);

  /// Whether the pod finished activating and is running insulin.
  ///
  /// A pod can be PAIRED without being activated: the key is stored the moment it
  /// exists, which is several commands before the pod starts delivering. Such a
  /// pod refuses everything but the activation sequence, answering anything else
  /// with an illegal-command-state NAK, so nothing may poll it.
  bool get isActivated => _cache[_kActivationStep] == 'running';

  /// What the pod reported about itself during activation, as JSON.
  ///
  /// Kept because the commands that produce it are one-shot: a resumed activation
  /// cannot ask a pod that already has its id how many prime pulses it wanted.
  String? get activationFacts => _cache[_kActivationFacts];

  Future<void> saveActivationFacts(String facts) =>
      _set(_kActivationFacts, facts);

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

  /// Persists where the message-packet counter stands, kept inside the byte the
  /// header gives it so a reload continues the same wrap the pod sees.
  Future<void> saveMessageSequence(int sequence) =>
      _set(_kMessageSequence, '${sequence & 0xff}');
}
