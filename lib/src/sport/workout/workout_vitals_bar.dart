import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/cgm/glucose_trend_icon.dart';
import 'package:insulink/src/google_health/fitbit_heart_rate_monitor.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Compact live-vitals strip for the running routine: current glucose (from the
/// G7 pipeline, stained by its target band and carrying the same trend arrow as
/// the overview headline) and live pulse (from the worn Fitbit, stained by its
/// zone). Kicks off the BLE pulse reader when mounted so the workout page shows
/// a live bpm without the user visiting the heart-rate page first.
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

  /// The palette the big overview readout uses, so a glanced-at value mid-set
  /// reads the same colour as on the overview page.
  GlucoseColors get _colors => Theme.of(context).brightness == Brightness.dark
      ? GlucoseColors.headlineDark
      : GlucoseColors.headlineLight;

  /// ponytail: fixed pulse zones (normal / elevated / high) — there is no
  /// HR-zone setting yet; wire it up once the profile grows one.
  Color _pulseColor(int bpm) {
    if (bpm < 100) {
      return _colors.inRange;
    }
    if (bpm < 140) {
      return _colors.high;
    }
    return _colors.low;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = context.watch<CgmController>();
    final glucose = context.watch<ProfileGlucoseState>();
    final mgdl = controller.currentMgdl;
    // A stale (cached, not live) value is grey, matching the overview headline.
    final glucoseColor = (mgdl == null || controller.currentIsStale)
        ? Colors.grey
        : _colors.forValue(mgdl, glucose);
    final trend = controller.displayTrendPerMin;
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
            PhosphorIconsRegular.drop,
            glucoseColor,
            mgdl == null ? '–' : glucose.formatWithUnit(mgdl),
            trailing: mgdl != null && trend != null
                ? GlucoseTrendIcon(perMin: trend, color: glucoseColor, size: 22)
                : null,
          ),
          ListenableBuilder(
            listenable: _monitor,
            builder: (context, _) {
              // Keep the last known bpm on screen; the Fitbit drops/rescans
              // between deliveries and status briefly leaves `streaming`, which
              // otherwise flickered the value back to '–'.
              final bpm = _monitor.bpm;
              return _reading(
                PhosphorIconsFill.heart,
                bpm != null
                    ? _pulseColor(bpm)
                    : scheme.onSurface.withValues(alpha: 0.3),
                bpm != null ? '$bpm bpm' : '–',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _reading(IconData icon, Color color, String text, {Widget? trailing}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 4), trailing],
      ],
    );
  }
}
