import 'package:flutter/material.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/g7/sensor_sync.dart';
import 'package:insulink/src/localization/locale_text.dart';
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
    final restore = await context.read<G7Controller>().availableBackendSensor(
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
    await context.read<G7Controller>().restoreSensor(offer);
  }

  Future<void> _dismiss() async {
    final offer = _offer;
    if (offer == null) {
      return;
    }
    setState(() => _offer = null);
    await context.read<G7Controller>().dismissRestore(offer.sensorId);
  }

  @override
  Widget build(BuildContext context) {
    if (_offer == null) {
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
                Icon(Icons.cloud_download_outlined, color: scheme.primary),
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
