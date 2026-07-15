import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/cgm/sensor_sync.dart';
import 'package:insulink/src/overview/sensor_restore_card.dart';
import 'package:insulink/src/sensor/control/libre3_scan_flow.dart';
import 'package:provider/provider.dart';

/// Shown on the overview when no sensor is set up locally but the account has
/// one on file (typically right after a reinstall): offers to adopt that sensor
/// without re-pairing. Renders nothing until the backend confirms one exists.
/// [SensorRestoreCard] draws it; this owns the offer + what the buttons do.
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

  /// Adopt the offered sensor. A Libre 3 can't be reconnected from stored
  /// credentials — the sensor reissues its BLE PIN on every NFC scan and honours
  /// only the latest one — so restoring its identity is followed straight by the
  /// NFC scan sheet that fetches a fresh PIN.
  Future<void> _use() async {
    final offer = _offer;
    if (offer == null) {
      return;
    }
    setState(() => _offer = null);
    final controller = context.read<CgmController>();
    final reading = await controller.restoreSensor(offer);
    if (reading || !mounted) {
      return;
    }
    await Libre3ScanFlow(controller: controller).run(context);
  }

  Future<void> _dismiss() async {
    final offer = _offer;
    if (offer == null) {
      return;
    }
    setState(() => _offer = null);
    await context.read<CgmController>().dismissRestore(offer.sensorId);
  }

  @override
  Widget build(BuildContext context) {
    final offer = _offer;
    if (offer == null) {
      return const SizedBox.shrink();
    }
    return SensorRestoreCard(offer: offer, onUse: _use, onDismiss: _dismiss);
  }
}
