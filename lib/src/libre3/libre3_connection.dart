import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

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

  /// Standard Libre 3 wear time (14 days) — used for the expiry warning; the
  /// sensor also reports it in factory data, wired later.
  static const _sessionLengthSec = 14 * 24 * 3600;

  Libre3Transport? _transport;
  StreamSubscription? _glucoseSub;
  StreamSubscription? _historicSub;
  StreamSubscription? _connSub;

  final SplayTreeMap<int, int> _byTime = SplayTreeMap();
  CgmReading? _latest;
  DateTime? _sensorStart;
  bool _connecting = false;

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
    _log('Libre 3 reading: ${reading.glucoseMgDl} mg/dL @ ${reading.secsSinceStart}s');
    _latest = reading;
    _sensorStart = DateTime.now().subtract(
      Duration(seconds: reading.secsSinceStart),
    );
    if (reading.glucoseMgDl != null) {
      _byTime[reading.secsSinceStart] = reading.glucoseMgDl!;
      _persistReadings();
      _persistLatest(reading);
      _archiveKnown();
    }
    onReading?.call(reading);
    onUpdate?.call();
  }

  void _onHistoric(List<int> plaintext) {
    final records = Libre3GlucoseCodec.parseHistorical(
      Uint8List.fromList(plaintext),
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
  }

  @override
  Future<void> dispose() async {
    await _teardown();
    onConnectionState?.call(false);
  }
}
