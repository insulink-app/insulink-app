import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/activity/activity_entry.dart';
import 'package:insulink/src/sport/activity/activity_log_page.dart';
import 'package:insulink/src/sport/activity/activity_tile.dart';
import 'package:insulink/src/sport/activity/current_activity_banners.dart';
import 'package:insulink/src/sport/calendar/sport_calendar_page.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// "Activities" section of the sport home page: the three most recent logged
/// activities (routines + trainings merged) with a calendar shortcut and a
/// "Show more" into the shared logbook.
class RecentActivitiesSection extends StatelessWidget {
  const RecentActivitiesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = mergedActivities(
      context.watch<TrainingState>().sessions,
      context.watch<CardioTrainingState>().trainings,
    );
    final recent = entries.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LocaleText(
              'sport.activities',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(PhosphorIconsBold.calendarBlank, size: 20),
              tooltip: Locales.string(context, 'sport.calendar'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SportCalendarPage(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const CurrentActivityBanners(),
        if (recent.isEmpty)
          LocaleText('sport.activities.empty')
        else
          for (final entry in recent)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ActivityTile(entry: entry),
            ),
        if (entries.length > recent.length)
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ActivityLogPage()),
            ),
            child: LocaleText('sport.trainings.show_more'),
          ),
      ],
    );
  }
}
