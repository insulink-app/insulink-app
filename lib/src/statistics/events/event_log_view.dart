import 'package:flutter/material.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';

/// Chronological log of notable events over the selected statistics window:
/// glucose lows/highs, signal loss, and sensor swap/stop. Reads the store-backed
/// event log via [G7Controller.statsEvents] (newest first).
class EventLogView extends StatelessWidget {
  const EventLogView({super.key});

  @override
  Widget build(BuildContext context) {
    final events = context.watch<G7Controller>().statsEvents;
    final glucose = context.watch<ProfileGlucoseState>();
    if (events.isEmpty) {
      return Center(child: LocaleText('statistics.events.empty'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: events.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) =>
          _EventRow(event: events[index], glucose: glucose),
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
    final value = event.value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(style.icon, color: style.color),
      title: LocaleText('statistics.events.type.${event.type}'),
      subtitle: value == null
          ? null
          : Text(
              _formatGlucose(value),
              style: TextStyle(fontWeight: FontWeight.w600, color: style.color),
            ),
      trailing: Text(
        _formatWhen(context, event.time),
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
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
