import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_connection.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/cgm/sensor_sync.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sensor/info/sensor_format.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Shown on the overview when no sensor is set up locally but the account has
/// one on file (typically right after a reinstall): offers to adopt that sensor
/// without re-pairing. Renders nothing until the backend confirms one exists.
class SensorRestoreOffer extends StatefulWidget {
  const SensorRestoreOffer({super.key});

  @override
  State<SensorRestoreOffer> createState() => _SensorRestoreOfferState();
}

class _SensorRestoreOfferState extends State<SensorRestoreOffer> {
  SensorRestore? _offer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final restore = await context.read<CgmController>().availableBackendSensor(
      context,
    );
    if (mounted) {
      setState(() => _offer = restore);
    }
  }

  Future<void> _use() async {
    final offer = _offer;
    if (offer == null) {
      return;
    }
    setState(() => _offer = null);
    await context.read<CgmController>().restoreSensor(offer);
  }

  Future<void> _dismiss() async {
    final offer = _offer;
    if (offer == null) {
      return;
    }
    setState(() => _offer = null);
    await context.read<CgmController>().dismissRestore(offer.sensorId);
  }

  /// Which sensor the account has on file: its type and — when known — when it
  /// was started, so the user recognises the sensor before adopting it.
  Widget _details(
    BuildContext context,
    ColorScheme scheme,
    SensorRestore offer,
  ) {
    final typeKey = offer.sensorType == SensorType.abbottLibre3
        ? 'sensor.type.libre3'
        : 'sensor.type.g7';
    final parts = <String>[Locales.string(context, typeKey)];
    final startMs = offer.sensorStartMs;
    if (startMs != null) {
      final started = formatSensorDateTime(
        DateTime.fromMillisecondsSinceEpoch(startMs),
      );
      parts.add('${Locales.string(context, 'sensor.field.started')} $started');
    }
    return Row(
      children: [
        Icon(
          PhosphorIconsRegular.broadcast,
          size: 16,
          color: scheme.onSurface.withValues(alpha: 0.55),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            parts.join(' · '),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final offer = _offer;
    if (offer == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(PhosphorIconsRegular.cloudArrowDown, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: LocaleText(
                    'overview.restore.title',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LocaleText(
              'overview.restore.body',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 10),
            _details(context, scheme, offer),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _dismiss,
                  child: LocaleText('overview.restore.dismiss'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: _use,
                  child: LocaleText('overview.restore.use'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
