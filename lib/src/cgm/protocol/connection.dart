import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'auth_session.dart';
import 'ble_transport.dart';
import 'device_info.dart';
import 'glucose.dart';
import '../cgm_connection.dart';
import '../cgm_store.dart';

/// UI-agnostic driver for the full G7 read pipeline: scan → connect → auth
/// (reconnect-or-pair) → stream live EGV + backfill → parse → persist.
///
/// It contains the orchestration that used to live in `_ReaderPageState`
/// (`_start`/`_onControl`), with every UI touch replaced by a callback so the
/// exact same logic can run inside the background foreground-service isolate.
/// Everything it depends on ([BleTransport], [G7AuthSession], [G7GlucoseCodec],
/// [G7DeviceInfo], [CgmStore]) is already widget-free.
///
/// It is the Dexcom G7 implementation of the shared [CgmConnection] contract, so
/// the service isolate can drive it and a `Libre3Connection` interchangeably.
class G7Connection implements CgmConnection {
  G7Connection({
    required this.store,
    required this.serial,
    required this.pairingCode,
    this.onLog,
    this.onReading,
    this.onUpdate,
    this.onConnectionState,
    this.onArchive,
  });

  final CgmStore store;
  final String serial;
  final String pairingCode;

  /// A human-readable handshake/log line (mirrors the old in-app log pane).
  final void Function(String line)? onLog;

  /// The most recent live EGV reading.
  final void Function(CgmReading reading)? onReading;

  /// Fired whenever persisted history/info changed (live EGV or backfill), so
  /// listeners can refresh the notification and signal the UI to reload.
  final void Function()? onUpdate;

  /// Connection up/down transitions.
  final void Function(bool connected)? onConnectionState;

  /// Newly-known readings (epoch-minute → mg/dL), fired alongside every archive
  /// write so a listener can mirror them to the backend.
  final void Function(Map<int, int> byEpochMinute)? onArchive;

  BleTransport? _transport;
  StreamSubscription? _controlSub;
  StreamSubscription? _backfillSub;
  StreamSubscription? _connSub;

  /// Glucose history keyed by seconds-since-session-start (dedupes EGV+backfill).
  final SplayTreeMap<int, int> _byTime = SplayTreeMap();
  CgmReading? _latest;
  final G7DeviceInfo _info = G7DeviceInfo();
  DateTime? _sensorStart;
  bool _backfillAsked = false;
  bool _connecting = false;

  /// Key all cached data is stored under: the user serial, or the sensor's BLE
  /// id when none was entered. Set in [connect] once a device is found.
  String _persistKey = '';

  /// Persisted history is pulled into [_byTime] once so backfill can request
  /// only the gap since our newest known reading (not a fixed 24 h every cycle).
  bool _historyLoaded = false;

  /// Consecutive reconnect cycles that armed autoConnect but never reached
  /// streaming. After [_maxAutoConnectFailures] we scan once to re-discover the
  /// sensor's address (it may have changed), then resume the direct autoConnect
  /// path. Reset to 0 the moment a cycle reaches streaming.
  int _autoConnectFailures = 0;
  static const _maxAutoConnectFailures = 2;

  /// autoConnect to a cold `BluetoothDevice.fromId` only fires once the OS has
  /// SEEN the sensor in THIS process; otherwise it silently never connects — the
  /// "after an app update / service restart, autoConnect is dead" failure. So
  /// the first connect of every process scans (which teaches the OS the
  /// address), and only then do in-process reconnects use autoConnect. A fresh
  /// service isolate resets this, forcing a re-scan before we trust autoConnect.
  bool _scannedThisProcess = false;

  @override
  bool get isConnected => _transport?.device.isConnected ?? false;

  @override
  bool get isConnecting => _connecting;

