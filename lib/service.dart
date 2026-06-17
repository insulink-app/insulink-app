import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'protocol.dart';
import 'keks.dart';

enum DexConnectionState {
  idle,
  scanning,
  connecting,
  authenticating,
  connected,
  error,
  disconnected,
}

class DexcomReading {
  final int glucoseMgdl;
  final DateTime timestamp;
  final String trendArrow;
  final double? trendMgdlPerMin;
  final int? predictedGlucose;
  final bool isWarmingUp;

  const DexcomReading({
    required this.glucoseMgdl,
    required this.timestamp,
    required this.trendArrow,
    required this.trendMgdlPerMin,
    required this.predictedGlucose,
    required this.isWarmingUp,
  });
}

class DexcomG7Service extends ChangeNotifier {
  // ─── State ───────────────────────────────────────────────────────────────
  DexConnectionState _connectionState = DexConnectionState.idle;
  String _statusMessage = 'Bereit';
  DexcomReading? _lastReading;
  final List<DexcomReading> _history = [];
  String? _errorMessage;

  DexConnectionState get connectionState => _connectionState;
  String get statusMessage => _statusMessage;
  DexcomReading? get lastReading => _lastReading;
  List<DexcomReading> get history => List.unmodifiable(_history);
  String? get errorMessage => _errorMessage;

  // ─── BLE Internals ───────────────────────────────────────────────────────
  BluetoothDevice? _device;
  BluetoothCharacteristic? _authChar;
  BluetoothCharacteristic? _controlChar;
  StreamSubscription? _authSubscription;
  StreamSubscription? _controlSubscription;
  StreamSubscription? _deviceStateSubscription;
  StreamSubscription? _scanSubscription;

  String _sensorCode = '';

  // EC-J-PAKE-Authentifizierung (moderner G7). Der Legacy-AES-Handshake aus
  // protocol.dart wird vom aktuellen G7 nicht akzeptiert (siehe keks.dart).
  KeksPlugin? _keks;

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Startet den Scan und verbindet sich mit dem G7.
  /// [sensorCode]: 4-stelliger Pairing-Code vom Sensor-Applikator — dient als
  /// J-PAKE-Passwort. [serialNumber] wird für die Authentifizierung nicht
  /// benötigt (anders als beim Legacy-AES-Verfahren), nur zur Anzeige/Diagnose.
  Future<void> connect(String sensorCode, String serialNumber) async {
    if (_connectionState == DexConnectionState.scanning ||
        _connectionState == DexConnectionState.connecting) return;

    _sensorCode = sensorCode;
    debugPrint('Verbinde — Pairing-Code: $sensorCode, SN: $serialNumber');
    await _reset();
    _setState(DexConnectionState.scanning, 'Suche nach Sensor...');

    // Warte kurz damit BLE bereit ist
    await Future.delayed(const Duration(milliseconds: 500));

    await FlutterBluePlus.startScan(
      //withServices: [Guid(DexcomUUIDs.cgmService)],
      //timeout: const Duration(seconds: 30),
    );

    _scanSubscription = FlutterBluePlus.scanResults.listen(
          (results) {
        for (final r in results) {
          final name = r.device.platformName;
          // G7 advertised names: DXCM, DX02, DX01
          if (name != "") {
            debugPrint(name);
          }
          if (name.startsWith('DXCM') ||
              name.startsWith('DX02') ||
              name.startsWith('DX01')) {
            _onSensorFound(r.device);
            return;
          }
        }
      },
      onError: (e) => _setError('Scan-Fehler: $e'),
    );
  }

  Future<void> disconnect() async {
    await _reset();
    _setState(DexConnectionState.idle, 'Getrennt');
  }

  Future<void> requestReading() async {
    if (_connectionState != DexConnectionState.connected ||
        _controlChar == null) {
      _setError('Nicht verbunden');
      return;
    }
    _setState(DexConnectionState.connected, 'Lese Glukosewert...');
    try {
      await _controlChar!.write(EGlucoseTx().bytes, withoutResponse: false);
    } catch (e) {
      _setError('Fehler beim Lesen: $e');
    }
  }

  // ─── Scan → Verbindung ───────────────────────────────────────────────────

  Future<void> _onSensorFound(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;

    _device = device;
    _setState(DexConnectionState.connecting,
        'Sensor gefunden: ${device.platformName}\nVerbinde...');

    _deviceStateSubscription =
        device.connectionState.listen(_onDeviceStateChange);

    try {
      await device.connect(
        timeout: const Duration(seconds: 15),
        license: License.nonprofit,
        mtu: null, // kein automatisches MTU-Request, kostet Zeit im kurzen Auth-Fenster des Sensors
      );
    } catch (e) {
      _setError('Verbindungsfehler: $e');
    }
  }

