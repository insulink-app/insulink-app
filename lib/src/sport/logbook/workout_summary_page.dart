import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/sport/logbook/workout_metrics_chart.dart';
import 'package:insulink/src/sport/logbook/workout_set_list.dart';
import 'package:insulink/src/sport/logbook/workout_summary_card.dart';
import 'package:insulink/src/sport/sport_models.dart';

/// Shown once a workout is finished, in place of the runner: the session's
/// numbers next to the previous time (see [WorkoutSummaryCard]). "Done" closes
/// back to the sport page. The session is already saved by the time this opens.
class WorkoutSummaryPage extends StatelessWidget {
  const WorkoutSummaryPage({super.key, required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: Text(Locales.string(context, 'sport.summary')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            InkSpace.panelMargin,
            12,
            InkSpace.panelMargin,
            20,
          ),
          children: [
            WorkoutSummaryCard(session: session),
            const SizedBox(height: 24),
            WorkoutMetricsChart(session: session),
            const SizedBox(height: 8),
            WorkoutSetList(session: session),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: LocaleText('sport.summary.done'),
          ),
        ),
      ),
    );
  }
}
