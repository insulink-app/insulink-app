import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../cgm/cgm_connection.dart';
import '../cgm/cgm_store.dart';
import 'libre3_crypto.dart';
import 'libre3_glucose.dart';
import 'libre3_transport.dart';

/// FreeStyle Libre 3 implementation of [CgmConnection]: scan by the NFC-derived
/// MAC → connect → security handshake (via the Abbott blob behind
/// [Libre3Crypto]) → stream + decode one-minute readings + historical backfill →
/// persist. Emits the SAME callbacks as [G7Connection], so the service isolate,
/// controller, chart, stats, alarms and backend queue are all shared.
///
/// The Libre 3 holds a continuous link and streams every ~1 min, so its
/// [timing] tolerates far less silence than the G7's connect/deliver/drop cycle.
class Libre3Connection implements CgmConnection {
  Libre3Connection({
    required this.store,
    required this.crypto,
    this.onLog,
    this.onReading,
    this.onUpdate,
    this.onConnectionState,
    this.onArchive,
  });

  final CgmStore store;
  final Libre3Crypto crypto;

  final void Function(String line)? onLog;
  final void Function(CgmReading reading)? onReading;
  final void Function()? onUpdate;
  final void Function(bool connected)? onConnectionState;
  final void Function(Map<int, int> byEpochMinute)? onArchive;

  /// Standard Libre 3 wear time (14 days, from [SensorType.sessionLengthSec]) —
  /// used for the expiry/halftime warnings; the sensor also reports it in
  /// factory data, wired later.
  static final _sessionLengthSec = SensorType.abbottLibre3.sessionLengthSec;

  Libre3Transport? _transport;
  StreamSubscription? _glucoseSub;
  StreamSubscription? _historicSub;
  StreamSubscription? _connSub;

  final SplayTreeMap<int, int> _byTime = SplayTreeMap();
  CgmReading? _latest;
  DateTime? _sensorStart;
  bool _connecting = false;

  /// Persisted history is pulled into [_byTime] once per process so the backlog
  /// survives reconnects/isolate restarts and [_persistReadings] extends it
  /// instead of overwriting it with only what the sensor re-streams.
  bool _historyLoaded = false;

  /// Whether this connection already asked the sensor to replay its buffered
  /// history (gap-fill). Reset on each connect so every reconnect catches up.
  bool _backfillRequested = false;

  String get _key => store.resolvedKey ?? '';

  @override
  bool get isConnected => _transport?.device.isConnected ?? false;

  @override
  bool get isConnecting => _connecting;

  @override
  int? get sessionLengthSec => _sessionLengthSec;

  @override
  int? get latestMgDl =>
      _latest?.glucoseMgDl ??
      (_byTime.isNotEmpty ? _byTime[_byTime.lastKey()] : null);

  @override
  double? get latestTrendPerMin => _latest?.trendMgDlPerMin;

  /// Continuous link, ~1-min stream: silence beyond a few minutes is a fault,
  /// and there is no connect/deliver/drop backoff to honour.
  @override
  CgmTiming get timing => const CgmTiming(
    staleAfter: Duration(minutes: 6),
    restartAfter: Duration(minutes: 12),
    processRestartAfter: Duration(minutes: 20),
    connectStuckAfter: Duration(minutes: 3),
    reconnectBackoff: Duration.zero,
    expectsContinuousLink: true,
  );

  void _log(String line) => onLog?.call(line);