  /// The cached BLE device id to reconnect to, or null when we must scan first.
  /// Non-null only once we hold BOTH the sensor's session key and its device id
  /// (a known-paired sensor); a fresh pair / swapped sensor returns null so we
  /// discover the new device instead of chasing one that's gone.
  String? get _knownDeviceId {
    final pinKey = serial.isNotEmpty ? serial : (store.resolvedKey ?? '');
    if (pinKey.isEmpty || store.sessionKey(pinKey) == null) {
      return null;
    }
    return store.deviceId(pinKey);
  }

  /// The latest known glucose value (live EGV, else newest history point).
  @override
  int? get latestMgDl =>
      _latest?.glucoseMgDl ??
      (_byTime.isNotEmpty ? _byTime[_byTime.lastKey()] : null);

  /// Trend of the latest live EGV in mg/dL per minute (null if none yet — the
  /// history archive doesn't carry a trend).
  @override
  double? get latestTrendPerMin => _latest?.trendMgDlPerMin;

  /// Total session length reported by the sensor (for the expiry warning).
  @override
  int? get sessionLengthSec => _info.sessionLengthSec;

  /// The G7 connects, delivers, then drops its link every ~5 min, so silence
  /// between deliveries is normal — the watchdog holds a reconnect backoff and
  /// tolerates long gaps before escalating. These are today's proven values.
  @override
  CgmTiming get timing => const CgmTiming(
    staleAfter: Duration(minutes: 12),
    restartAfter: Duration(minutes: 25),
    processRestartAfter: Duration(minutes: 35),
    connectStuckAfter: Duration(minutes: 7),
    reconnectBackoff: Duration(minutes: 3),
    expectsContinuousLink: false,
  );

  void _log(String line) => onLog?.call(line);

  void _addReading(int secs, int mgdl) {
    _byTime[secs] = mgdl;
  }

  /// A new sensor session resets secsSinceStart toward 0 — drop stale history.
  /// Only a LIVE EGV (always the newest reading) can signal this; backfill
  /// records are intentionally in the past, so a >1h-old backfill point after a
  /// long outage must NOT be mistaken for a session reset (it used to wipe the
  /// whole history and leave only the freshly-backfilled gap).
  void _resetIfNewSession(int liveSecs) {
    if (_byTime.isNotEmpty && liveSecs + 3600 < _byTime.lastKey()!) {
      _byTime.clear();
      store.addEvent('new_sensor');
    }
  }

  /// History merge as a live EGV does it (session-reset check, then insert).
  @visibleForTesting
  void ingestLive(int secs, int mgdl) {
    _resetIfNewSession(secs);
    _addReading(secs, mgdl);
  }

  /// History merge as a backfill record does it (insert only, never resets).
  @visibleForTesting
  void ingestBackfill(int secs, int mgdl) => _addReading(secs, mgdl);

  @visibleForTesting
  Map<int, int> get history => _byTime;

  /// Drives the real live control/EGV handler end-to-end (covers the EGV-merge
  /// path the [ingestLive]/[ingestBackfill] shims bypass).
  // ponytail: a low secsSinceStart keeps `end > start` false so no backfill
  // request fires → the throwaway transport is never dereferenced. If backfill
  // gating changes, pass a real transport instead.
  @visibleForTesting
  void handleControlBytes(Uint8List bytes) => _onControl(
    BleTransport(BluetoothDevice.fromId('00:00:00:00:00:00')),
    bytes,
  );

  /// Mirror the ENTIRE in-memory session history into BOTH the permanent,
  /// absolute-time archive (the stats source) AND the backend report queue —
  /// not just freshly-received records. Maps each session-relative key to
  /// wall-clock via [_sensorStart]; both sinks dedup per minute, so
  /// re-publishing the whole day each time is idempotent and cheap.
  ///
  /// Re-offering the whole known window to the backend (not just this connect's
  /// increment) is what makes reporting restart-safe: a fresh service isolate
  /// loses [GlucoseSync]'s in-memory "already sent" set and any pending retry,
  /// so a value left unreported by a transient network failure (e.g. a DNS
  /// "Failed host lookup" while the radio was busy) would otherwise be lost —
  /// gap-based backfill won't re-offer minutes already in the archive. On the
  /// next connect we re-offer everything recent and the server fills the gap.
  /// Without the archive half, the stats were likewise starved to a few points
  /// whenever a fresh backfill didn't get through.
  /// Tolerance around the existing anchor: below it, a candidate is treated as
  /// latency jitter and ignored; above it, as a real session reset / clock jump.
  static const _startDriftTolerance = Duration(minutes: 2);

