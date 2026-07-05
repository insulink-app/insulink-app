import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/sport/training/cardio_models.dart';
import 'package:insulink/src/sport/training/cardio_training_state.dart';
import 'package:insulink/src/sport/training/cardio_training_tile.dart';
import 'package:provider/provider.dart';

/// Full list of recorded trainings (newest first), revealed a chunk at a time
/// via a "Show more" button. Reached from the sport home section.
class CardioLogPage extends StatefulWidget {
  const CardioLogPage({super.key});

  @override
  State<CardioLogPage> createState() => _CardioLogPageState();
}

class _CardioLogPageState extends State<CardioLogPage> {
  static const _chunk = 15;
  int _shown = _chunk;

  @override
  Widget build(BuildContext context) {
    final trainings = context.watch<CardioTrainingState>().trainings.reversed
        .toList();
    final visible = trainings.take(_shown).toList();
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: LocaleText('sport.trainings.all'),
      ),
      body: trainings.isEmpty
          ? Center(child: LocaleText('sport.trainings.empty'))
          : ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [
                for (var index = 0; index < visible.length; index++) ...[
                  if (_startsNewDay(visible, index))
                    Padding(
                      padding: EdgeInsets.only(top: index == 0 ? 0 : 20, bottom: 8),
                      child: Text(
                        MaterialLocalizations.of(context).formatFullDate(
                          DateTime.fromMillisecondsSinceEpoch(
                            visible[index].startMs,
                          ),
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: CardioTrainingTile(
                      training: visible[index],
                      showDate: false,
                    ),
                  ),
                ],
                if (_shown < trainings.length)
                  TextButton(
                    onPressed: () => setState(() => _shown += _chunk),
                    child: LocaleText('sport.trainings.show_more'),
                  ),
              ],
            ),
    );
  }

  /// True when [index] belongs to a different calendar day than the item
  /// before it — i.e. it opens a new day section.
  bool _startsNewDay(List<CardioTraining> items, int index) {
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
