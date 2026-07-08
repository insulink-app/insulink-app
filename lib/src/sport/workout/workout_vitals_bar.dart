import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/google_health/fitbit_heart_rate_monitor.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:provider/provider.dart';

/// Compact live-vitals strip for the running routine: current glucose (from the
/// G7 pipeline) and live pulse (from the worn Fitbit). Kicks off the BLE pulse
/// reader when mounted so the workout page shows a live bpm without the user
/// visiting the heart-rate page first.
class WorkoutVitalsBar extends StatefulWidget {
  const WorkoutVitalsBar({super.key});

  @override
  State<WorkoutVitalsBar> createState() => _WorkoutVitalsBarState();
}

class _WorkoutVitalsBarState extends State<WorkoutVitalsBar> {
  FitbitHeartRateMonitor get _monitor =>
      context.read<GoogleHealthState>().liveHrMonitor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _monitor.start());
  }

  @override
  void dispose() {
    _monitor.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = context.watch<CgmController>();
    final glucose = context.watch<ProfileGlucoseState>();
    final mgdl = controller.currentMgdl;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _reading(
            Icons.water_drop,
            scheme.primary,
            mgdl == null ? '–' : glucose.formatWithUnit(mgdl),
          ),
          ListenableBuilder(
            listenable: _monitor,
            builder: (context, _) {
              final live = _monitor.status == FitbitHrStatus.streaming;
              return _reading(
                Icons.favorite,
                live ? scheme.error : scheme.onSurface.withValues(alpha: 0.3),
                live && _monitor.bpm != null ? '${_monitor.bpm} bpm' : '–',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _reading(IconData icon, Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      ],
    );
  }
}