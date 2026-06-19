import 'dart:async';
import 'dart:collection';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import 'src/g7/ble_service.dart';
import 'src/g7/device_info.dart';
import 'src/g7/glucose.dart';
import 'src/g7/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Required so the UI isolate can exchange data with the foreground-service
  // isolate that owns the BLE connection.
  FlutterForegroundTask.initCommunicationPort();
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

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
  final _code = TextEditingController();
  final _serial = TextEditingController();
  final _log = <String>[];
  bool _busy = false;

  /// True while the foreground service (which owns the BLE link) is running.
  bool _serviceRunning = false;
  G7Store? _store;

  /// glucose history keyed by seconds-since-session-start (dedupes EGV+backfill).
  /// Mirrors what the background service persists to [G7Store].
  final SplayTreeMap<int, int> _byTime = SplayTreeMap();
  G7GlucoseReading? _latest;

  /// False when [_latest] was restored from cache (shown dimmed as "cached"),
  /// true once a live reading arrives from the service.
  bool _latestIsLive = false;

  /// Wall-clock time a live reading last arrived from the service. Fallback for
  /// the "last update" time when the sensor session start isn't known.
  DateTime? _latestAt;
  G7DeviceInfo _info = G7DeviceInfo();
  DateTime? _sensorStart;

  bool get _connected => _serviceRunning;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Receive live updates pushed from the foreground-service isolate.
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    G7Store.open().then((s) async {
      if (!mounted) return;
      _store = s;
      final serial = s.serial ?? '';
      // Show cached history, latest value + device info immediately.
      final cached = serial.isEmpty ? <int, int>{} : s.loadReadings(serial);
      final latest = serial.isEmpty ? null : s.loadLatest(serial);
      setState(() {
        _serial.text = serial;
        _code.text = s.pairingCode ?? '';
        _byTime.addAll(cached);
        if (serial.isNotEmpty) {
          _info = s.loadInfo(serial) ?? _info;
          _sensorStart = s.loadSensorStart(serial);
        }
        if (latest != null) {
          _latest = G7GlucoseReading(
            secsSinceStart: latest['secs'] as int? ?? 0,
            age: 0,
            sequence: 0,
            glucoseMgDl: latest['mgdl'] as int?,
            predictedMgDl: 0,
            trendTenths: latest['trend'] as int? ?? 0,
            state: latest['state'] as int? ?? 0,
          );
          _latestIsLive = false; // from cache until a live reading arrives
        }
      });
      if (cached.isNotEmpty) {
        _append('showing ${cached.length} cached readings');
      }
      await _refreshServiceState();
      // Auto-connect on launch when paired, unless the service is already up
      // (it keeps running while the app is closed).
      if (serial.isNotEmpty &&
          s.sessionKey(serial) != null &&
          !_serviceRunning) {
        _append('auto-connecting to $serial…');
        _start();
      }
    });
  }

  void _append(String s) {
    if (mounted) setState(() => _log.insert(0, s));
  }

  /// Copy the whole log (oldest line first, chronological) to the clipboard so it
  /// can be shared. [_log] is stored newest-first, so reverse it for sharing.
  Future<void> _copyLog() async {
    await Clipboard.setData(ClipboardData(text: _log.reversed.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_log.length} Log-Zeilen kopiert')),
      );
    }
  }

  /// Messages from the background service: log lines, the latest live reading,
  /// a "reload from store" ping, and connection-state transitions.
  void _onTaskData(Object data) {
    if (data is! Map) return;
    switch (data['t']) {
      case 'log':
        _append(data['line'] as String? ?? '');
      case 'reading':
        if (!mounted) return;
        setState(() {
          _latest = G7GlucoseReading(
            secsSinceStart: data['secs'] as int? ?? 0,
            age: 0,
            sequence: 0,
            glucoseMgDl: data['mgdl'] as int?,
            predictedMgDl: 0,
            trendTenths: data['trendTenths'] as int? ?? 0,
            state: data['state'] as int? ?? 0,
          );
          _latestIsLive = true;
          _latestAt = DateTime.now();
        });
      case 'update':
        _reloadFromStore();
    }
  }

  /// Re-read everything the service persisted (history, info, sensor start).
  /// Requires reloading the SharedPreferences cache since the writes happened
  /// in the service isolate.
  Future<void> _reloadFromStore() async {
    final s = _store;
    if (s == null) return;
    await s.reload();
    final serial = _serial.text.trim();
    if (serial.isEmpty || !mounted) return;
    final cached = s.loadReadings(serial);
    setState(() {
      _byTime
        ..clear()
        ..addAll(cached);
      _info = s.loadInfo(serial) ?? _info;
      _sensorStart = s.loadSensorStart(serial) ?? _sensorStart;
    });
  }

  Future<void> _refreshServiceState() async {
    final running = await FlutterForegroundTask.isRunningService;
    if (mounted) setState(() => _serviceRunning = running);
  }

  /// Request the BLE permissions the background scan/connect needs. On
  /// Android 12+ these are `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`; on older
  /// versions scanning needs location instead (auto-granted scan/connect).
  Future<bool> _ensureBlePermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final scanOk = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final connectOk = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    final locOk = statuses[Permission.locationWhenInUse]?.isGranted ?? false;
    // Modern devices need scan+connect; pre-12 falls back to location.
    return (scanOk && connectOk) || locOk;
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'insulink',
        channelName: 'Dexcom G7 connection',
        channelDescription:
            'Keeps the glucose connection alive in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Watchdog tick that lets the handler reconnect after a drop.
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Start the foreground service that connects and streams glucose. The BLE
  /// work now lives in that service isolate, so it survives the app being
  /// backgrounded or closed.
  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Bluetooth runtime permissions must be GRANTED before starting a
      // `connectedDevice` foreground service (Android 14+ validates the app
      // holds one), and because the scan now runs in the background isolate
      // which cannot show permission dialogs. Request them here in the UI.
      if (!await _ensureBlePermissions()) {
        _append('Bluetooth permission denied — cannot start');
        return;
      }
      if (await FlutterForegroundTask.checkNotificationPermission() !=
          NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      final serial = _serial.text.trim();
      final code = _code.text.trim();
      // The service isolate reads serial + code from the store on start.
      await _store?.saveIdentity(serial: serial, pairingCode: code);

      _initForegroundTask();
      final result = await FlutterForegroundTask.startService(
        serviceId: 256,
        serviceTypes: const [ForegroundServiceTypes.connectedDevice],
        notificationTitle: 'Dexcom G7',
        notificationText: 'connecting…',
        callback: startCallback,
      );
      if (result is ServiceRequestSuccess) {
        _append('background service started');
      } else if (result is ServiceRequestFailure) {
        _append('service start failed: ${result.error}');
      }
      await _refreshServiceState();
    } catch (e) {
      _append('ERROR: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    await FlutterForegroundTask.stopService();
    _append('disconnected');
    if (mounted) {
      setState(() {
        _serviceRunning = false;
        _latest = null;
        _latestIsLive = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Catch up on whatever the service captured while we were away.
      _refreshServiceState();
      _reloadFromStore();
    }
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Wall-clock time of the latest glucose reading. Derived from the sensor's own
  /// session clock (`sensorStart + secsSinceStart`) so it's correct even for the
  /// value restored from cache on launch; falls back to the live arrival time.
  DateTime? get _lastUpdate {
    final l = _latest;
    if (l == null) return null;
    final start = _sensorStart;
    if (start != null) return start.add(Duration(seconds: l.secsSinceStart));
    return _latestAt;
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
              // Dimmed "cached" until a live reading arrives from the service.
              stale: !_latestIsLive,
              busy: _busy,
            ),
            _UpdateStatus(lastUpdate: _lastUpdate),
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
            Row(
              children: [
                Text('Log', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                const Spacer(),
                if (_log.isNotEmpty)
                  TextButton.icon(
                    onPressed: _copyLog,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Kopieren'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
            Expanded(
              flex: 1,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                // SelectableText so individual lines can also be selected by hand;
                // the Kopieren button grabs the whole log at once. Scrollable
                // because SelectableText won't scroll on its own inside Expanded.
                child: SingleChildScrollView(
                  child: SelectableText(
                    _log.join('\n'),
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

/// Live "last / next update" line. The G7 reports a new glucose value every
/// ~5 minutes, so this shows when the last one arrived and counts down to the
/// next expected one, ticking once a second on its own (without rebuilding the
/// chart). [lastUpdate] is the wall-clock time of the latest reading.
class _UpdateStatus extends StatefulWidget {
  const _UpdateStatus({required this.lastUpdate});
  final DateTime? lastUpdate;

  @override
  State<_UpdateStatus> createState() => _UpdateStatusState();
}

class _UpdateStatusState extends State<_UpdateStatus> {
  /// G7 EGV cadence — a new value roughly every 5 minutes.
  static const _intervalSec = 300;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _hms(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// "3 min 21 s" / "45 s" for a non-negative duration.
  static String _span(Duration d) {
    final s = d.inSeconds;
    if (s < 60) return '$s s';
    return '${s ~/ 60} min ${s % 60} s';
  }

  @override
  Widget build(BuildContext context) {
    final last = widget.lastUpdate;
    final grey = TextStyle(fontSize: 12, color: Colors.grey[400]);
    if (last == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('Noch keine Aktualisierung empfangen', style: grey),
      );
    }

    final now = DateTime.now();
    final ago = now.difference(last);
    final next = last.add(const Duration(seconds: _intervalSec));
    final rem = next.difference(now);

    final String nextLabel;
    final Color nextColor;
    if (rem.isNegative) {
      // Past the expected slot — the reading is late (skipped/poor signal).
      nextLabel = 'Nächste überfällig (seit ${_span(-rem)})';
      nextColor = Colors.orangeAccent;
    } else {
      nextLabel = 'Nächste in noch ${_span(rem)}…';
      nextColor = Colors.grey[300]!;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Zuletzt aktualisiert: ${_hms(last)} (vor ${_span(ago)})',
            style: grey,
          ),
          Text(
            nextLabel,
            style: TextStyle(fontSize: 12, color: nextColor),
          ),
        ],
      ),
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