  /// Fix the wall-clock time of session-second 0 to a STABLE value. Recomputing
  /// `now - secsSinceStart` on every EGV jitters the anchor by the BLE delivery
  /// latency, so the SAME reading lands in a different epoch-minute bucket each
  /// cycle — defeating the archive + backend per-minute dedup and re-POSTing the
  /// whole window every reading. So seed the anchor once (from the persisted
  /// value across isolate restarts) and only move it when the candidate jumps
  /// past [_startDriftTolerance] — a genuine new session or clock change.
  void _anchorSensorStart(int secs) {
    final candidate = DateTime.now().subtract(Duration(seconds: secs));
    final current = _sensorStart ?? store.loadSensorStart(_persistKey);
    final drifted =
        current == null ||
        candidate.difference(current).abs() > _startDriftTolerance;
    _sensorStart = drifted ? candidate : current;
  }

  void _archiveKnown() {
    final start = _sensorStart;
    if (start == null || _byTime.isEmpty) {
      return;
    }
    final out = <DateTime, int>{};
    final byMinute = <int, int>{};
    _byTime.forEach((secs, mgdl) {
      final at = start.add(Duration(seconds: secs));
      out[at] = mgdl;
      byMinute[at.millisecondsSinceEpoch ~/ 60000] = mgdl;
    });
    store.archiveAddAll(out);
    onArchive?.call(byMinute);
  }

  Future<void> _persistReadings() async {
    if (_persistKey.isNotEmpty && _byTime.isNotEmpty) {
      await store.saveReadings(_persistKey, _byTime);
    }
  }

  Future<void> _persistInfo() async {
    if (_persistKey.isNotEmpty && (_info.hasAny || _sensorStart != null)) {
      await store.saveInfo(_persistKey, _info, _sensorStart);
    }
  }

  Future<void> _persistLatest(CgmReading reading) async {
    if (_persistKey.isEmpty) {
      return;
    }
    await store.saveLatest(
      _persistKey,
      mgdl: reading.glucoseMgDl,
      trendTenths: reading.trendTenths,
      state: reading.state,
      secsSinceStart: reading.secsSinceStart,
    );
  }

