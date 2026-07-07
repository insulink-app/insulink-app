import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../cgm/cgm_controller.dart';
import '../../localization/locale_text.dart';
import '../../localization/locales.dart';

/// Which stage of the Libre 3 NFC flow the [Libre3NfcScanSheet] is showing.
enum Libre3ScanPhase { scanning, success }

/// Bottom sheet for the Libre 3 NFC flow. While [phase] is `scanning` it shows a
/// pulsing ring animation prompting the user to hold the sensor to the phone;
/// once activation succeeds the caller flips [phase] to `success` and the sheet
/// confirms it, then tracks the background BLE connection live. Dismissed by the
/// caller, the drag handle, the scrim, the cancel button ([onCancel]) or the
/// done button ([onClose]).
class Libre3NfcScanSheet extends StatefulWidget {
  const Libre3NfcScanSheet({
    super.key,
    required this.phase,
    required this.controller,
    required this.onCancel,
    required this.onClose,
  });

  final ValueListenable<Libre3ScanPhase> phase;
  final CgmController controller;
  final VoidCallback onCancel;
  final VoidCallback onClose;

  @override
  State<Libre3NfcScanSheet> createState() => _Libre3NfcScanSheetState();
}

class _Libre3NfcScanSheetState extends State<Libre3NfcScanSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: ValueListenableBuilder<Libre3ScanPhase>(
          valueListenable: widget.phase,
          builder: (context, phase, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _grabber(),
              const SizedBox(height: 28),
              if (phase == Libre3ScanPhase.scanning)
                ..._scanning()
              else
                ..._success(),
            ],
          ),
        ),
      ),
    );
  }

  ColorScheme get _scheme => Theme.of(context).colorScheme;

  Widget _grabber() {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: _scheme.onSurface.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  List<Widget> _scanning() {
    return [
      _pulsingIcon(),
      const SizedBox(height: 32),
      LocaleText(
        'sensor.pair.libre.title',
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      _subtitle('sensor.pair.libre.scanning'),
      const SizedBox(height: 28),
      _button('sensor.pair.libre.cancel', widget.onCancel, filled: false),
    ];
  }

  List<Widget> _success() {
    return [
      _checkIcon(),
      const SizedBox(height: 32),
      LocaleText(
        'sensor.pair.libre.done',
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 14),
      AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => _connectionStatus(),
      ),
      const SizedBox(height: 28),
      _button('alert.done', widget.onClose, filled: true),
    ];
  }

  /// Live BLE status shown under the success confirmation: a spinner while the
  /// background service is still handshaking, a green check once glucose streams.
  Widget _connectionStatus() {
    final live = widget.controller.latestIsLive;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (live)
          Icon(Icons.check_circle, size: 18, color: _scheme.primary)
        else
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: _scheme.primary),
          ),
        const SizedBox(width: 10),
        LocaleText(
          live ? 'sensor.pair.libre.connected' : 'sensor.pair.libre.connecting',
          style: TextStyle(
            fontSize: 14,
            color: _scheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _subtitle(String key) {
    return LocaleText(
      key,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 14,
        color: _scheme.onSurface.withValues(alpha: 0.6),
      ),
    );
  }

  Widget _button(String key, VoidCallback onTap, {required bool filled}) {
    final child = SizedBox(
      width: double.infinity,
      child: filled
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(Locales.string(context, key)),
            )
          : TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                foregroundColor: _scheme.onSurface.withValues(alpha: 0.75),
                backgroundColor: _scheme.onSurface.withValues(alpha: 0.06),
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
              child: Text(Locales.string(context, key)),
            ),
    );
    return child;
  }

  /// A check mark that scales+fades in once, marking the switch to success.
  Widget _checkIcon() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
      ),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _scheme.primary.withValues(alpha: 0.14),
        ),
        child: Icon(Icons.check_rounded, size: 46, color: _scheme.primary),
      ),
    );
  }

  /// An NFC icon wrapped in two rings that expand and fade outward on a loop.
  Widget _pulsingIcon() {
    return SizedBox(
      width: 140,
      height: 140,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              _ring(_pulse.value),
              _ring((_pulse.value + 0.5) % 1.0),
              child!,
            ],
          );
        },
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _scheme.primary.withValues(alpha: 0.12),
          ),
          child: Icon(Icons.nfc, size: 38, color: _scheme.primary),
        ),
      ),
    );
  }

  Widget _ring(double progress) {
    final size = 72.0 + progress * 68.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: _scheme.primary.withValues(alpha: (1 - progress) * 0.4),
          width: 2,
        ),
      ),
    );
  }
}
