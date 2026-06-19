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

  /// Persisted history is pulled into [_byTime] once so backfill can request
  /// only the gap since our newest known reading (not a fixed 24 h every cycle).
  bool _historyLoaded = false;

  bool get isConnected => _transport?.device.isConnected ?? false;
  bool get isConnecting => _connecting;

  /// The latest known glucose value (live EGV, else newest history point).
  int? get latestMgDl =>
      _latest?.glucoseMgDl ?? (_byTime.isNotEmpty ? _byTime[_byTime.lastKey()] : null);

  void _log(String s) => onLog?.call(s);

  void _addReading(int secs, int mgdl) {
    // A new sensor session resets secsSinceStart toward 0 — drop stale history.
    if (_byTime.isNotEmpty && secs + 3600 < _byTime.lastKey()!) {
      _byTime.clear();
    }
    _byTime[secs] = mgdl;
  }

  Future<void> _persistReadings() async {
    if (serial.isNotEmpty && _byTime.isNotEmpty) {
      await store.saveReadings(serial, _byTime);
    }
  }

  Future<void> _persistInfo() async {
    if (serial.isNotEmpty && (_info.hasAny || _sensorStart != null)) {
      await store.saveInfo(serial, _info, _sensorStart);
    }
  }

  Future<void> _persistLatest(G7GlucoseReading r) async {
    if (serial.isEmpty) return;
    await store.saveLatest(
      serial,
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
    // Seed in-memory history from the store so backfill only fetches the gap.
    if (!_historyLoaded && serial.isNotEmpty) {
      _historyLoaded = true;
      _byTime.addAll(store.loadReadings(serial));
    }

    BleTransport? transport;
    try {
      // Pin to the known sensor once we've paired: with a stored device id we
      // scan for THAT sensor only, so a different nearby G7 can't be picked up
      // and fail key-confirmation against our stored key.
      final wantedId = serial.isEmpty ? null : store.deviceId(serial);
      _log(wantedId == null ? 'scanning for DXCM…' : 'scanning for $wantedId…');
      final device = await BleTransport.scanForSensor(wantedId: wantedId);
      if (device == null) {
        _log('no sensor found');
        return;
      }

      // One clean attempt per connect(): the G7 rejects rapid in-process
      // reconnects (REMOTE_USER_TERMINATED / CONNECTION_TIMEOUT), so on a
      // handshake failure we tear down and let the 30s watchdog re-scan and retry
      // on the sensor's own advertising schedule (see G7TaskHandler.onRepeatEvent).
      transport = BleTransport(device);
      await transport.connectAndBind(log: _log);
      await _authenticate(transport);
      // Remember which physical sensor this was, so future reconnects pin to it.
      if (serial.isNotEmpty) {
        await store.saveDeviceId(serial, device.remoteId.str);
      }
      _log('session established');

      final t = transport;
      _controlSub = t.controlStream
          .listen((b) => _onControl(t, Uint8List.fromList(b)));
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
          _log('link dropped');
          onConnectionState?.call(false);
        }
      });

      await t.enableDataChannels(log: _log);
      await t.writeControl([0x4E]); // current EGV
      await t.writeControl([0x4A]); // transmitter version (fw, sw#, serial)
      await t.writeControl([0x52]); // extended version (session/warmup, hw, algo)
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
  /// pairing; on reconnect rejection fall back to a full pairing. The new key is
  /// persisted. Throws on handshake failure so the caller can retry on a fresh link.
  Future<void> _authenticate(BleTransport t) async {
    final session = G7AuthSession(
      transport: t,
      pairingCode: pairingCode,
      log: _log,
    );
    final stored = serial.isEmpty ? null : store.sessionKey(serial);
    if (stored != null) {
      try {
        await session.runReconnect(stored);
        _log('RECONNECTED — no re-pairing needed');
        return;
      } catch (e) {
        _log('reconnect failed ($e) — full pairing');
      }
    }
    final secret = await session.run();
    if (serial.isNotEmpty) await store.saveSessionKey(serial, secret);
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
      final haveFullDay = priorMax != null &&
          _byTime.isNotEmpty &&
          priorMax - _byTime.firstKey()! >= 23 * 3600;
      if (haveFullDay && priorMax > start) {
        start = priorMax + 1; // continuous history already cached → just the gap
      }
      if (start < 300) start = 300;
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
