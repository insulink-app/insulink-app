import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'service.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => DexcomG7Service(),
      child: const DexcomApp(),
    ),
  );
}

class DexcomApp extends StatelessWidget {
  const DexcomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dexcom G7',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// ─── HOME SCREEN ─────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _txIdController = TextEditingController();
  final _sensorCodeController = TextEditingController();
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _loadSavedTxId();
    _requestPermissions();
  }

  Future<void> _loadSavedTxId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('transmitter_id') ?? '';
    final savedCode = prefs.getString('sensor_code') ?? '';
    setState(() {
      _txIdController.text = saved;
      _sensorCodeController.text = savedCode;
    });
  }

  Future<void> _saveTxId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('transmitter_id', id);
  }

  Future<void> _saveSensorCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sensor_code', code);
  }

  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final granted = statuses.values.every(
            (s) => s == PermissionStatus.granted);
    setState(() => _permissionsGranted = granted);

    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Bluetooth- und Standortberechtigung erforderlich'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text(
          'Dexcom G7',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white70),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const HistoryScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<DexcomG7Service>(
        builder: (context, service, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Glukose-Anzeige
                _GlucoseDisplay(service: service),
                const SizedBox(height: 24),

                // Verbindungsstatus
                _ConnectionStatus(service: service),
                const SizedBox(height: 24),

                // Sensor-Code Eingabe
                _SensorCodeInput(
                  controller: _sensorCodeController,
                  onChanged: (code) {
                    setState(() {});
                    _saveSensorCode(code);
                  },
                ),
                const SizedBox(height: 16),

                // Seriennummer Eingabe
                _PairingCodeInput(
                  controller: _txIdController,
                  onChanged: (id) {
                    setState(() {});
                    _saveTxId(id);
                  },
                ),
                const SizedBox(height: 16),

                // Buttons
                _ActionButtons(
                  service: service,
                  sensorCode: _sensorCodeController.text,
                  txId: _txIdController.text,
                  permissionsGranted: _permissionsGranted,
                  onTxIdChanged: () => setState(() {}),
                ),

                // Fehleranzeige
                if (service.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  _ErrorCard(message: service.errorMessage!),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _txIdController.dispose();
    _sensorCodeController.dispose();
    super.dispose();
  }
}

// ─── WIDGETS ─────────────────────────────────────────────────────────────────

class _GlucoseDisplay extends StatelessWidget {
  final DexcomG7Service service;
  const _GlucoseDisplay({required this.service});

  Color _glucoseColor(int mgdl) {
    if (mgdl < 70) return const Color(0xFFFF4444);
    if (mgdl < 80) return const Color(0xFFFF8800);
    if (mgdl <= 180) return const Color(0xFF44BB44);
    if (mgdl <= 250) return const Color(0xFFFF8800);
    return const Color(0xFFFF4444);
  }

  @override
  Widget build(BuildContext context) {
    final reading = service.lastReading;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: reading != null
              ? _glucoseColor(reading.glucoseMgdl).withOpacity(0.4)
              : Colors.white12,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Hauptwert
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                reading != null ? '${reading.glucoseMgdl}' : '---',
                style: TextStyle(
                  fontSize: 80,
                  fontWeight: FontWeight.w300,
                  color: reading != null
                      ? _glucoseColor(reading.glucoseMgdl)
                      : Colors.white24,
                  height: 1,
                ),
              ),
              if (reading != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    reading.trendArrow,
                    style: TextStyle(
                      fontSize: 32,
                      color: _glucoseColor(reading.glucoseMgdl),
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 8),
          const Text(
            'mg/dL',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 16,
              letterSpacing: 2,
            ),
          ),

          if (reading != null) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Zeitstempel
                _InfoChip(
                  label: _formatTime(reading.timestamp),
                  icon: Icons.access_time,
                ),
                // Trend
                if (reading.trendMgdlPerMin != null)
                  _InfoChip(
                    label: '${reading.trendMgdlPerMin! >= 0 ? '+' : ''}'
                        '${reading.trendMgdlPerMin!.toStringAsFixed(1)} mg/min',
                    icon: Icons.trending_flat,
                  ),
                // Prognose
                if (reading.predictedGlucose != null)
                  _InfoChip(
                    label: 'Prog: ${reading.predictedGlucose}',
                    icon: Icons.arrow_forward,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _InfoChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white54),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatus extends StatelessWidget {
  final DexcomG7Service service;
  const _ConnectionStatus({required this.service});

  Color get _stateColor {
    return switch (service.connectionState) {
      DexConnectionState.connected => const Color(0xFF44BB44),
      DexConnectionState.scanning ||
      DexConnectionState.connecting ||
      DexConnectionState.authenticating =>
      const Color(0xFF1A73E8),
      DexConnectionState.error => const Color(0xFFFF4444),
      _ => Colors.white38,
    };
  }

  IconData get _stateIcon {
    return switch (service.connectionState) {
      DexConnectionState.connected => Icons.bluetooth_connected,
      DexConnectionState.scanning => Icons.bluetooth_searching,
      DexConnectionState.connecting ||
      DexConnectionState.authenticating =>
      Icons.bluetooth,
      DexConnectionState.error => Icons.bluetooth_disabled,
      _ => Icons.bluetooth_disabled,
    };
  }

  bool get _isLoading =>
      service.connectionState == DexConnectionState.scanning ||
          service.connectionState == DexConnectionState.connecting ||
          service.connectionState == DexConnectionState.authenticating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          if (_isLoading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _stateColor,
              ),
            )
          else
            Icon(_stateIcon, color: _stateColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              service.statusMessage,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PairingCodeInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _PairingCodeInput({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Seriennummer (SN)',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: TextInputType.number,
          maxLength: 12,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            letterSpacing: 4,
            fontWeight: FontWeight.w300,
          ),
          decoration: InputDecoration(
            hintText: '698926479289',
            hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.2),
              letterSpacing: 4,
            ),
            counterText: '',
            filled: true,
            fillColor: const Color(0xFF161B22),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: Color(0xFF1A73E8), width: 2),
            ),
            prefixIcon:
            const Icon(Icons.pin, color: Colors.white38),
            helperText: '12-stellige SN vom Sensor-Applikator',
            helperStyle:
            const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _SensorCodeInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SensorCodeInput({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sensor-Code',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: TextInputType.number,
          maxLength: 4,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            letterSpacing: 8,
            fontWeight: FontWeight.w300,
          ),
          decoration: InputDecoration(
            hintText: '1234',
            hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.2),
              letterSpacing: 8,
            ),
            counterText: '',
            filled: true,
            fillColor: const Color(0xFF161B22),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: Color(0xFF1A73E8), width: 2),
            ),
            prefixIcon:
            const Icon(Icons.pin, color: Colors.white38),
            helperText: '4-stelliger Sensor-Code vom Sensor-Applikator',
            helperStyle:
            const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final DexcomG7Service service;
  final String sensorCode;
  final String txId;
  final bool permissionsGranted;
  final VoidCallback onTxIdChanged;

  const _ActionButtons({
    required this.service,
    required this.sensorCode,
    required this.txId,
    required this.permissionsGranted,
    required this.onTxIdChanged,
  });

  bool get _canConnect =>
      permissionsGranted &&
          sensorCode.length == 4 &&
          txId.length == 12 &&
          service.connectionState != DexConnectionState.scanning &&
          service.connectionState != DexConnectionState.connecting &&
          service.connectionState != DexConnectionState.authenticating &&
          service.connectionState != DexConnectionState.connected;

  bool get _canDisconnect =>
      service.connectionState == DexConnectionState.connected ||
          service.connectionState == DexConnectionState.scanning ||
          service.connectionState == DexConnectionState.connecting ||
          service.connectionState == DexConnectionState.authenticating;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _canConnect
                ? () => service.connect(sensorCode, txId)
                : null,
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text('Verbinden'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        if (_canDisconnect) ...[
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: service.disconnect,
            icon: const Icon(Icons.bluetooth_disabled,
                color: Colors.white54),
            label: const Text('Trennen',
                style: TextStyle(color: Colors.white54)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  vertical: 16, horizontal: 20),
              side: const BorderSide(color: Colors.white24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
        if (service.connectionState == DexConnectionState.connected) ...[
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: service.requestReading,
            icon: const Icon(Icons.refresh, color: Colors.white54),
            label:
            const Text('Lesen', style: TextStyle(color: Colors.white54)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  vertical: 16, horizontal: 20),
              side: const BorderSide(color: Colors.white24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3D0000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF4444).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: Color(0xFFFF4444), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFFF8888),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── HISTORY SCREEN ──────────────────────────────────────────────────────────

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  Color _glucoseColor(int mgdl) {
    if (mgdl < 70) return const Color(0xFFFF4444);
    if (mgdl < 80) return const Color(0xFFFF8800);
    if (mgdl <= 180) return const Color(0xFF44BB44);
    if (mgdl <= 250) return const Color(0xFFFF8800);
    return const Color(0xFFFF4444);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Verlauf',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Consumer<DexcomG7Service>(
        builder: (context, service, _) {
          final history = service.history;

          if (history.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.show_chart,
                      size: 48, color: Colors.white24),
                  SizedBox(height: 16),
                  Text(
                    'Noch keine Messungen',
                    style: TextStyle(color: Colors.white38, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: history.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = history[i];
              final h = r.timestamp.hour.toString().padLeft(2, '0');
              final m = r.timestamp.minute.toString().padLeft(2, '0');
              final color = _glucoseColor(r.glucoseMgdl);

              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white),
                ),
                child: Row(
                  children: [
                    // Zeit
                    SizedBox(
                      width: 48,
                      child: Text(
                        '$h:$m',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    // Wert
                    Text(
                      '${r.glucoseMgdl}',
                      style: TextStyle(
                        color: color,
                        fontSize: 22,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'mg/dL',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                    const Spacer(),
                    // Trend
                    Text(
                      r.trendArrow,
                      style: TextStyle(fontSize: 18, color: color),
                    ),
                    if (r.trendMgdlPerMin != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${r.trendMgdlPerMin! >= 0 ? '+' : ''}'
                            '${r.trendMgdlPerMin!.toStringAsFixed(1)}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}