import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/glucose/profile_glucose_state.dart';
import 'package:insulink/src/theme/glucose_colors.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/list_row.dart';
import 'package:insulink/src/base/relative_day.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/sport_format.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// Chronological log of notable events over the selected analysis window:
/// glucose lows/highs, signal loss, and sensor swap/stop. Reads the store-backed
/// event log via [CgmController.statsEvents] (newest first).
class EventLogView extends StatelessWidget {
  const EventLogView({super.key});

  @override
  Widget build(BuildContext context) {
    final events = context.watch<CgmController>().statsEvents;
    final glucose = context.watch<ProfileGlucoseState>();
    if (events.isEmpty) {
      return const EmptyState(
        icon: PhosphorIconsBold.calendarBlank,
        titleKey: 'analysis.events.empty',
      );
    }
    final colors = Theme.of(context).extension<GlucoseColors>()!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        InkSpace.panelMargin,
        8,
        InkSpace.panelMargin,
        120,
      ),
      children: [
        Row(
          spacing: InkSpace.tileGap,
          children: [
            Expanded(
              child: _Counter(
                labelKey: 'analysis.events.count_low',
                color: colors.low,
                count: _count(events, 'glucose_low'),
              ),
            ),
            Expanded(
              child: _Counter(
                labelKey: 'analysis.events.count_high',
                color: colors.high,
                count: _count(events, 'glucose_high'),
              ),
            ),
          ],
        ),
        const SizedBox(height: InkSpace.tileGap),
        InkPanel.list(
          rows: [
            for (final event in events)
              _EventRow(event: event, glucose: glucose),
          ],
        ),
      ],
    );
  }

  /// Events of a kind, the urgent ones included ("glucose_low_urgent").
  int _count(
    List<({DateTime time, String type, int? value})> events,
    String kind,
  ) => events.where((event) => event.type.startsWith(kind)).length;
}

/// One count above the list: a dot in the zone colour, the kind, the number.
class _Counter extends StatelessWidget {
  const _Counter({
    required this.labelKey,
    required this.color,
    required this.count,
  });

  final String labelKey;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return InkPanel(
      radius: InkRadius.tile,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        spacing: 10,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: LocaleText(
              labelKey,
              style: InkText.body.copyWith(
                fontWeight: FontWeight.w400,
                color: colors.muted,
              ),
            ),
          ),
          Text('$count', style: InkText.bigValue.copyWith(fontSize: 22)),
        ],
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
    final value = event.value;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(event.time),
      alwaysUse24HourFormat: true,
    );
    return ListRow(
      icon: style.icon,
      glyphColor: style.color,
      title: Locales.string(context, 'analysis.events.type.${event.type}'),
      subtitle: value == null ? null : _formatGlucose(value),
      subtitleColor: style.color,
      trailing: ListRowMeta(
        date: RelativeDay(event.time).label(context),
        time: time,
      ),
    );
  }

  /// The triggering glucose value in the user's display unit (e.g. "62 mg/dL").
  String _formatGlucose(int mgdl) {
    final shown = glucose.unit == GlucoseUnit.mmol
        ? sportDecimal(glucose.toDisplay(mgdl), 1)
        : '$mgdl';
    return '$shown ${glucose.unit.label}';
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
        return _EventStyle(PhosphorIconsBold.arrowDown, colors.low);
      case 'glucose_high':
      case 'glucose_high_urgent':
        return _EventStyle(PhosphorIconsBold.arrowUp, colors.high);
      case 'signal_loss':
        return _EventStyle(
          PhosphorIconsBold.wifiSlash,
          scheme.onSurfaceVariant,
        );
      case 'new_sensor':
        return _EventStyle(PhosphorIconsBold.plusCircle, colors.inRange);
      case 'sensor_stopped':
        return _EventStyle(PhosphorIconsBold.stopCircle, scheme.onSurface);
      default:
        return _EventStyle(PhosphorIconsFill.circle, scheme.onSurface);
    }
  }
}
