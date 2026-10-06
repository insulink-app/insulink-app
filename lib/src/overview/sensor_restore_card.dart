import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_connection.dart';
import 'package:insulink/src/cgm/sensor_sync.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/sensor/info/sensor_format.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The overview card offering the account's stored sensor: icon badge, title,
/// the sensor's identity, and the adopt/dismiss actions. Presentation only —
/// [SensorRestoreOffer] owns when it appears and what the buttons do.
///
/// A Libre 3 needs an NFC scan rather than a plain restore (its BLE PIN is
/// reissued on every scan), so the copy and both icons switch to say so.
class SensorRestoreCard extends StatelessWidget {
  const SensorRestoreCard({
    super.key,
    required this.offer,
    required this.onUse,
    required this.onDismiss,
  });

  final SensorRestore offer;
  final VoidCallback onUse;
  final VoidCallback onDismiss;

  bool get _needsScan => offer.sensorType == SensorType.abbottLibre3;

  IconData get _icon =>
      _needsScan ? PhosphorIconsBold.scan : PhosphorIconsBold.cloudArrowDown;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        InkPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, scheme),
              const SizedBox(height: 12),
              LocaleText(
                _needsScan
                    ? 'overview.restore.body_scan'
                    : 'overview.restore.body',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 16),
              _actions(),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// Title + identity line behind the same filled circular icon badge the empty
  /// states use. The icon says what the button will do: adopt from the cloud, or
  /// hold the phone against the sensor.
  Widget _header(BuildContext context, ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Icon(_icon, size: 21, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              LocaleText(
                'overview.restore.title',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _identity(context),
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Which sensor the account has on file: its type and — when known — when it
  /// was started, so the user recognises the sensor before adopting it.
  String _identity(BuildContext context) {
    final typeKey = _needsScan ? 'sensor.type.libre3' : 'sensor.type.g7';
    final parts = <String>[Locales.string(context, typeKey)];
    final startMs = offer.sensorStartMs;
    if (startMs != null) {
      final started = formatSensorDateTime(
        DateTime.fromMillisecondsSinceEpoch(startMs),
      );
      parts.add('${Locales.string(context, 'sensor.field.started')} $started');
    }
    return parts.join(' · ');
  }

  /// Adopt (primary, wider) and dismiss, same height so they read as one bar.
  Widget _actions() {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: onDismiss,
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            child: LocaleText('overview.restore.dismiss'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: onUse,
            icon: Icon(_icon, size: 18),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            label: LocaleText(
              _needsScan ? 'overview.restore.scan' : 'overview.restore.use',
            ),
          ),
        ),
      ],
    );
  }
}
