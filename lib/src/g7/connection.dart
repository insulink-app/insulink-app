import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'auth_session.dart';
import 'ble_transport.dart';
import 'device_info.dart';
import 'glucose.dart';
import 'store.dart';

/// UI-agnostic driver for the full G7 read pipeline: scan → connect → auth
/// (reconnect-or-pair) → stream live EGV + backfill → parse → persist.
///
/// It contains the orchestration that used to live in `_ReaderPageState`
/// (`_start`/`_onControl`), with every UI touch replaced by a callback so the
/// exact same logic can run inside the background foreground-service isolate.
/// Everything it depends on ([BleTransport], [G7AuthSession], [G7GlucoseCodec],
/// [G7DeviceInfo], [G7Store]) is already widget-free.
class G7Connection {
  G7Connection({
    required this.store,
    required this.serial,
    required this.pairingCode,
    this.onLog,
    this.onReading,
    this.onUpdate,
    this.onConnectionState,
  });

  final G7Store store;
  final String serial;
  final String pairingCode;

  /// A human-readable handshake/log line (mirrors the old in-app log pane).
  final void Function(String line)? onLog;

  /// The most recent live EGV reading.
  final void Function(G7GlucoseReading reading)? onReading;

  /// Fired whenever persisted history/info changed (live EGV or backfill), so
  /// listeners can refresh the notification and signal the UI to reload.
  final void Function()? onUpdate;

  /// Connection up/down transitions.
  final void Function(bool connected)? onConnectionState;

  BleTransport? _transport;
  StreamSubscription? _controlSub;
  StreamSubscription? _backfillSub;
  StreamSubscription? _connSub;

  /// Glucose history keyed by seconds-since-session-start (dedupes EGV+backfill).
  final SplayTreeMap<int, int> _byTime = SplayTreeMap();
  G7GlucoseReading? _latest;
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

  bool get isConnected => _transport?.device.isConnected ?? false;

  bool get isConnecting => _connecting;

  /// The latest known glucose value (live EGV, else newest history point).
  int? get latestMgDl =>
      _latest?.glucoseMgDl ??
      (_byTime.isNotEmpty ? _byTime[_byTime.lastKey()] : null);

  /// Total session length reported by the sensor (for the expiry warning).
  int? get sessionLengthSec => _info.sessionLengthSec;

  void _log(String s) => onLog?.call(s);

  void _addReading(int secs, int mgdl) {
    // A new sensor session resets secsSinceStart toward 0 — drop stale history.
    if (_byTime.isNotEmpty && secs + 3600 < _byTime.lastKey()!) {
      _byTime.clear();
    }
    _byTime[secs] = mgdl;
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

  Future<void> _persistLatest(G7GlucoseReading r) async {
    if (_persistKey.isEmpty) return;
    await store.saveLatest(
      _persistKey,
      mgdl: r.glucoseMgDl,
      trendTenths: r.trendTenths,
      state: r.state,
      secsSinceStart: r.secsSinceStart,
    );
  }

  /// Scan, connect, authenticate, and begin streaming. Reuses a stored session
  /// key for a fast reconnect, falling back to a full pairing if the sensor
  /// rejects it. Safe to call again after a drop (the watchdog does this).
  Future<void> connect() async {
    if (_connecting) return;
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
      final pinKey = serial.isNotEmpty ? serial : (store.resolvedKey ?? '');
      final wantedId = pinKey.isEmpty ? null : store.deviceId(pinKey);
      _log(wantedId == null ? 'scanning for DXCM…' : 'scanning for $wantedId…');
      final device = await BleTransport.scanForSensor(
        wantedId: wantedId,
        log: _log,
      );
      if (device == null) {
        _log('no sensor found');
        return;
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
              .firstWhere((s) => s != BluetoothBondState.bonding)
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
      // on the sensor's own advertising schedule (see G7TaskHandler.onRepeatEvent).
      transport = BleTransport(device);
      await transport.connectAndBind(log: _log);
      await _authenticate(transport);
      // Remember which physical sensor this was, so future reconnects pin to it.
      if (_persistKey.isNotEmpty) {
        await store.saveDeviceId(_persistKey, device.remoteId.str);
      }
      _log('session established');

      final t = transport;
      _controlSub = t.controlStream.listen(
        (b) => _onControl(t, Uint8List.fromList(b)),
      );
      _backfillSub = t.backfillStream.listen((b) {
        final recs = G7GlucoseCodec.parseBackfill(Uint8List.fromList(b));
        for (final r in recs) {
          _addReading(r.secsSinceStart, r.glucoseMgDl);
        }
        if (recs.isNotEmpty) {
          _persistReadings();
          onUpdate?.call();
        }
      });
      _connSub = t.device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          // DIAGNOSTIC: include the disconnect reason/code. A NORMAL G7 drop
          // looks different from an abnormal one (e.g. 19 REMOTE_USER_TERMINATED,
          // 147/8 CONNECTION_TIMEOUT) that may leave the sensor not advertising.
          final r = t.device.disconnectReason;
          _log('link dropped (reason code=${r?.code} "${r?.description}")');
          onConnectionState?.call(false);
        }
      });

