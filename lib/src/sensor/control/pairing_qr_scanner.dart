import 'package:flutter/material.dart';
import 'package:insulink/src/base/scanner_torch_button.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../localization/locale_text.dart';
import 'gs1_pairing_code.dart';

/// Full-screen camera that reads the sensor-box code and pops the pairing code.
///
/// Pushed by [scanPairingCode]; pops a `String` pairing code on the first code
/// whose payload carries a GS1 AI-240 element, or null if the user backs out.
/// The Dexcom box uses a **GS1 DataMatrix**, not a QR code, so the scanner is
/// restricted to that format for faster, more reliable detection.
class PairingQrScanner extends StatefulWidget {
  const PairingQrScanner({super.key});

  @override
  State<PairingQrScanner> createState() => _PairingQrScannerState();
}

class _PairingQrScannerState extends State<PairingQrScanner> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.dataMatrix],
    detectionSpeed: DetectionSpeed.normal,
    cameraResolution: const Size(1920, 1080),
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final code = Gs1PairingCode.parse(barcode.rawValue ?? '').value;
      if (code != null) {
        _handled = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [ScannerTorchButton(controller: _controller)],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          const _ScannerHud(),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(32, 0, 32, 48),
              child: LocaleText(
                'sensor.pair.scan_hint',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dims everything outside a centred square viewport and draws corner brackets
/// around it — the HUD frame that guides the box code into focus.
class _ScannerHud extends StatelessWidget {
  const _ScannerHud();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HudPainter(Colors.white),
      child: const SizedBox.expand(),
    );
  }
}

class _HudPainter extends CustomPainter {
  _HudPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.68;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    );
    final window = RRect.fromRectAndRadius(rect, const Radius.circular(20));
    _dimOutside(canvas, size, window);
    _corners(canvas, rect);
  }

  void _dimOutside(Canvas canvas, Size size, RRect window) {
    final overlay = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(window),
    );
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );
  }

  void _corners(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = accent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const arm = 28.0;
    for (final corner in _cornerArms(rect, arm)) {
      canvas.drawPath(corner, paint);
    }
  }

  List<Path> _cornerArms(Rect rect, double arm) {
    return [
      Path()
        ..moveTo(rect.left, rect.top + arm)
        ..lineTo(rect.left, rect.top)
        ..lineTo(rect.left + arm, rect.top),
      Path()
        ..moveTo(rect.right - arm, rect.top)
        ..lineTo(rect.right, rect.top)
        ..lineTo(rect.right, rect.top + arm),
      Path()
        ..moveTo(rect.left, rect.bottom - arm)
        ..lineTo(rect.left, rect.bottom)
        ..lineTo(rect.left + arm, rect.bottom),
      Path()
        ..moveTo(rect.right - arm, rect.bottom)
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.right, rect.bottom - arm),
    ];
  }

  @override
  bool shouldRepaint(_HudPainter oldDelegate) => oldDelegate.accent != accent;
}

/// Opens the scanner and returns the scanned pairing code, or null.
Future<String?> scanPairingCode(BuildContext context) {
  return Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => const PairingQrScanner()));
}
