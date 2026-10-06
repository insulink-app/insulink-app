import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/training/cardio_detail_page.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_type_ui.dart';
import 'package:insulink/src/sport/sport_leading_badge.dart';
import 'package:insulink/src/base/list_row.dart';
import 'package:insulink/src/base/relative_day.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// One recorded training as a tappable list tile (type, date, distance,
/// duration). Shared by the sport home section and the full trainings log.
class CardioTrainingTile extends StatelessWidget {
  const CardioTrainingTile({
    super.key,
    required this.training,
    this.showDate = true,
  });

  final CardioTraining training;

  /// Whether the trailing corner shows the date above the time. The log page
  /// groups by day already, so it passes `false` to show only the time.
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = MaterialLocalizations.of(context);
    final started = DateTime.fromMillisecondsSinceEpoch(training.startMs);
    return ListTile(
      tileColor: scheme.onSurface.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      leading: SportLeadingBadge(icon: training.type.icon),
      title: Text(
        Locales.string(context, training.type.labelKey),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${formatDistanceKm(training.distanceM)} · ${formatDuration(training.duration)}'
        '${training.detected ? ' · ${Locales.string(context, 'sport.trainings.detected')}' : ''}',
      ),
      trailing: _trailing(context, locale, started),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CardioDetailPage(training: training),
        ),
      ),
    );
  }

  /// Right-hand corner: the time, with the date stacked above it on the
  /// overview (where there is no day section header).
  Widget _trailing(
    BuildContext context,
    MaterialLocalizations locale,
    DateTime started,
  ) {
    final time = locale.formatTimeOfDay(
      TimeOfDay.fromDateTime(started),
      alwaysUse24HourFormat: true,
    );
    if (!showDate) {
      return Text(time, style: InkText.row);
    }
    return ListRowMeta(date: RelativeDay(started).label(context), time: time);
  }
}
