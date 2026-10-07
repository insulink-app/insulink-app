import 'package:flutter/material.dart';
import 'package:insulink/src/base/restore_offer_card.dart';
import 'package:insulink/src/cgm/cgm_connection.dart';
import 'package:insulink/src/cgm/sensor_sync.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sensor/info/sensor_format.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The overview's offer of the account's stored sensor, as a
/// [RestoreOfferCard]: the sensor type and when it was started, "Nicht jetzt"
/// and "Verwenden". Presentation only; [SensorRestoreOffer] owns when it
/// appears and what the buttons do.
///
/// A Libre 3 needs an NFC scan rather than a plain restore (its BLE PIN is
/// reissued on every scan), so it says so in one line and the button scans.
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

  @override
  Widget build(BuildContext context) {
    return RestoreOfferCard(
      icon: _needsScan ? PhosphorIconsBold.scan : PhosphorIconsBold.drop,
      titleKey: 'overview.restore.title',
      detail: _identity(context),
      hintKey: _needsScan ? 'overview.restore.scan_hint' : null,
      secondaryLabelKey: 'overview.restore.dismiss',
      onSecondary: onDismiss,
      primaryLabelKey: _needsScan
          ? 'overview.restore.scan'
          : 'overview.restore.use',
      onPrimary: onUse,
    );
  }

  /// Which sensor the account has on file: its type and, when known, when it
  /// was started, so the user recognises it before adopting it.
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
}