      await t.enableDataChannels(log: _log);
      await t.writeControl([0x4E]); // current EGV
      // Version is static — only fetch it until we have it, to leave room in the
      // G7's brief reconnect window for the battery/calibration replies below.
      if (_info.firmware == null) {
        await t.writeControl([0x4A]); // transmitter version (fw, sw#, serial)
        await t.writeControl([
          0x52,
        ]); // extended version (session/warmup, hw, algo)
      }
      await t.writeControl([0x22]); // battery status
      await t.writeControl([0x32]); // calibration bounds (read-only status)

      _transport = transport;
      transport = null;
      onConnectionState?.call(true);
      _log('connected — streaming');
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
  Future<void> _authenticate(BleTransport t) async {
    final session = G7AuthSession(
      transport: t,
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
        if (_persistKey.isNotEmpty) await store.clearSessionKey(_persistKey);
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
    if (_persistKey.isNotEmpty) await store.saveSessionKey(_persistKey, secret);
  }

  void _onControl(BleTransport t, Uint8List bytes) {
    // Non-EGV control responses carry device metadata (version/battery).
    if (bytes.isNotEmpty && bytes[0] != 0x4E) {
      if (_info.applyControl(bytes)) {
        _persistInfo();
        onUpdate?.call();
      }
      return;
    }
    final r = G7GlucoseCodec.parseEgv(bytes);
    if (r == null) return;
    // The newest reading we already hold, BEFORE adding this EGV — the backfill
    // start point (so we only pull what we missed, not a fixed 24 h).
    final priorMax = _byTime.isEmpty ? null : _byTime.lastKey();
    _latest = r;
    _sensorStart = DateTime.now().subtract(Duration(seconds: r.secsSinceStart));
    if (r.glucoseMgDl != null) {
      _addReading(r.secsSinceStart, r.glucoseMgDl!);
      _persistReadings();
      _persistLatest(r); // restore the exact headline value on next launch
    }
    _persistInfo(); // keep cached sensorStart fresh
    onReading?.call(r);
    onUpdate?.call();
    // Once we know the session clock, pull history. Default to the full last
    // 24 h; only shrink to the gap-since-newest once we ALREADY hold a roughly
    // continuous day of history — otherwise a single cached point would wrongly
    // suppress the full backfill (leaving the chart and headline empty).
    if (!_backfillAsked) {
      _backfillAsked = true;
      final end = r.secsSinceStart - 60;
      var start = r.secsSinceStart - 24 * 3600;
      final haveFullDay =
          priorMax != null &&
          _byTime.isNotEmpty &&
          priorMax - _byTime.firstKey()! >= 23 * 3600;
      if (haveFullDay && priorMax > start) {
        start =
            priorMax + 1; // continuous history already cached → just the gap
      }
      if (start < 300) start = 300;
      // Request immediately: the G7 drops the link within a second of connecting,
      // so deferring the backfill would push it past the window and it'd never be
      // sent. (Metadata replies are best-effort within the same short window.)
      if (end > start) {
        _log('requesting backfill ${start}s..${end}s');
        t.requestBackfill(start, end);
      }
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

  Future<void> dispose() async {
    await _teardownTransport();
    onConnectionState?.call(false);
  }
}
