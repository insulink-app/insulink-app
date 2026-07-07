import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/activity/activity_entry.dart';
import 'package:insulink/src/sport/activity/activity_tile.dart';
import 'package:insulink/src/sport/calendar/sport_calendar_page.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training_state.dart';
import 'package:provider/provider.dart';

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
            icon: const Icon(Icons.calendar_month),
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
          ? Center(child: LocaleText('sport.logbook.empty'))
          : ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [
                for (var index = 0; index < visible.length; index++) ...[
                  if (_startsNewDay(visible, index))
                    _dayHeader(context, visible[index].startMs, index == 0),
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

  Widget _dayHeader(BuildContext context, int startMs, bool first) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 20, bottom: 8),
      child: Text(
        MaterialLocalizations.of(context).formatFullDate(
          DateTime.fromMillisecondsSinceEpoch(startMs),
        ),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
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
