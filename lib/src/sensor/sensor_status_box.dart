import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../g7/g7_controller.dart';
import '../localization/locale_text.dart';
import '../profile/profile_glucose_state.dart';
import 'sensor_life_bar.dart';
import 'sensor_session_controls.dart';

/// Standard G7 lifetime (10 days + 12 h grace), used when the sensor hasn't
/// reported its own session length yet.
const int _defaultSessionLengthSec = 907200;

/// Box shown once paired: connection status header plus the session controls.
/// While [searching] (connected but no reading yet) the header shows a spinner.
class SensorStatusBox extends StatelessWidget {
  const SensorStatusBox({
    super.key,
    required this.controller,
    required this.searching,
  });

  final G7Controller controller;
  final bool searching;

  bool get _connected => controller.connected;

  /// Best-effort session length: the sensor's reported value, else its max
  /// lifetime, else the standard G7 lifetime — so the life bar always renders.
  int get _sessionLengthSec {
    final info = controller.info;
    if (info.sessionLengthSec != null) {
      return info.sessionLengthSec!;
    }
    if (info.maxLifetimeDays != null) {
      return info.maxLifetimeDays! * 86400;
    }
    return _defaultSessionLengthSec;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, scheme),
          if (controller.sensorStart != null) ...[
            const SizedBox(height: 18),
            SensorLifeBar(
              start: controller.sensorStart!,
              sessionLengthSec: _sessionLengthSec,
            ),
          ],
          const SizedBox(height: 16),
          SensorSessionControls(controller: controller),
        ],
      ),
    );
  }

  /// Neutral status accent: strong onSurface when live, dimmed when offline.
  Color _accent(ColorScheme scheme) {
    final alpha = (_connected || searching) ? 0.8 : 0.35;
    return scheme.onSurface.withValues(alpha: alpha);
  }

  Widget _header(BuildContext context, ColorScheme scheme) {
    return Row(
      children: [
        _statusIcon(scheme),
        const SizedBox(width: 14),
        Expanded(child: _titles(context)),
      ],
    );
  }

  Widget _statusIcon(ColorScheme scheme) {
    final accent = _accent(scheme);
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.15),
      ),
      child: searching ? _spinner(accent) : _stateIcon(accent),
    );
  }

  Widget _spinner(Color accent) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: CircularProgressIndicator(strokeWidth: 3, color: accent),
    );
  }

  Widget _stateIcon(Color accent) {
    return Icon(
      _connected
          ? CupertinoIcons.dot_radiowaves_left_right
          : CupertinoIcons.drop,
      size: 32,
      color: accent,
    );
  }

  Widget _titles(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocaleText(
          _titleKey,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        _subtitle(context),
      ],
    );
  }

  String get _titleKey {
    if (searching) {
      return 'sensor.status.searching';
    }
    return _connected
        ? 'sensor.status.connected'
        : 'sensor.status.disconnected';
  }

  Widget _subtitle(BuildContext context) {
    final dimmed = TextStyle(fontSize: 13, color: Colors.grey[500]);
    if (searching) {
      return LocaleText('sensor.searching.hint', style: dimmed);
    }
    if (_connected && controller.currentMgdl != null) {
      final glucose = context.watch<ProfileGlucoseState>();
      return Text(
        glucose.formatWithUnit(controller.currentMgdl!),
        style: dimmed,
      );
    }
    final key = controller.hasSensor
        ? 'sensor.status.paired'
        : 'sensor.status.unpaired';
    return LocaleText(key, style: dimmed);
  }
}