  void _onDeviceStateChange(BluetoothConnectionState state) {
    if (state == BluetoothConnectionState.connected) {
      _onConnected();
    } else if (state == BluetoothConnectionState.disconnected) {
      if (_connectionState != DexConnectionState.idle) {
        _setState(DexConnectionState.disconnected, 'Verbindung getrennt');
      }
    }
  }

  Future<void> _onConnected() async {
    _setState(DexConnectionState.authenticating, 'Verbunden, authentifiziere...');

    try {
      // Niedrige Latenz anfordern, bevor weitere GATT-Operationen laufen -
      // sonst terminiert der Sensor die Verbindung wieder selbst.
      try {
        await _device!.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
      } catch (_) {}

      // Services entdecken
      final services = await _device!.discoverServices();
      final cgmService = services.firstWhere(
            (s) => s.serviceUuid == Guid(DexcomUUIDs.cgmService),
        orElse: () => throw Exception('CGM Service nicht gefunden'),
      );

      // Characteristics finden
      _authChar = cgmService.characteristics.firstWhere(
            (c) => c.characteristicUuid == Guid(DexcomUUIDs.authentication),
        orElse: () => throw Exception('Auth Characteristic nicht gefunden'),
      );
      _controlChar = cgmService.characteristics.firstWhere(
            (c) => c.characteristicUuid == Guid(DexcomUUIDs.control),
        orElse: () => throw Exception('Control Characteristic nicht gefunden'),
      );

      // Auth starten
      await _startAuthentication();
    } catch (e) {
      _setError('Setup-Fehler: $e');
    }
  }

  // ─── Authentifizierung ───────────────────────────────────────────────────

  Future<void> _startAuthentication() async {
    // Der Pairing-Code (sensorCode) ist das J-PAKE-Passwort. Die Seriennummer
    // fließt — anders als beim Legacy-AES-Verfahren — NICHT in den Schlüssel.
    _keks = KeksPlugin(_sensorCode);

    // WICHTIG: Der G7 hat ein sehr kurzes Verbindungsfenster nach dem Connect
    // und terminiert selbst, wenn nicht sofort der Auth-Handshake beginnt
    // (frühes Notify auf der Control-Characteristic reicht schon zum Abbruch).
    // Daher: Control-Notify erst NACH erfolgreicher Auth aktivieren und die
    // erste keks-Nachricht parallel zum Auth-Notify schreiben (wie Legacy).
    _authSubscription = _authChar!.lastValueStream
        .listen((data) => _onAuthData(Uint8List.fromList(data)));

    _keks!.amConnected();
    final firstOutputs = _keks!.aNext();

    await Future.wait([
      _authChar!.setNotifyValue(true),
      _writeOutputs(firstOutputs),
    ]);
  }

  /// Schreibt keks-Nachrichten auf die passende Characteristic. J-PAKE-/Auth-
  /// Nachrichten gehen an die Authentication-Characteristic, das GETDATA-
  /// Kommando (0x4e) an Control.
  ///
  /// HINWEIS: Die genaue BLE-Choreografie (welche Characteristic, Long-Write-
  /// Fragmentierung der 160-Byte-Pakete) ist mangels Referenztreiber aus xDrip
  /// nicht am Gerät verifiziert und muss ggf. am echten Sensor justiert werden.
  Future<void> _writeOutputs(List<Uint8List?> outputs) async {
    for (final out in outputs) {
      if (out == null || out.isEmpty) continue;
      final toControl = out[0] == Opcode.eGlucoseTx; // 0x4e -> Control
      final ch = toControl ? _controlChar! : _authChar!;
      debugPrint('keks TX (${toControl ? "control" : "auth"}): '
          '${_bytesToHex(out)}');
      try {
        await ch.write(out,
            withoutResponse: false, allowLongWrite: out.length > 20);
      } catch (e) {
        _setError('Auth-Schreibfehler: $e');
        return;
      }
    }
  }

  Future<void> _pumpKeks() => _writeOutputs(_keks!.aNext());

  /// J-PAKE erfolgreich: jetzt erst Control-Notifications aktivieren (vorher
  /// würde der Sensor die Verbindung abbrechen), dann das GETDATA-Kommando
  /// senden. Die Glukose-Antwort kommt anschließend über die Control-Char.
  Future<void> _onKeksAuthenticated() async {
    _setState(DexConnectionState.connected, 'Verbunden ✓');
    try {
      await _controlChar!.setNotifyValue(true);
      _controlSubscription = _controlChar!.lastValueStream
          .listen((data) => _onControlData(Uint8List.fromList(data)));
    } catch (e) {
      _setError('Fehler beim Aktivieren der Glukose-Notifications: $e');
      return;
    }
    await _pumpKeks(); // sendet GETDATA
  }