  /// Scan, connect, authenticate, and begin streaming. Reuses a stored session
  /// key for a fast reconnect, falling back to a full pairing if the sensor
  /// rejects it. Safe to call again after a drop (the watchdog does this).
  @override
  Future<void> connect() async {
    if (_connecting) {
      return;
    }
    _connecting = true;
    await _teardownTransport();
    _backfillAsked = false;

    BleTransport? transport;
    try {
      // Pin to the known sensor once we've paired: with a stored device id we
      // scan for THAT sensor only, so a different nearby G7 can't be picked up
      // and fail key-confirmation against our stored key. The pin is keyed by the
      // serial when given, else by the previously resolved BLE id, so pinning
      // works even when no serial was entered.
      // Steady-state reconnect: arm autoConnect straight to the cached device —
      // NO scan, so the native Android-13+ scanner can't wedge (the cause of the
      // "toggle Bluetooth by hand" outages). Scan only for a fresh pair, or as a
      // fallback to re-discover the address after autoConnect keeps missing (the
      // remoteId may have changed). Mirrors Juggluco's Android-13+ reconnect.
      final knownId = _knownDeviceId;
      // Only autoConnect once we've scanned this process (so the OS has seen the
      // device) and haven't exhausted the failure budget — see [_scannedThisProcess].
      var useAutoConnect =
          knownId != null &&
          _scannedThisProcess &&
          _autoConnectFailures < _maxAutoConnectFailures;
      final BluetoothDevice device;
      if (useAutoConnect) {
        _autoConnectFailures++;
        _log('reconnecting directly to $knownId (autoConnect)…');
        device = BluetoothDevice.fromId(knownId);
      } else {
        _log(knownId == null ? 'scanning for DXCM…' : 'scanning for $knownId…');
        final found = await BleTransport.scanForSensor(
          wantedId: knownId,
          log: _log,
        );
        if (found == null) {
          _log('no sensor found');
          return;
        }
        device = found;
        _scannedThisProcess =
            true; // OS has now seen the device → autoConnect ok
        // Arm autoConnect for THIS connect too, rather than a direct connect.
        // A direct connect has a hard 35 s timeout, but the G7 advertises only
        // for about a second per ~5-min cycle: by the time the scan result is
        // delivered and the bond checked, its window is usually already closed,
        // so the connect dies with 147 GATT_CONNECTION_TIMEOUT and the whole
        // cycle repeats forever. autoConnect has no timeout — the OS holds the
        // request and completes it the moment the sensor next advertises, which
        // is exactly what the steady-state path already relies on. Legal here
        // because the scan we just ran taught the OS this address.
        useAutoConnect = true;
      }

      // The serial is only a cache key, not an auth secret — when none was
      // entered, key everything by the sensor's BLE id so caching still works.
      // Persist it so the UI and future service starts resolve to the same key.
      _persistKey = serial.isNotEmpty ? serial : device.remoteId.str;
      await store.saveResolvedKey(_persistKey);
      // Seed in-memory history from the store so backfill only fetches the gap.
      if (!_historyLoaded && _persistKey.isNotEmpty) {
        _historyLoaded = true;
        _byTime.addAll(store.loadReadings(_persistKey));
      }

      // Fresh pairing needed (no stored session key)? A leftover OS bond from a
      // previous pairing is poison here: the sensor sees an already-bonded phone,
      // reports reconnect-state (statusReply 05 01 01) for our fresh J-PAKE, so
      // run() skips the cert-exchange/PoP/bond — and WITHOUT those the sensor
      // never commits the freshly derived key as its reconnect key. Every later
      // reconnect then key-confirmation-mismatches → re-pair → mismatch → loop.
      // Remove the stale bond first so the sensor does a TRUE fresh pair
      // (statusReply 05 01 02) and commits the new key. Best-effort + Android-only.
      if (store.sessionKey(_persistKey) == null) {
        try {
          final bond = await device.bondState
              .firstWhere((state) => state != BluetoothBondState.bonding)
              .timeout(
                const Duration(seconds: 3),
                onTimeout: () => BluetoothBondState.none,
              );
          if (bond == BluetoothBondState.bonded) {
            _log('removing stale OS bond for a clean fresh pair…');
            await device.removeBond();
          }
        } catch (e) {
          _log('bond removal skipped: $e');
        }
      }

      // One clean attempt per connect(): the G7 rejects rapid in-process
      // reconnects (REMOTE_USER_TERMINATED / CONNECTION_TIMEOUT), so on a
      // handshake failure we tear down and let the 30s watchdog re-scan and retry
      // on the sensor's own advertising schedule (see CgmTaskHandler.onRepeatEvent).
      transport = BleTransport(device);
      await transport.connectAndBind(autoConnect: useAutoConnect, log: _log);
      await _authenticate(transport);
      // Remember which physical sensor this was, so future reconnects pin to it.
      if (_persistKey.isNotEmpty) {
        await store.saveDeviceId(_persistKey, device.remoteId.str);
      }
      _log('session established');

      final boundTransport = transport;
      _controlSub = boundTransport.controlStream.listen(
        (bytes) => _onControl(boundTransport, Uint8List.fromList(bytes)),
      );
      _backfillSub = boundTransport.backfillStream.listen((bytes) {
        final records = G7GlucoseCodec.parseBackfill(Uint8List.fromList(bytes));
        for (final record in records) {
          _addReading(record.secsSinceStart, record.glucoseMgDl);
        }
        if (records.isNotEmpty) {
          _persistReadings();
          _archiveKnown(); // publishes the whole window to stats + backend
          onUpdate?.call();
        }
      });
      _connSub = boundTransport.device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          // Include the disconnect reason/code: a NORMAL G7 drop looks different
          // from an abnormal one (e.g. 19 REMOTE_USER_TERMINATED, 147/8
          // CONNECTION_TIMEOUT) that may leave the sensor not advertising.
          final reason = boundTransport.device.disconnectReason;
          _log(
            'link dropped (reason code=${reason?.code} "${reason?.description}")',
          );
          onConnectionState?.call(false);
        }
      });

      await boundTransport.enableDataChannels(log: _log);
      await boundTransport.writeControl([0x4E]); // current EGV
      // Version is static — only fetch it until we have it, to leave room in the
      // G7's brief reconnect window for the battery/calibration replies below.
      if (_info.firmware == null) {
        await boundTransport.writeControl([0x4A]); // version (fw, sw#, serial)
        await boundTransport.writeControl([
          0x52,
        ]); // extended version (session/warmup, hw, algo)
      }
      await boundTransport.writeControl([0x22]); // battery status
      await boundTransport.writeControl([
        0x32,
      ]); // calibration bounds (read-only)

      _transport = transport;
      transport = null;
      _autoConnectFailures = 0; // this cycle reached streaming — clear fallback
      onConnectionState?.call(true);
      _log('connected — streaming');
      // Bound the permanent archive's size (kept across sensors). Cheap and
      // usually a no-op; off the critical reconnect path so it can't delay it.
      store.archivePrune(const Duration(days: 90));
    } catch (e) {
      _log('ERROR: $e');
      await transport?.dispose();
    } finally {
      _connecting = false;
    }
  }

  /// Reconnect with the stored session key if we have one, else do a full
  /// pairing. The new key is persisted. Throws on handshake failure so the caller
  /// can retry on a fresh link.
  ///
  /// On a DEFINITIVE reconnect rejection (the sensor reset/expired its session so
  /// our stored key no longer matches) the stale key is dropped and we throw —
  /// the watchdog then re-pairs from scratch on the next clean link using the
  /// stored pairing code, with NO user action needed. We deliberately do NOT fall
  /// back to a full pairing on THIS link: a full J-PAKE right after a failed
  /// reconnect is exactly the rapid in-process reconnect the G7 rejects
  /// (REMOTE_USER_TERMINATED / CONNECTION_TIMEOUT), which used to wedge recovery —
  /// every cycle retried the doomed reconnect against the stale key and never
  /// cleared it, so the app never self-healed (only a manual sensor-delete did).
  Future<void> _authenticate(BleTransport transport) async {
    final session = G7AuthSession(
      transport: transport,
      pairingCode: pairingCode,
      log: _log,
    );
    final stored = _persistKey.isEmpty ? null : store.sessionKey(_persistKey);
    if (stored != null) {
      try {
        await session.runReconnect(stored);
        _log('RECONNECTED — no re-pairing needed');
        return;
      } on G7HandshakeException catch (e) {
        // Definitive rejection: key-confirmation mismatched or the sensor is not
        // in reconnect state. Our stored key no longer matches this sensor (its
        // session was reset/expired), so retrying reconnect is futile. Drop the
        // stale key so the next clean connect goes straight to a full pairing
        // (using the stored pairing code, no user action), then tear down and let
        // the watchdog re-pair. We do NOT re-pair on THIS link: a full J-PAKE
        // right after a failed reconnect is the rapid in-process reconnect the G7
        // rejects (REMOTE_USER_TERMINATED / CONNECTION_TIMEOUT).
        _log('reconnect rejected ($e) — clearing stale key, will re-pair');
        if (_persistKey.isNotEmpty) {
          await store.clearSessionKey(_persistKey);
        }
        rethrow;
      } catch (e) {
        // Transient (timeout, dropped link, GATT write error): the key is likely
        // still valid. Keep it and let the watchdog retry reconnect on a fresh
        // link, rather than churning an unnecessary full re-pair.
        _log('reconnect failed ($e) — retrying on next link');
        rethrow;
      }
    }
    final secret = await session.run();
    if (_persistKey.isNotEmpty) {
      await store.saveSessionKey(_persistKey, secret);
    }
  }

  void _onControl(BleTransport transport, Uint8List bytes) {
    // Non-EGV control responses carry device metadata (version/battery).
    if (bytes.isNotEmpty && bytes[0] != 0x4E) {
      if (_info.applyControl(bytes)) {
        _persistInfo();
        onUpdate?.call();
      }
      return;
    }
    final reading = G7GlucoseCodec.parseEgv(bytes);
    if (reading == null) {
      return;
    }
    // The newest reading we already hold, BEFORE adding this EGV — the backfill
    // start point (so we only pull what we missed, not a fixed 24 h).
    final priorMax = _byTime.isEmpty ? null : _byTime.lastKey();
    _latest = reading;
    _anchorSensorStart(reading.secsSinceStart);
    if (reading.glucoseMgDl != null) {
      _resetIfNewSession(reading.secsSinceStart);
      _addReading(reading.secsSinceStart, reading.glucoseMgDl!);
      _persistReadings();
      _persistLatest(
        reading,
      ); // restore the exact headline value on next launch
      // Publish the whole known session history to the permanent archive (stats
      // source) AND the backend queue — not just this point — so seeded/
      // persisted history lands too and a restart can't strand unreported values.
      _archiveKnown();
    }
    _persistInfo(); // keep cached sensorStart fresh
    onReading?.call(reading);
    onUpdate?.call();
    if (!_backfillAsked) {
      _backfillAsked = true;
      _requestBackfill(transport, reading.secsSinceStart, priorMax);
    }
  }

  /// How often to sweep the full last 24 h instead of only the gap-since-newest.
  static const _fullBackfillEvery = Duration(hours: 1);
  DateTime? _lastFullBackfill;

  /// Ask the sensor only for what we're missing. Almost every connect that's
  /// just the gap since [priorMax] (our newest stored reading) — a few points,
  /// and after an outage [priorMax] lags by the outage so the gap covers it.
  /// At most once an hour (and whenever we hold no history yet) we sweep the
  /// full 24 h instead, to repair any interior hole a partial backfill left
  /// behind — otherwise that hole could be orphaned permanently. Duplicates are
  /// deduped by [_byTime], so the overlap is harmless.
  ///
  /// Request immediately: the G7 drops the link within a second of connecting,
  /// so deferring would push the request past the window and it'd never be sent.
  void _requestBackfill(BleTransport transport, int liveSecs, int? priorMax) {
    final end = liveSecs - 60;
    final now = DateTime.now();
    final dueFull =
        _lastFullBackfill == null ||
        now.difference(_lastFullBackfill!) >= _fullBackfillEvery;
    var start = liveSecs - 24 * 3600;
    if (priorMax != null && !dueFull) {
      start = priorMax + 1;
    } else {
      _lastFullBackfill = now;
    }
    if (start < 300) {
      start = 300;
    }
    if (end > start) {
      _log('requesting backfill ${start}s..${end}s');
      transport.requestBackfill(start, end);
    }
  }

  Future<void> _teardownTransport() async {
    await _controlSub?.cancel();
    await _backfillSub?.cancel();
    await _connSub?.cancel();
    _controlSub = _backfillSub = _connSub = null;
    await _transport?.dispose();
    _transport = null;
  }

  @override
  Future<void> dispose() async {
    await _teardownTransport();
    onConnectionState?.call(false);
  }
}
