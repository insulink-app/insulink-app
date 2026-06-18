import 'dart:collection';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'src/g7/auth_session.dart';
import 'src/g7/ble_transport.dart';
import 'src/g7/device_info.dart';
import 'src/g7/glucose.dart';
import 'src/g7/store.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const G7ReaderApp());
}

class G7ReaderApp extends StatelessWidget {
  const G7ReaderApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'G7 Reader',
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.tealAccent,
        brightness: Brightness.dark,
      ),
    ),
    home: const ReaderPage(),
  );
}

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key});
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final _code = TextEditingController();
  final _serial = TextEditingController();
  final _log = <String>[];
  bool _busy = false;
  BleTransport? _transport;
  G7Store? _store;

  /// glucose history keyed by seconds-since-session-start (dedupes EGV+backfill).
  final SplayTreeMap<int, int> _byTime = SplayTreeMap();
  G7GlucoseReading? _latest;
  bool _backfillAsked = false;
  G7DeviceInfo _info = G7DeviceInfo();
  DateTime? _sensorStart;

  bool get _connected => _transport != null;

  @override
  void initState() {
    super.initState();
    G7Store.open().then((s) {
      if (!mounted) return;
      _store = s;
      final serial = s.serial ?? '';
      // Show cached history + device info immediately while we connect.
      final cached = serial.isEmpty ? <int, int>{} : s.loadReadings(serial);
      setState(() {
        _serial.text = serial;
        _code.text = s.pairingCode ?? '';
        _byTime.addAll(cached);
        if (serial.isNotEmpty) {
          _info = s.loadInfo(serial) ?? _info;
          _sensorStart = s.loadSensorStart(serial);
        }
      });
      if (cached.isNotEmpty) {
        _append('showing ${cached.length} cached readings');
      }
      // Auto-connect on launch when we already have a paired sensor.
      if (serial.isNotEmpty && s.sessionKey(serial) != null) {
        _append('auto-connecting to $serial…');
        _start();
      }
    });
  }

  void _append(String s) {
    if (mounted) setState(() => _log.insert(0, s));
  }

  void _addReading(int secs, int mgdl) {
    // A new sensor session resets secsSinceStart toward 0 — drop stale history.
    if (_byTime.isNotEmpty && secs + 3600 < _byTime.lastKey()!) {
      _byTime.clear();
    }
    setState(() => _byTime[secs] = mgdl);
  }

  Future<void> _persistReadings() async {
    final serial = _serial.text.trim();
    if (serial.isNotEmpty && _byTime.isNotEmpty) {
      await _store?.saveReadings(serial, _byTime);
    }
  }

  Future<void> _persistInfo() async {
    final serial = _serial.text.trim();
    if (serial.isNotEmpty && (_info.hasAny || _sensorStart != null)) {
      await _store?.saveInfo(serial, _info, _sensorStart);
    }
  }

  Future<void> _start() async {
    if (_busy) return;
    final hadConnection = _transport != null;
    await _transport?.dispose();
    _transport = null;
    _backfillAsked = false;
    setState(() => _busy = true);
    if (hadConnection) await Future<void>.delayed(const Duration(seconds: 2));

    BleTransport? transport;
    try {
      _append('scanning for DXCM…');
      final device = await BleTransport.scanForSensor();
      if (device == null) {
        _append('no sensor found');
        return;
      }
      final serial = _serial.text.trim();
      final code = _code.text.trim();
      await _store?.saveIdentity(serial: serial, pairingCode: code);

      transport = BleTransport(device);
      await transport.connectAndBind(log: _append);

      final session = G7AuthSession(
        transport: transport,
        pairingCode: code,
        log: _append,
      );
      final stored = serial.isEmpty ? null : _store?.sessionKey(serial);
      late final dynamic secret;
      if (stored != null) {
        try {
          secret = await session.runReconnect(stored);
          _append('RECONNECTED — no re-pairing needed');
        } catch (e) {
          _append('reconnect failed ($e) — full pairing');
          secret = await session.run();
          if (serial.isNotEmpty) await _store?.saveSessionKey(serial, secret);
        }
      } else {
        secret = await session.run();
        if (serial.isNotEmpty) await _store?.saveSessionKey(serial, secret);
      }
      _append('session established (${secret.length}-byte key)');

      final t = transport;
      t.controlStream.listen((b) => _onControl(t, Uint8List.fromList(b)));
      t.backfillStream.listen((b) {
        final recs = G7GlucoseCodec.parseBackfill(Uint8List.fromList(b));
        for (final r in recs) {
          _addReading(r.secsSinceStart, r.glucoseMgDl);
        }
        if (recs.isNotEmpty) _persistReadings();
      });
      await t.enableDataChannels(log: _append);
      await t.writeControl([0x4E]); // current EGV
      await t.writeControl([
        0x4A,
      ]); // transmitter version (firmware, sw#, serial)
      await t.writeControl([
        0x52,
      ]); // extended version (session/warmup, hw, algo)
      await t.writeControl([0x22]); // battery status

      _transport = transport;
      transport = null;
      _append('connected — streaming');
    } catch (e) {
      _append('ERROR: $e');
      await transport?.dispose();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onControl(BleTransport t, Uint8List bytes) {
    // Non-EGV control responses carry device metadata (version/battery).
    if (bytes.isNotEmpty && bytes[0] != 0x4E) {
      if (_info.applyControl(bytes)) {
        setState(() {});
        _persistInfo();
      }
      return;
    }
    final r = G7GlucoseCodec.parseEgv(bytes);
    if (r == null) return;
    _latest = r;
    _sensorStart = DateTime.now().subtract(Duration(seconds: r.secsSinceStart));
    if (r.glucoseMgDl != null) {
      _addReading(r.secsSinceStart, r.glucoseMgDl!);
      _persistReadings();
    }
    _persistInfo(); // keep cached sensorStart fresh
    // Once we know the session clock, pull the last 24 h of history.
    if (!_backfillAsked) {
      _backfillAsked = true;
      final end = r.secsSinceStart - 60;
      var start = r.secsSinceStart - 24 * 3600;
      if (start < 300) start = 300;
      if (end > start) {
        _append('requesting backfill ${start}s..${end}s');
        t.requestBackfill(start, end);
      }
    }
  }

  Future<void> _disconnect() async {
    await _transport?.dispose();
    _transport = null;
    _append('disconnected');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _transport?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dexcom G7'),
        actions: [
          if (_connected)
            IconButton(
              onPressed: _disconnect,
              icon: const Icon(Icons.bluetooth_disabled),
              tooltip: 'Disconnect',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CurrentValue(
              mgdl:
                  _latest?.glucoseMgDl ??
                  (_byTime.isNotEmpty ? _byTime[_byTime.lastKey()] : null),
              trendPerMin: _latest?.trendMgDlPerMin,
              stale: _latest == null && _byTime.isNotEmpty,
              busy: _busy,
            ),
            const SizedBox(height: 12),
            Expanded(flex: 3, child: _GlucoseChart(byTime: _byTime)),
            const SizedBox(height: 8),
            _SensorInfo(
              info: _info,
              sensorStart: _sensorStart,
              state: _latest?.state,
              age: _latest?.secsSinceStart,
            ),
            const SizedBox(height: 8),
            if (!_connected) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _serial,
                      decoration: const InputDecoration(
                        labelText: 'Serial',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _code,
                      decoration: const InputDecoration(
                        labelText: 'Pairing code',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _start,
                icon: const Icon(Icons.bluetooth_searching),
                label: Text(_busy ? 'Connecting…' : 'Connect'),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              flex: 1,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  reverse: false,
                  itemCount: _log.length,
                  itemBuilder: (_, i) => Text(
                    _log[i],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Big current-glucose readout with a trend arrow. [stale] dims the value when
/// it's the last cached reading shown before live data arrives.
class _CurrentValue extends StatelessWidget {
  const _CurrentValue({
    required this.mgdl,
    required this.trendPerMin,
    required this.stale,
    required this.busy,
  });
  final int? mgdl;
  final double? trendPerMin;
  final bool stale;
  final bool busy;

  String _arrow(double perMin) {
    if (perMin >= 3) return '⇈';
    if (perMin >= 2) return '↑';
    if (perMin >= 1) return '↗';
    if (perMin > -1) return '→';
    if (perMin > -2) return '↘';
    if (perMin > -3) return '↓';
    return '⇊';
  }

  Color _color(int v) {
    if (v < 70) return Colors.redAccent;
    if (v > 180) return Colors.orangeAccent;
    return Colors.tealAccent;
  }

  @override
  Widget build(BuildContext context) {
    final v = mgdl;
    if (v == null) {
      return Text(
        busy ? '…' : '--',
        style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold),
      );
    }
    final color = stale ? _color(v).withValues(alpha: 0.5) : _color(v);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '$v',
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        if (trendPerMin != null)
          Text(
            _arrow(trendPerMin!),
            style: TextStyle(fontSize: 40, color: color),
          ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              stale ? 'cached' : 'mg/dL',
              style: TextStyle(color: Colors.grey[400]),
            ),
            if (trendPerMin != null)
              Text(
                '${trendPerMin! >= 0 ? '+' : ''}'
                '${trendPerMin!.toStringAsFixed(1)}/min',
                style: TextStyle(color: Colors.grey[400]),
              ),
          ],
        ),
      ],
    );
  }
}

/// Compact panel of everything the sensor reports: start/expiry, state,
/// firmware/software/hardware versions, battery, serial, session lengths.
class _SensorInfo extends StatelessWidget {
  const _SensorInfo({
    required this.info,
    required this.sensorStart,
    required this.state,
    required this.age,
  });
  final G7DeviceInfo info;
  final DateTime? sensorStart;
  final int? state;
  final int? age;

  static String _dur(int? secs) {
    if (secs == null) return '—';
    final d = secs ~/ 86400,
        h = (secs % 86400) ~/ 3600,
        m = (secs % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  static String _dt(DateTime? t) {
    if (t == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final items = <MapEntry<String, String>>[];
    void add(String k, String? v) {
      if (v != null && v.isNotEmpty) items.add(MapEntry(k, v));
    }

    if (state != null) add('State', g7AlgorithmState(state!));
    add('Started', _dt(sensorStart));
    if (sensorStart != null && info.sessionLengthSec != null) {
      final expiry = sensorStart!.add(
        Duration(seconds: info.sessionLengthSec!),
      );
      final rem = expiry.difference(DateTime.now());
      final remStr = rem.isNegative
          ? 'expired'
          : 'in ${rem.inDays}d ${rem.inHours % 24}h';
      add('Expires (Ablauf)', '${_dt(expiry)}  ($remStr)');
    }
    final effAge =
        age ??
        (sensorStart != null
            ? DateTime.now().difference(sensorStart!).inSeconds
            : null);
    add('Age', _dur(effAge));
    add('Firmware', info.firmware);
    add('Software #', info.softwareNumber?.toString());
    add('Hardware', info.hardwareVersion?.toString());
    add(
      'Algorithm',
      info.algorithmVersion != null
          ? '0x${info.algorithmVersion!.toRadixString(16)}'
          : null,
    );
    add(
      'Silicon',
      info.siliconVersion != null
          ? '0x${info.siliconVersion!.toRadixString(16)}'
          : null,
    );
    add('Serial', info.serialNumber);
    add('Session', _dur(info.sessionLengthSec));
    add('Warmup', _dur(info.warmupSec));
    add('Max days', info.maxLifetimeDays?.toString());
    if (info.batteryVoltageA != null) {
      add(
        'Battery',
        '${info.batteryVoltageA}/${info.batteryVoltageB} mV · ${info.runtimeDays}d · ${info.temperatureC}°C',
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final e in items)
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 11),
                children: [
                  TextSpan(
                    text: '${e.key}: ',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                  TextSpan(
                    text: e.value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// fl_chart line graph of glucose vs. time (hours, 0 = latest reading).
class _GlucoseChart extends StatelessWidget {
  const _GlucoseChart({required this.byTime});
  final SplayTreeMap<int, int> byTime;

  @override
  Widget build(BuildContext context) {
    if (byTime.isEmpty) {
      return const Center(child: Text('no readings yet'));
    }
    final entries = byTime.entries.toList();
    final latestSecs = entries.last.key;
    final spots = [
      for (final e in entries)
        FlSpot((e.key - latestSecs) / 3600.0, e.value.toDouble()),
    ];
    final maxY =
        (entries.map((e) => e.value).reduce((a, b) => a > b ? a : b) + 30)
            .clamp(200, 400)
            .toDouble();
    final minX = spots.first.x;

    return LineChart(
      LineChartData(
        minY: 40,
        maxY: maxY,
        minX: minX,
        maxX: 0,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 50,
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: 50,
              getTitlesWidget: (v, _) => Text(
                '${v.toInt()}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 6,
              getTitlesWidget: (v, _) => Text(
                '${v.toInt()}h',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ),
        ),
        // Target range band 70–180 mg/dL.
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 70,
              color: Colors.red.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
            HorizontalLine(
              y: 180,
              color: Colors.orange.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ],
        ),
        lineTouchData: const LineTouchData(enabled: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            barWidth: 3,
            color: Colors.tealAccent,
            dotData: FlDotData(show: spots.length < 60),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.tealAccent.withValues(alpha: 0.3),
                  Colors.tealAccent.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
