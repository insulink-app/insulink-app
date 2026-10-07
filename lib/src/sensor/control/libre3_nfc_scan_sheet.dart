import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_sheet.dart';

import '../../localization/locale_text.dart';
import '../../localization/locales.dart';
import 'libre3_scan_icons.dart';

/// Which stage of the Libre 3 NFC flow the [Libre3NfcScanSheet] is showing.
enum Libre3ScanPhase { scanning, success }

/// Bottom sheet for the Libre 3 NFC flow. While [phase] is `scanning` it shows a
/// pulsing ring animation prompting the user to hold the sensor to the phone;
/// once activation succeeds the caller flips [phase] to `success`, the sheet
/// confirms it with a check mark and then closes ITSELF ([onClose]) — the scan is
/// done, so making the user acknowledge it would be a click that waits on
/// nothing. What happens next (BLE scan → handshake → first reading) is the
/// overview's job: it shows its searching state until a value lands. Also
/// dismissed by the caller, the drag handle, the scrim or cancel ([onCancel]).
class Libre3NfcScanSheet extends StatefulWidget {
  const Libre3NfcScanSheet({
    super.key,
    required this.phase,
    required this.onCancel,
    required this.onClose,
  });

  final ValueListenable<Libre3ScanPhase> phase;
  final VoidCallback onCancel;
  final VoidCallback onClose;

  @override
  State<Libre3NfcScanSheet> createState() => _Libre3NfcScanSheetState();
}

class _Libre3NfcScanSheetState extends State<Libre3NfcScanSheet> {
  /// How long the check mark stays up before the sheet closes itself: long
  /// enough to read and register as confirmation (the animation alone runs
  /// 340 ms), short enough that it never feels like waiting.
  static const _successLinger = Duration(milliseconds: 2500);

  Timer? _autoClose;

  @override
  void initState() {
    super.initState();
    widget.phase.addListener(_onPhase);
  }

  void _onPhase() {
    if (widget.phase.value == Libre3ScanPhase.success) {
      _autoClose ??= Timer(_successLinger, widget.onClose);
    }
  }

  @override
  void dispose() {
    widget.phase.removeListener(_onPhase);
    _autoClose?.cancel();
    super.dispose();
  }

  /// An [InkSheet] without a title: the phase's own centred title says what
  /// is going on, and the close button stands alone at the top right.
  @override
  Widget build(BuildContext context) {
    return InkSheet(
      child: ValueListenableBuilder<Libre3ScanPhase>(
        valueListenable: widget.phase,
        builder: (context, phase, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            if (phase == Libre3ScanPhase.scanning)
              ..._scanning()
            else
              ..._success(),
          ],
        ),
      ),
    );
  }

  ColorScheme get _scheme => Theme.of(context).colorScheme;

  List<Widget> _scanning() {
    return [
      const Libre3PulsingIcon(),
      const SizedBox(height: 28),
      _title('sensor.pair.libre.title'),
      const SizedBox(height: 8),
      _subtitle('sensor.pair.libre.scanning'),
      const SizedBox(height: 30),
      _cancelButton(),
    ];
  }

  /// The confirmation the sheet closes on: check mark, what happened, and what
  /// the app does next. No button — [_successLinger] closes it. The trailing gap
  /// stands in for the cancel button, so the sheet keeps its height and the
  /// content doesn't jump when the phase flips.
  List<Widget> _success() {
    return [
      const Libre3CheckIcon(),
      const SizedBox(height: 28),
      _title('sensor.pair.libre.done'),
      const SizedBox(height: 8),
      _subtitle('sensor.pair.libre.connecting'),
      const SizedBox(height: 30),
      const SizedBox(height: 46),
    ];
  }

  Widget _title(String key) {
    return LocaleText(
      key,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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

  /// The only button left in the sheet: aborting the scan. The success view
  /// needs none — it closes itself.
  Widget _cancelButton() {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: widget.onCancel,
        style: TextButton.styleFrom(
          foregroundColor: _scheme.onSurface.withValues(alpha: 0.75),
          backgroundColor: _scheme.onSurface.withValues(alpha: 0.06),
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
        child: Text(Locales.string(context, 'sensor.pair.libre.cancel')),
      ),
    );
  }
}
