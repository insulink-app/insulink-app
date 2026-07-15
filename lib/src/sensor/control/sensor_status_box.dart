import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../cgm/cgm_connection.dart';
import '../../cgm/cgm_controller.dart';
import '../../localization/locale_text.dart';
import '../../localization/locales.dart';
import '../../profile/glucose/profile_glucose_state.dart';
import 'sensor_life_bar.dart';
import 'sensor_session_controls.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Box shown once paired: connection status header plus the session controls.
/// While [searching] (connected but no reading yet) the header shows a spinner.
class SensorStatusBox extends StatelessWidget {
  const SensorStatusBox({
    super.key,
    required this.controller,
    required this.searching,
  });

  final CgmController controller;
  final bool searching;

  bool get _connected => controller.connected;

  /// Best-effort session length: the sensor's reported value, else its max
  /// lifetime, else the active sensor's nominal lifetime (G7 ~10 d, Libre 3
  /// 14 d) — so the life bar always renders with the right total.
  int get _sessionLengthSec {
    final info = controller.info;
    if (info.sessionLengthSec != null) {
      return info.sessionLengthSec!;
    }
    if (info.maxLifetimeDays != null) {
      return info.maxLifetimeDays! * 86400;
    }
    return controller.sensorType.sessionLengthSec;
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
      _connected ? PhosphorIconsRegular.broadcast : PhosphorIconsRegular.drop,
      size: 32,
      color: accent,
    );
  }

  /// The sensor type is the headline (prominent), with connection state + the
  /// live value on the dimmed line below.
  Widget _titles(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocaleText(
          _typeKey,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        _subtitle(context),
      ],
    );
  }

  String get _typeKey => controller.sensorType == SensorType.abbottLibre3
      ? 'sensor.type.libre3'
      : 'sensor.type.g7';

  String get _statusKey {
    if (searching) {
      return 'sensor.status.searching';
    }
    return _connected
        ? 'sensor.status.connected'
        : 'sensor.status.disconnected';
  }

  Widget _subtitle(BuildContext context) {
    final dimmed = TextStyle(
      fontSize: 13,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final status = Locales.string(context, _statusKey);
    if (_connected && controller.currentMgdl != null) {
      final glucose = context.watch<ProfileGlucoseState>();
      final value = glucose.formatWithUnit(controller.currentMgdl!);
      return Text('$status · $value', style: dimmed);
    }
    return Text(status, style: dimmed);
  }
}
