import 'package:flutter/material.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';

/// Chronological log of notable events over the selected statistics window:
/// glucose lows/highs, signal loss, and sensor swap/stop. Reads the store-backed
/// event log via [CgmController.statsEvents] (newest first).
class EventLogView extends StatelessWidget {
  const EventLogView({super.key});

  @override
  Widget build(BuildContext context) {
    final events = context.watch<CgmController>().statsEvents;
    final glucose = context.watch<ProfileGlucoseState>();
    if (events.isEmpty) {
      return Center(child: LocaleText('statistics.events.empty'));
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          itemCount: events.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) =>
              _EventRow(event: events[index], glucose: glucose),
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.glucose});

  final ({DateTime time, String type, int? value}) event;
  final ProfileGlucoseState glucose;

  @override
  Widget build(BuildContext context) {
    final style = _EventStyle.of(event.type, context);
    final scheme = Theme.of(context).colorScheme;
    final value = event.value;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: style.color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(style.icon, color: style.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocaleText(
                  'statistics.events.type.${event.type}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (value != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatGlucose(value),
                    style: TextStyle(fontSize: 13, color: style.color),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatWhen(context, event.time),
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// The triggering glucose value in the user's display unit (e.g. "62 mg/dL").
  String _formatGlucose(int mgdl) {
    final shown = glucose.unit == GlucoseUnit.mmol
        ? glucose.toDisplay(mgdl).toStringAsFixed(1)
        : '$mgdl';
    return '$shown ${glucose.unit.label}';
  }

  /// "DD.MM.  HH:MM" in the platform locale's formats.
  String _formatWhen(BuildContext context, DateTime time) {
    final locale = MaterialLocalizations.of(context);
    final date = locale.formatShortDate(time);
    final clock = locale.formatTimeOfDay(TimeOfDay.fromDateTime(time));
    return '$date  $clock';
  }
}

/// The icon + colour for an event type. Unknown types fall back to a neutral
/// dot so a future event slug still renders.
class _EventStyle {
  const _EventStyle(this.icon, this.color);
  final IconData icon;
  final Color color;

  static _EventStyle of(String type, BuildContext context) {
    final colors = Theme.of(context).extension<GlucoseColors>()!;
    final scheme = Theme.of(context).colorScheme;
    switch (type) {
      case 'glucose_low':
      case 'glucose_low_urgent':
        return _EventStyle(Icons.arrow_downward, colors.low);
      case 'glucose_high':
      case 'glucose_high_urgent':
        return _EventStyle(Icons.arrow_upward, colors.high);
      case 'signal_loss':
        return _EventStyle(Icons.wifi_off, scheme.onSurface);
      case 'new_sensor':
        return _EventStyle(Icons.add_circle_outline, colors.inRange);
      case 'sensor_stopped':
        return _EventStyle(Icons.stop_circle_outlined, scheme.onSurface);
      default:
        return _EventStyle(Icons.circle, scheme.onSurface);
    }
  }
}
