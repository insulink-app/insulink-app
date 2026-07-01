import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/training/cardio_map.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_tracker.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

/// Live-Aufzeichnung eines Ausdauer-Trainings: Karte mit der laufenden Route,
/// Dauer/Distanz/Tempo und ein Stopp-Button, der das Training speichert.
class CardioRecordingPage extends StatefulWidget {
  const CardioRecordingPage({super.key, required this.type});

  final CardioType type;

  @override
  State<CardioRecordingPage> createState() => _CardioRecordingPageState();
}

class _CardioRecordingPageState extends State<CardioRecordingPage> {
  late final CardioTracker _tracker = CardioTracker(widget.type);
  final MapController _map = MapController();

  @override
  void initState() {
    super.initState();
    _tracker.addListener(_recenter);
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  Future<void> _begin() async {
    if (await _tracker.start() || !mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(Locales.string(context, 'sport.trainings.location_denied'))),
    );
    Navigator.of(context).pop();
  }

  void _recenter() {
    final latest = _tracker.latest;
    if (latest != null) {
      _map.move(LatLng(latest.lat, latest.lng), _map.camera.zoom);
    }
  }

  Future<void> _stop() async {
    final training = _tracker.finish();
    await context.read<CardioTrainingState>().addTraining(training);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _tracker.removeListener(_recenter);
    _tracker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText(widget.type.labelKey),
      ),
      body: Stack(
        children: [
          ListenableBuilder(
            listenable: _tracker,
            builder: (context, _) => CardioMap(
              controller: _map,
              points: _tracker.points,
              live: true,
            ),
          ),
          Align(alignment: Alignment.bottomCenter, child: _panel(context)),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12)],
      ),
      child: ListenableBuilder(
        listenable: _tracker,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _metric(context, 'sport.trainings.duration', formatDuration(_tracker.elapsed)),
                _metric(context, 'sport.trainings.distance', formatDistanceKm(_tracker.distanceM)),
                _metric(context, 'sport.trainings.speed', formatSpeed(_tracker.currentSpeedKmh)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: scheme.error),
                icon: const Icon(Icons.stop_rounded, size: 28),
                label: LocaleText(
                  'sport.trainings.stop',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: _stop,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String labelKey, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(
          Locales.string(context, labelKey),
          style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.6)),
        ),
      ],
    );
  }
}