  @override
  Future<void> connect() async {
    if (_connecting) {
      return;
    }
    _connecting = true;
    await _teardown();
    final key = _key;
    final mac = key.isEmpty ? null : store.libreMac(key);
    if (mac == null) {
      _log('no Libre 3 activation on file — scan the sensor with NFC first');
      _connecting = false;
      return;
    }
    if (!_historyLoaded && key.isNotEmpty) {
      _historyLoaded = true;
      _byTime.addAll(store.loadReadings(key));
    }

    Libre3Transport? transport;
    try {
      _log('scanning for Libre 3 $mac…');
      final device = await Libre3Transport.scanForMac(mac, log: _log);
      if (device == null) {
        _log('Libre 3 not found');
        return;
      }
      transport = Libre3Transport(
        device: device,
        crypto: crypto,
        blePin: store.librePin(key),
      );
      await transport.connectAndBind(log: _log);
      final authKey = await transport.runHandshake(
        cachedAuthKey: store.libreAuthKey(key),
        log: _log,
      );
      await store.saveLibreAuthKey(key, authKey);

      final boundTransport = transport;
      _glucoseSub = boundTransport.glucoseStream.listen(_onGlucose);
      _historicSub = boundTransport.historicStream.listen(_onHistoric);
      _connSub = boundTransport.device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _log('Libre 3 link dropped');
          onConnectionState?.call(false);
        }
      });

      _transport = transport;
      transport = null;
      onConnectionState?.call(true);
      _log('Libre 3 connected — streaming');
    } catch (error) {
      _log('ERROR: $error');
      await transport?.dispose();
    } finally {
      _connecting = false;
    }
  }

  void _onGlucose(List<int> plaintext) {
    final reading = Libre3GlucoseCodec.parseOneMinuteReading(
      Uint8List.fromList(plaintext),
    );
    if (reading == null) {
      _log('Libre 3 one-minute parse failed (${plaintext.length} B)');
      return;
    }
    _log(
      'Libre 3 reading: ${reading.glucoseMgDl} mg/dL @ ${reading.secsSinceStart}s',
    );
    // The newest point we already hold BEFORE this reading — the backfill start
    // (so we only pull the gap we missed, not the whole buffer).
    final priorMax = _byTime.isEmpty ? null : _byTime.lastKey();
    _latest = reading;
    _anchorSensorStart(reading.secsSinceStart);
    _persistSensorStart();
    if (reading.glucoseMgDl != null) {
      _byTime[reading.secsSinceStart] = reading.glucoseMgDl!;
      _persistReadings();
      _persistLatest(reading);
      _archiveKnown();
    }
    onReading?.call(reading);
    onUpdate?.call();
    if (!_backfillRequested && _transport != null) {
      _backfillRequested = true;
      _requestBackfill(reading.secsSinceStart, priorMax);
    }
  }

  /// The most history we ask the sensor to replay after a gap. The Libre 3's real
  /// BLE backfill depth is unverified, so this is a deliberately conservative,
  /// tunable cap (the real buffer may be shorter or longer).
  static const int _maxBackfillMinutes = 6 * 60;

  /// Don't pester the patch for gaps smaller than this — the normal 1-min stream
  /// needs no catch-up; only a real disconnect leaves a bigger hole.
  static const int _minBackfillGapMin = 10;

  /// Gap-based backfill (mirrors the G7's `_requestBackfill`): on the first
  /// reading after connecting, ask the sensor to replay what we're missing since
  /// [priorMax] (our newest stored point). Fire-and-forget — replies merge back
  /// through [_onHistoric].
  ///
  /// DIAGNOSTIC MODE ([_backfillDiagnostic]): the Patch Control command is still
  /// hardware-unverified, so right now we fire ONCE per connect even without a
  /// gap (a short recent window) and log richly — the only way to observe on real
  /// hardware whether the command elicits any historic (`0898195a`) response.
  /// Once confirmed, flip [_backfillDiagnostic] off to restore the gap gate.
  void _requestBackfill(int liveSecs, int? priorMax) {
    final transport = _transport;
    if (transport == null) {
      return;
    }
    final liveLifeCount = liveSecs ~/ 60;
    final gated = backfillStartLifeCount(liveSecs, priorMax);
    final from =
        gated ??
        (_backfillDiagnostic
            ? (liveLifeCount - 60 < 0 ? 0 : liveLifeCount - 60)
            : null);
    if (from == null) {
      _log(
        'Libre 3 backfill: skipped (no gap; live $liveLifeCount, '
        'prior ${priorMax == null ? '—' : priorMax ~/ 60})',
      );
      return;
    }
    _log(
      'Libre 3 backfill: would request from life count $from '
      '(live $liveLifeCount, prior ${priorMax == null ? '—' : priorMax ~/ 60})',
    );
    if (_activeBackfillWrite) {
      transport.requestBackfill(from);
    } else {
      _log('Libre 3 backfill: active write disabled — observing passively');
    }
  }

  /// ponytail: while true, always evaluate the backfill once per connect so
  /// on-device logs reveal the sensor's behaviour. Turn off once verified.
  static const bool _backfillDiagnostic = true;

  /// The Patch Control command is confirmed length-rejected
  /// (GATT_INVALID_ATTRIBUTE_LENGTH) — the 3-byte guess is wrong. Keep the write
  /// OFF until the real command format is known (from a Juggluco/DiaBLE capture),
  /// so we can cleanly observe whether the sensor pushes historic passively.
  static const bool _activeBackfillWrite = false;

  /// The life count (minutes since activation) to start a backfill request from,
  /// or null when the gap since [priorMax] is too small to bother. Only pulls the
  /// gap we missed, capped at [_maxBackfillMinutes]. Pure so it is unit-tested.
  @visibleForTesting
  static int? backfillStartLifeCount(int liveSecs, int? priorMax) {
    final liveLifeCount = liveSecs ~/ 60;
    final gapMinutes = priorMax == null
        ? _maxBackfillMinutes
        : liveLifeCount - (priorMax ~/ 60);
    if (gapMinutes < _minBackfillGapMin) {
      return null;
    }
    final span = gapMinutes > _maxBackfillMinutes
        ? _maxBackfillMinutes
        : gapMinutes;
    final from = liveLifeCount - span;
    return from < 0 ? 0 : from;
  }

  void _onHistoric(List<int> plaintext) {
    final records = Libre3GlucoseCodec.parseHistorical(
      Uint8List.fromList(plaintext),
    );
    _log(
      'Libre 3 historic notification: ${plaintext.length} B → '
      '${records.length} record(s)',
    );
    if (records.isEmpty) {
      return;
    }
    for (final record in records) {
      _byTime[record.secsSinceStart] = record.glucoseMgDl;
    }
    _persistReadings();
    _archiveKnown();
    onUpdate?.call();
  }

  /// Anchor the session start ONCE and keep it stable. The sensor clock is
  /// minute-granular, so recomputing `now - secsSinceStart` every reading would
  /// jitter the start ±60 s and smear the archive's absolute timestamps. Re-anchor
  /// only on a large jump (a swapped sensor / session reset).
  void _anchorSensorStart(int secsSinceStart) {
    final candidate = DateTime.now().subtract(
      Duration(seconds: secsSinceStart),
    );
    final current = _sensorStart ?? store.loadSensorStart(_key);
    if (current == null ||
        current.difference(candidate).abs() > const Duration(minutes: 5)) {
      _sensorStart = candidate;
    } else {
      _sensorStart = current;
    }
  }

  Future<void> _persistSensorStart() async {
    final start = _sensorStart;
    if (_key.isNotEmpty && start != null) {
      await store.saveSensorStart(_key, start);
    }
  }

  Future<void> _persistReadings() async {
    if (_key.isNotEmpty && _byTime.isNotEmpty) {
      await store.saveReadings(_key, _byTime);
    }
  }

  Future<void> _persistLatest(CgmReading reading) async {
    if (_key.isEmpty) {
      return;
    }
    await store.saveLatest(
      _key,
      mgdl: reading.glucoseMgDl,
      trendTenths: reading.trendTenths,
      state: reading.state,
      secsSinceStart: reading.secsSinceStart,
    );
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

  Future<void> _teardown() async {
    await _glucoseSub?.cancel();
    await _historicSub?.cancel();
    await _connSub?.cancel();
    _glucoseSub = _historicSub = _connSub = null;
    await _transport?.dispose();
    _transport = null;
    _backfillRequested = false;
  }

  @override
  Future<void> dispose() async {
    await _teardown();
    onConnectionState?.call(false);
  }
}
