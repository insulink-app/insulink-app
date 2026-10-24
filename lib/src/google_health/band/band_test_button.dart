import 'dart:async';

import 'package:flutter/material.dart';
import 'package:insulink/src/google_health/band/band_haptics.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/notifications/alarm_tone.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

enum _PreviewState { idle, busy, felt, failed }

/// A quiet vibration test, an icon button like the pump's test beep: [slot]'s
/// pattern on the band, or with no slot two plain pulses (the device page's
/// "is the band reachable"). The glyph itself says how it went (check or
/// warning) for a few seconds, no SnackBar (docs/DESIGN.md).
class BandTestButton extends StatefulWidget {
  const BandTestButton({super.key, this.slot});

  final AlarmSlot? slot;

  @override
  State<BandTestButton> createState() => _BandTestButtonState();
}

class _BandTestButtonState extends State<BandTestButton> {
  _PreviewState _state = _PreviewState.idle;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: Locales.string(
        context,
        widget.slot == null ? 'google_health.band.test' : 'profile.band_vibration.preview',
      ),
      onPressed: _state == _PreviewState.busy ? null : _preview,
      icon: switch (_state) {
        _PreviewState.idle => const Icon(PhosphorIconsBold.vibrate),
        _PreviewState.busy => const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        _PreviewState.felt => Icon(PhosphorIconsBold.check, color: context.positive),
        _PreviewState.failed => Icon(PhosphorIconsBold.warning, color: context.danger),
      },
    );
  }

  Future<void> _preview() async {
    _reset?.cancel();
    setState(() => _state = _PreviewState.busy);
    final slot = widget.slot;
    final haptics = BandHaptics();
    final felt = await (slot == null ? haptics.vibrate() : haptics.preview(slot));
    if (!mounted) {
      return;
    }
    setState(() => _state = felt ? _PreviewState.felt : _PreviewState.failed);
    _reset = Timer(const Duration(seconds: 3), () => setState(() => _state = _PreviewState.idle));
  }
}
