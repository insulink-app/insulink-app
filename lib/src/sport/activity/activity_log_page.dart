import 'package:flutter/material.dart';
import 'package:insulink/src/base/day_section_header.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/activity/activity_entry.dart';
import 'package:insulink/src/sport/activity/activity_tile.dart';
import 'package:insulink/src/sport/calendar/sport_calendar_page.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Shared logbook of every logged activity — routines and endurance trainings
/// merged, newest first, grouped by day. Revealed a chunk at a time. A calendar
/// button in the app bar jumps to the month view.
class ActivityLogPage extends StatefulWidget {
  const ActivityLogPage({super.key});

  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  static const _chunk = 15;
  int _shown = _chunk;

  @override
  Widget build(BuildContext context) {
    final entries = mergedActivities(
      context.watch<TrainingState>().sessions,
      context.watch<CardioTrainingState>().trainings,
    );
    final visible = entries.take(_shown).toList();
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('sport.logbook'),
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsBold.calendarBlank),
            tooltip: Locales.string(context, 'sport.calendar'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SportCalendarPage(),
              ),
            ),
          ),
        ],
      ),
      body: entries.isEmpty
          ? const EmptyState(
              icon: PhosphorIconsBold.calendarBlank,
              titleKey: 'sport.logbook.empty',
            )
          : ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [
                for (var index = 0; index < visible.length; index++) ...[
                  if (_startsNewDay(visible, index))
                    DaySectionHeader(
                      day: DateTime.fromMillisecondsSinceEpoch(
                        visible[index].startMs,
                      ),
                      first: index == 0,
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ActivityTile(entry: visible[index], showDate: false),
                  ),
                ],
                if (_shown < entries.length)
                  TextButton(
                    onPressed: () => setState(() => _shown += _chunk),
                    child: LocaleText('sport.trainings.show_more'),
                  ),
              ],
            ),
    );
  }

  /// True when [index] falls on a different calendar day than the item before
  /// it — i.e. it opens a new day section.
  bool _startsNewDay(List<ActivityEntry> items, int index) {
    if (index == 0) {
      return true;
    }
    return !_sameDay(items[index].startMs, items[index - 1].startMs);
  }

  bool _sameDay(int aMs, int bMs) {
    final first = DateTime.fromMillisecondsSinceEpoch(aMs);
    final second = DateTime.fromMillisecondsSinceEpoch(bMs);
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }
}