  void _onAuthData(Uint8List data) {
    if (data.isEmpty || _keks == null) return;
    debugPrint('keks RX (state=${_keks!.state.name}): ${_bytesToHex(data)}');

    final st = _keks!.state;
    try {
      switch (st) {
        case KeksState.round1:
        case KeksState.round2:
        case KeksState.round3:
          // J-PAKE-Runden-Pakete (evtl. fragmentiert) sammeln.
          if (_keks!.receivedData(data)) {
            _pumpKeks();
          }
        case KeksState.requestAuth:
        case KeksState.challengeReply:
          final cont = _keks!.receivedResponse(data);
          final now = _keks!.state;
          if (now == KeksState.getData || now == KeksState.getData2) {
            // J-PAKE erfolgreich + gebondet.
            _onKeksAuthenticated();
            return;
          }
          if (st == KeksState.challengeReply &&
              (now == KeksState.unknown || now == KeksState.bondFailure)) {
            _setError('Authentifizierung fehlgeschlagen (J-PAKE).\n'
                'Falscher Pairing-Code?');
            return;
          }
          if (cont) _pumpKeks();
        default:
          debugPrint('keks: unerwarteter Zustand ${st.name}');
      }
    } on KeksCertificateRequired catch (e) {
      _setError('Erstmaliges Pairing erforderlich (Zertifikat/QR).\n'
          'Dieser Pfad ist noch nicht implementiert.\n$e');
    } catch (e) {
      _setError('Auth-Fehler: $e');
    }
  }

  // ─── Glucose Notifications ───────────────────────────────────────────────

  void _onControlData(Uint8List data) {
    if (data.isEmpty) return;
    debugPrint('Control Daten: ${_bytesToHex(data)}');

    final packet = classifyPacket(data);

    if (packet case GlucosePacket(:final msg)) {
      _processGlucose(msg);
    } else {
      debugPrint('Unbekanntes Control-Paket: ${_bytesToHex(data)}');
    }
  }

  void _processGlucose(EGlucoseRx glucose) {
    debugPrint(glucose.toString());

    if (glucose.isWarmingUp) {
      _setState(DexConnectionState.connected,
          'Sensor wärmt auf\nBitte warte ca. 30 Minuten');
      return;
    }

    if (!glucose.isUsable) {
      _setState(DexConnectionState.connected,
          'Kein gültiger Wert\nStatus: ${glucose.calibrationStateText}');
      return;
    }

    final reading = DexcomReading(
      glucoseMgdl: glucose.glucose,
      timestamp: glucose.timestamp,
      trendArrow: glucose.trendArrow,
      trendMgdlPerMin: glucose.trendMgdlPerMin,
      predictedGlucose: glucose.predictedGlucose,
      isWarmingUp: glucose.isWarmingUp,
    );

    _lastReading = reading;
    _history.insert(0, reading);
    if (_history.length > 288) _history.removeLast(); // max 24h

    _setState(DexConnectionState.connected,
        'Letzter Wert: ${glucose.timestamp.hour.toString().padLeft(2, '0')}:'
            '${glucose.timestamp.minute.toString().padLeft(2, '0')}');

    notifyListeners();
  }

  // ─── Hilfsfunktionen ─────────────────────────────────────────────────────

  Future<void> _reset() async {
    await _scanSubscription?.cancel();
    await _authSubscription?.cancel();
    await _controlSubscription?.cancel();
    await _deviceStateSubscription?.cancel();
    _scanSubscription = null;
    _authSubscription = null;
    _controlSubscription = null;
    _deviceStateSubscription = null;

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    try {
      await _device?.disconnect();
    } catch (_) {}

    _device = null;
    _authChar = null;
    _controlChar = null;
    _keks = null;
    _errorMessage = null;
  }

  void _setState(DexConnectionState state, String message) {
    _connectionState = state;
    _statusMessage = message;
    _errorMessage = null;
    notifyListeners();
  }

  void _setError(String message) {
    _connectionState = DexConnectionState.error;
    _statusMessage = 'Fehler';
    _errorMessage = message;
    notifyListeners();
    debugPrint(message);
  }

  static String _bytesToHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  @override
  void dispose() {
    _reset();
    super.dispose();
  }
}